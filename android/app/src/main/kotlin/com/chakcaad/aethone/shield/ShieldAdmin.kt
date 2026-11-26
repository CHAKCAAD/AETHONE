package com.chakcaad.aethone.shield

/// Family Shield — the admin API behind the `aethone/family_shield` method
/// channel (pure JVM, unit-tested). Native (this class + the SQLite store) is
/// the source of truth; Flutter only calls in.
///
/// Every call answers a Map. Success: `ok = true` (+ data). Failure:
/// `ok = false`, `error` = a stable machine code (Flutter maps it to a
/// localized AppStrings text; no user-visible text originates here).
///
/// Gating: every operation that CHANGES protection, or reads the event log /
/// history, needs a live parent session `token` from the PIN core
/// (pinVerify / pinRecover). Read-only configuration views (profiles, rules,
/// app restrictions, pinState) need none — they reveal nothing secret.
///
/// `changed = true` in an answer tells the caller (ShieldChannel) to apply
/// the new configuration live (FamilyShield.applyLive: atomic snapshot swap
/// + flow revalidation, no tunnel restart).
class ShieldAdmin(
    private val repo: ShieldRepository,
    private val pin: ParentPin,
    private val clock: () -> Long = System::currentTimeMillis,
) {
    private val profiles = ProfileManager(repo, clock)

    class AdminError(val code: String) : RuntimeException(code)

    companion object {
        /// operations that need a parent session
        val GATED = setOf(
            "setEnabled", "createProfile", "switchProfile", "deleteProfile",
            "setCategory", "setUnknownPolicy", "setStrict", "resetToPreset",
            "addRule", "removeRule", "restrictApp", "setLogging",
            "events", "history", "pinChange", "setBiometric",
        )
        const val MAX_RULES_PER_PROFILE = 5000
        const val MAX_PROFILES = 16
    }

    fun handle(method: String, args: Map<String, Any?>): Map<String, Any?> = try {
        if (method in GATED && !pin.checkToken(args["token"] as? String)) throw AdminError("session-required")
        dispatch(method, args)
    } catch (e: AdminError) {
        mapOf("ok" to false, "error" to e.code)
    } catch (e: IllegalArgumentException) {
        mapOf("ok" to false, "error" to "invalid-argument", "detail" to (e.message ?: ""))
    } catch (e: IllegalStateException) {
        mapOf("ok" to false, "error" to "invalid-state", "detail" to (e.message ?: ""))
    }

    private fun str(a: Map<String, Any?>, k: String): String =
        (a[k] as? String)?.takeIf { it.isNotBlank() } ?: throw IllegalArgumentException("missing $k")

    private fun bool(a: Map<String, Any?>, k: String): Boolean =
        a[k] as? Boolean ?: throw IllegalArgumentException("missing $k")

    private fun long(a: Map<String, Any?>, k: String): Long =
        (a[k] as? Number)?.toLong() ?: throw IllegalArgumentException("missing $k")

    private fun ok(vararg kv: Pair<String, Any?>): Map<String, Any?> = mapOf("ok" to true, *kv)

    private fun changed(vararg kv: Pair<String, Any?>): Map<String, Any?> = mapOf("ok" to true, "changed" to true, *kv)

    private fun dispatch(m: String, a: Map<String, Any?>): Map<String, Any?> = when (m) {
        // ---- PIN core ----
        "pinState" -> {
            val s = repo.pinState()
            ok(
                "set" to (s != null),
                "biometric" to (s?.biometricEnabled ?: false),
                "lockedUntil" to (s?.lockedUntil ?: 0L),
                "recoveryAvailable" to (s != null && !s.recoveryUsed),
            )
        }
        "pinSetup" -> {
            if (pin.isSet) throw AdminError("pin-already-set")
            val p = str(a, "pin")
            ParentPin.pinProblem(p)?.let { throw AdminError("weak-pin:$it") }
            val code = pin.setup(p, a["biometric"] as? Boolean ?: false)
            ok("recoveryCode" to code)
        }
        "pinVerify" -> pinResult(pin.verify(str(a, "pin")))
        "pinRecover" -> pinResult(pin.recover(str(a, "code")))
        "pinChange" -> {
            val p = str(a, "newPin")
            ParentPin.pinProblem(p)?.let { throw AdminError("weak-pin:$it") }
            ok("recoveryCode" to pin.change(str(a, "token"), p))
        }
        "setBiometric" -> { pin.setBiometric(str(a, "token"), bool(a, "on")); ok() }
        "endSession" -> { pin.endSessions(); ok() }

        // ---- shield on/off ----
        "setEnabled" -> {
            val on = bool(a, "enabled")
            val cfg = repo.config()
            if (on) {
                if (!pin.isSet) throw AdminError("pin-not-set")
                val active = cfg.activeProfileId?.let { repo.profile(it) } ?: throw AdminError("no-active-profile")
                if (active.id.isEmpty()) throw AdminError("no-active-profile")
            }
            repo.saveConfig(cfg.copy(enabled = on, generation = cfg.generation + 1, updatedAt = clock()))
            changed("enabled" to on, "restartRequired" to true)
        }
        "config" -> {
            val c = repo.config()
            ok("enabled" to c.enabled, "activeProfileId" to c.activeProfileId, "logDomains" to c.logDomains,
                "retentionDays" to c.retentionDays, "generation" to c.generation)
        }
        "setLogging" -> {
            val c = repo.config()
            val days = (a["retentionDays"] as? Number)?.toInt() ?: c.retentionDays
            if (days !in 1..365) throw IllegalArgumentException("retentionDays out of range")
            repo.saveConfig(c.copy(logDomains = a["logDomains"] as? Boolean ?: c.logDomains, retentionDays = days, updatedAt = clock()))
            changed()
        }

        // ---- profiles ----
        "profiles" -> ok("profiles" to repo.profiles().map(::profileMap), "activeProfileId" to repo.config().activeProfileId)
        "createProfile" -> {
            if (repo.profiles().size >= MAX_PROFILES) throw AdminError("too-many-profiles")
            val preset = AgePreset.byKey(str(a, "preset")) ?: throw IllegalArgumentException("unknown preset")
            val p = profiles.create((a["name"] as? String ?: "").take(64), preset)
            changed("profile" to profileMap(p))
        }
        "switchProfile" -> { profiles.switchTo(str(a, "id"), "parent"); changed("activeProfileId" to str(a, "id")) }
        "deleteProfile" -> { profiles.delete(str(a, "id")); changed() }
        "resetToPreset" -> {
            val preset = AgePreset.byKey(str(a, "preset")) ?: throw IllegalArgumentException("unknown preset")
            changed("profile" to profileMap(profiles.resetToPreset(str(a, "profileId"), preset)))
        }
        "setCategory" -> {
            val c = ShieldCategory.byKey(str(a, "category")) ?: throw IllegalArgumentException("unknown category")
            if (c.mandatory) throw AdminError("mandatory-category")
            changed("profile" to profileMap(profiles.setCategory(str(a, "profileId"), c, bool(a, "on"))))
        }
        "setUnknownPolicy" -> {
            val pol = when (str(a, "policy")) { "allow" -> UnknownPolicy.ALLOW; "block" -> UnknownPolicy.BLOCK; else -> throw IllegalArgumentException("policy") }
            changed("profile" to profileMap(profiles.setUnknownPolicy(str(a, "profileId"), pol)))
        }
        "setStrict" -> {
            @Suppress("UNCHECKED_CAST")
            val s = a["strict"] as? Map<String, Any?> ?: throw IllegalArgumentException("missing strict")
            val d = StrictOptions()
            val opt = StrictOptions(
                enabled = s["enabled"] as? Boolean ?: d.enabled,
                blockDot = s["blockDot"] as? Boolean ?: d.blockDot,
                blockQuic = s["blockQuic"] as? Boolean ?: d.blockQuic,
                blockAltDns = s["blockAltDns"] as? Boolean ?: d.blockAltDns,
                blockDirectIp = s["blockDirectIp"] as? Boolean ?: d.blockDirectIp,
            )
            changed("profile" to profileMap(profiles.setStrict(str(a, "profileId"), opt)))
        }

        // ---- rules ----
        "rules" -> ok("rules" to repo.rules(str(a, "profileId")).map(::ruleMap))
        "addRule" -> {
            val pid = str(a, "profileId")
            if (repo.rules(pid).size >= MAX_RULES_PER_PROFILE) throw AdminError("too-many-rules")
            val kind = RuleKind.entries.firstOrNull { it.name.equals(str(a, "kind"), true) } ?: throw IllegalArgumentException("kind")
            val action = RuleAction.entries.firstOrNull { it.name.equals(str(a, "action"), true) } ?: throw IllegalArgumentException("action")
            val r = profiles.addRule(pid, kind, str(a, "value"), action, (a["note"] as? String)?.take(200))
            changed("rule" to ruleMap(r))
        }
        "removeRule" -> { profiles.removeRule(str(a, "id")); changed() }
        "appRestrictions" -> ok("apps" to repo.appRestrictions(str(a, "profileId")).map { it.packageName })
        "restrictApp" -> { profiles.restrictApp(str(a, "profileId"), str(a, "package"), bool(a, "on")); changed() }

        // ---- events / history (aggregated only; never URLs) ----
        "events" -> {
            val to = (a["to"] as? Number)?.toLong() ?: clock()
            val from = (a["from"] as? Number)?.toLong() ?: (to - 86_400_000L)
            if (from > to || to - from > 400L * 86_400_000L) throw IllegalArgumentException("range")
            ok("events" to aggregate(repo.events(from, to)))
        }
        "history" -> ok("history" to repo.history(((a["limit"] as? Number)?.toInt() ?: 50).coerceIn(1, 500)).map {
            mapOf("at" to it.at, "from" to it.fromProfileId, "to" to it.toProfileId, "reason" to it.reason)
        })
        else -> throw AdminError("unknown-method")
    }

    private fun pinResult(r: ParentPin.Result): Map<String, Any?> = when (r) {
        is ParentPin.Result.Ok -> ok("token" to r.token, "expiresAt" to r.expiresAt)
        is ParentPin.Result.Wrong -> mapOf("ok" to false, "error" to "wrong-pin", "attemptsBeforeLock" to r.attemptsBeforeLock, "lockedUntil" to r.lockedUntil)
        is ParentPin.Result.Locked -> mapOf("ok" to false, "error" to "locked", "lockedUntil" to r.until)
        ParentPin.Result.NotSet -> mapOf("ok" to false, "error" to "pin-not-set")
    }

    /// Batched rows → per (kind, level, category, app[, domain]) totals for
    /// the requested window; the minute buckets stay in the store.
    fun aggregate(rows: List<EventBucket>): List<Map<String, Any?>> {
        data class K(val kind: String, val level: Int, val category: String?, val app: String?, val domain: String?)
        val acc = LinkedHashMap<K, LongArray>()
        for (r in rows) {
            val k = K(r.kind, r.level, r.category, r.app, r.domain)
            val v = acc.getOrPut(k) { longArrayOf(0L, Long.MAX_VALUE, 0L) }
            v[0] += r.count
            v[1] = minOf(v[1], r.minute)
            v[2] = maxOf(v[2], r.minute)
        }
        return acc.entries.sortedByDescending { it.value[0] }.map { (k, v) ->
            mapOf("kind" to k.kind, "level" to k.level, "category" to k.category, "app" to k.app,
                "domain" to k.domain, "count" to v[0], "first" to v[1], "last" to v[2])
        }
    }

    fun profileMap(p: AgeProfile): Map<String, Any?> = mapOf(
        "id" to p.id, "name" to p.name, "preset" to p.preset.key,
        "categories" to p.categories.map { it.key }.sorted(),
        "allowCategories" to p.allowCategories.map { it.key }.sorted(),
        "unknownPolicy" to p.unknownPolicy.name.lowercase(),
        "strict" to mapOf("enabled" to p.strict.enabled, "blockDot" to p.strict.blockDot, "blockQuic" to p.strict.blockQuic,
            "blockAltDns" to p.strict.blockAltDns, "blockDirectIp" to p.strict.blockDirectIp),
        "updatedAt" to p.updatedAt,
    )

    fun ruleMap(r: ParentRule): Map<String, Any?> = mapOf(
        "id" to r.id, "profileId" to r.profileId, "kind" to r.kind.name.lowercase(), "value" to r.value,
        "action" to r.action.name.lowercase(), "note" to r.note, "createdAt" to r.createdAt,
    )
}
