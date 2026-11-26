package com.chakcaad.aethone.shield

/// Settings export / import (phase 2, pure JVM, unit-tested).
///
/// Why it exists: the release-key rotation gives AETHONE a NEW signature, so
/// the next release can not be installed as an update over an old-key
/// install — the user uninstalls and reinstalls (docs/migration-plan.md). This
/// file carries the user's settings across that reinstall.
///
/// Exported (file `aethone-settings-<stamp>.json`, user-chosen location):
///  * app settings: every `aethone.settings.*` preference the Flutter side
///    persists (protocol, locations, routing region, per-app tunneling,
///    hybrid routing rules, core settings, kill switch, look) with its type;
///  * Family Shield configuration: profiles, parent rules, app
///    restrictions, logging options, the active profile.
///
/// NEVER exported: the parent PIN hash/salt, the recovery code hash, the
/// Keystore pepper (it can not leave the Keystore at all), admin sessions,
/// protection events and profile history. A PIN hash is peppered with a
/// device-bound Keystore key, so it would not verify on the new install
/// anyway — and carrying it would only give an attacker an offline target.
/// The parent sets a NEW PIN after import; until then the imported shield
/// stays DISABLED (fail-safe: no protection is claimed without a PIN).
object SettingsBackup {
    const val FORMAT = "aethone-settings"
    const val VERSION = 1
    const val MAX_BYTES = 2 * 1024 * 1024
    const val PREF_PREFIX = "aethone.settings."
    private const val MAX_PREFS = 200
    private const val MAX_PREF_STRING = 256 * 1024

    class BackupError(val code: String) : IllegalArgumentException(code)

    /// One typed preference value: s = String, b = Boolean, l = Long,
    /// i = Int, d = Double, f = Float (the Android SharedPreferences types).
    data class Pref(val key: String, val type: String, val value: Any)

    data class ShieldPart(
        val activeProfileId: String?,
        val logDomains: Boolean,
        val retentionDays: Int,
        val profiles: List<AgeProfile>,
        val rules: List<ParentRule>,
        val apps: List<AppRestriction>,
    )

    data class Parsed(val createdAt: Long, val appVersion: String?, val prefs: List<Pref>, val shield: ShieldPart?)

    fun export(prefs: List<Pref>, repo: ShieldRepository?, now: Long, appVersion: String?): String {
        val p = prefs.filter { it.key.startsWith(PREF_PREFIX) }.sortedBy { it.key }.map {
            mapOf("key" to it.key, "type" to it.type, "value" to it.value)
        }
        val root = LinkedHashMap<String, Any?>()
        root["format"] = FORMAT
        root["version"] = VERSION
        root["createdAt"] = now
        root["appVersion"] = appVersion
        root["note"] = "No PIN, recovery code, keys or event logs are included. Set a new parent PIN after import."
        root["app"] = mapOf("prefs" to p)
        if (repo != null) {
            val cfg = repo.config()
            val profs = repo.profiles()
            root["familyShield"] = mapOf(
                "enabledAtExport" to cfg.enabled,
                "activeProfileId" to cfg.activeProfileId,
                "logDomains" to cfg.logDomains,
                "retentionDays" to cfg.retentionDays,
                "profiles" to profs.map { pr ->
                    mapOf(
                        "id" to pr.id, "name" to pr.name, "preset" to pr.preset.key,
                        "categories" to pr.categories.map { it.key }.sorted(),
                        "allowCategories" to pr.allowCategories.map { it.key }.sorted(),
                        "unknownPolicy" to pr.unknownPolicy.name.lowercase(),
                        "strict" to mapOf("enabled" to pr.strict.enabled, "blockDot" to pr.strict.blockDot,
                            "blockQuic" to pr.strict.blockQuic, "blockAltDns" to pr.strict.blockAltDns,
                            "blockDirectIp" to pr.strict.blockDirectIp),
                        "rules" to repo.rules(pr.id).map { r ->
                            mapOf("kind" to r.kind.name.lowercase(), "value" to r.value, "action" to r.action.name.lowercase(), "note" to r.note)
                        },
                        "apps" to repo.appRestrictions(pr.id).map { it.packageName },
                    )
                },
            )
        }
        return MiniJson.write(root)
    }

    @Suppress("UNCHECKED_CAST")
    fun parse(text: String): Parsed {
        if (text.length > MAX_BYTES) throw BackupError("too-large")
        val root = try { MiniJson.parse(text) } catch (_: MiniJson.ParseError) { throw BackupError("not-json") }
            as? Map<String, Any?> ?: throw BackupError("not-an-object")
        if (root["format"] != FORMAT) throw BackupError("wrong-format")
        val version = (root["version"] as? Long) ?: throw BackupError("no-version")
        if (version > VERSION) throw BackupError("newer-version:$version")
        if (version < 1) throw BackupError("bad-version")
        val created = (root["createdAt"] as? Long) ?: 0L
        val app = root["app"] as? Map<String, Any?> ?: throw BackupError("no-app-section")
        val rawPrefs = app["prefs"] as? List<Any?> ?: throw BackupError("no-prefs")
        if (rawPrefs.size > MAX_PREFS) throw BackupError("too-many-prefs")
        val prefs = rawPrefs.map { e ->
            val m = e as? Map<String, Any?> ?: throw BackupError("bad-pref")
            val key = m["key"] as? String ?: throw BackupError("bad-pref-key")
            if (!key.startsWith(PREF_PREFIX) || key.length > 128 || !key.all { it.isLetterOrDigit() || it in "._-" }) throw BackupError("bad-pref-key:$key")
            val type = m["type"] as? String ?: throw BackupError("bad-pref-type")
            val v = m["value"]
            val value: Any = when (type) {
                "s" -> (v as? String)?.also { if (it.length > MAX_PREF_STRING) throw BackupError("pref-too-large:$key") }
                "b" -> v as? Boolean
                "l" -> v as? Long
                "i" -> (v as? Long)?.takeIf { it in Int.MIN_VALUE..Int.MAX_VALUE }?.toInt()
                "d" -> (v as? Number)?.toDouble()
                "f" -> (v as? Number)?.toFloat()
                else -> null
            } ?: throw BackupError("bad-pref-value:$key")
            Pref(key, type, value)
        }
        if (prefs.map { it.key }.toSet().size != prefs.size) throw BackupError("duplicate-pref")
        val fs = root["familyShield"] as? Map<String, Any?>
        val shield = fs?.let { parseShield(it, created) }
        return Parsed(created, root["appVersion"] as? String, prefs, shield)
    }

    @Suppress("UNCHECKED_CAST")
    private fun parseShield(fs: Map<String, Any?>, now: Long): ShieldPart {
        val list = fs["profiles"] as? List<Any?> ?: throw BackupError("shield-no-profiles")
        if (list.size > ShieldAdmin.MAX_PROFILES) throw BackupError("shield-too-many-profiles")
        val profiles = ArrayList<AgeProfile>()
        val rules = ArrayList<ParentRule>()
        val apps = ArrayList<AppRestriction>()
        for ((pi, e) in list.withIndex()) {
            val m = e as? Map<String, Any?> ?: throw BackupError("shield-bad-profile")
            val id = (m["id"] as? String)?.takeIf { it.length in 1..64 && it.all { c -> c.isLetterOrDigit() || c in "_-" } }
                ?: throw BackupError("shield-bad-profile-id")
            if (profiles.any { it.id == id }) throw BackupError("shield-duplicate-profile")
            val preset = AgePreset.byKey(m["preset"] as? String ?: "") ?: throw BackupError("shield-bad-preset")
            fun cats(k: String, allow: Boolean): Set<ShieldCategory> = ((m[k] as? List<Any?>) ?: emptyList()).map {
                val c = ShieldCategory.byKey(it as? String ?: "") ?: throw BackupError("shield-bad-category")
                if (c.mandatory) throw BackupError("shield-mandatory-category")
                if (c.allowList != allow) throw BackupError("shield-bad-category")
                c
            }.toSet()
            val st = m["strict"] as? Map<String, Any?> ?: emptyMap()
            val d = StrictOptions()
            profiles += AgeProfile(
                id = id,
                name = ((m["name"] as? String) ?: preset.key).take(64),
                preset = preset,
                categories = cats("categories", false),
                unknownPolicy = when (m["unknownPolicy"]) { "block" -> UnknownPolicy.BLOCK; "allow" -> UnknownPolicy.ALLOW; else -> throw BackupError("shield-bad-unknown-policy") },
                strict = StrictOptions(
                    st["enabled"] as? Boolean ?: d.enabled, st["blockDot"] as? Boolean ?: d.blockDot,
                    st["blockQuic"] as? Boolean ?: d.blockQuic, st["blockAltDns"] as? Boolean ?: d.blockAltDns,
                    st["blockDirectIp"] as? Boolean ?: d.blockDirectIp,
                ),
                allowCategories = cats("allowCategories", true),
                updatedAt = now,
            )
            val rl = (m["rules"] as? List<Any?>) ?: emptyList()
            if (rl.size > ShieldAdmin.MAX_RULES_PER_PROFILE) throw BackupError("shield-too-many-rules")
            for ((ri, re) in rl.withIndex()) {
                val r = re as? Map<String, Any?> ?: throw BackupError("shield-bad-rule")
                val kind = RuleKind.entries.firstOrNull { it.name.equals(r["kind"] as? String ?: "", true) } ?: throw BackupError("shield-bad-rule-kind")
                val action = RuleAction.entries.firstOrNull { it.name.equals(r["action"] as? String ?: "", true) } ?: throw BackupError("shield-bad-rule-action")
                val raw = r["value"] as? String ?: throw BackupError("shield-bad-rule-value")
                // same normalization / validation as a rule typed in by the parent
                val value = when (kind) {
                    RuleKind.CIDR -> Cidr.parse(raw)?.toString()
                    RuleKind.WILDCARD -> DomainNames.normalize(raw.trim().removePrefix("*."))
                    else -> DomainNames.normalize(raw)
                } ?: throw BackupError("shield-bad-rule-value")
                rules += ParentRule("r${pi}x$ri" + id.take(8), id, kind, value, action, (r["note"] as? String)?.take(200), now)
            }
            for (a in (m["apps"] as? List<Any?>) ?: emptyList()) {
                val pkg = (a as? String)?.takeIf { it.length in 1..255 && it.all { c -> c.isLetterOrDigit() || c in "._" } }
                    ?: throw BackupError("shield-bad-app")
                apps += AppRestriction(id, pkg, now)
            }
        }
        val active = fs["activeProfileId"] as? String
        if (active != null && profiles.none { it.id == active }) throw BackupError("shield-bad-active-profile")
        val days = ((fs["retentionDays"] as? Long) ?: 30L).toInt()
        if (days !in 1..365) throw BackupError("shield-bad-retention")
        return ShieldPart(active, fs["logDomains"] as? Boolean ?: false, days, profiles, rules, apps)
    }

    /// Replaces the shield configuration with [p]. The shield is left
    /// DISABLED: the parent must set a new PIN and switch it on (the PIN is
    /// never part of a backup).
    fun applyShield(p: ShieldPart, repo: ShieldRepository, now: Long) {
        for (old in repo.profiles()) repo.deleteProfile(old.id)
        for (pr in p.profiles) repo.upsertProfile(pr)
        for (r in p.rules) repo.addRule(r)
        for (a in p.apps) repo.addAppRestriction(a)
        val c = repo.config()
        repo.saveConfig(
            c.copy(enabled = false, activeProfileId = p.activeProfileId, logDomains = p.logDomains,
                retentionDays = p.retentionDays, generation = c.generation + 1, updatedAt = now),
        )
        repo.appendHistory(ProfileChange(now, c.activeProfileId, p.activeProfileId, "import"))
    }
}
