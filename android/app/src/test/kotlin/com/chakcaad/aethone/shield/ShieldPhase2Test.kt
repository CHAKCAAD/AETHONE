package com.chakcaad.aethone.shield

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/// Family Shield phase 2: admin API (channel), status rules, exclusion
/// audit, loopback gate decision, u32 counter wrap, settings export/import.
class ShieldPhase2Test {
    private var now = 5_000_000L
    private val repo = InMemoryShieldRepository()
    private val pin = ParentPin(repo, StaticPepper(ByteArray(32) { 3 }), { now }, iterations = 1000)
    private val admin = ShieldAdmin(repo, pin) { now }

    private fun session(): String {
        if (!pin.isSet) assertEquals(true, admin.handle("pinSetup", mapOf("pin" to "583920"))["ok"])
        return admin.handle("pinVerify", mapOf("pin" to "583920"))["token"] as String
    }

    @Suppress("UNCHECKED_CAST")
    private fun newProfile(t: String, name: String, preset: String = "custom"): String =
        ((admin.handle("createProfile", mapOf("token" to t, "name" to name, "preset" to preset))["profile"]) as Map<String, Any?>)["id"] as String

    // ------------------------------------------------------------ admin API

    @Test fun gatedOperationsNeedALiveSession() {
        for (m in ShieldAdmin.GATED) {
            val r = admin.handle(m, mapOf("token" to "forged"))
            assertEquals(m, "session-required", r["error"])
        }
        assertEquals("session-required", admin.handle("setEnabled", mapOf("enabled" to false))["error"])
        val t = session()
        now += ParentPin.SESSION_MS + 1
        assertEquals("session-required", admin.handle("setEnabled", mapOf("token" to t, "enabled" to false))["error"])
        // read-only views are open
        assertEquals(true, admin.handle("profiles", emptyMap())["ok"])
        assertEquals(true, admin.handle("pinState", emptyMap())["ok"])
    }

    @Test fun pinFlowThroughTheChannel() {
        assertEquals("pin-not-set", admin.handle("pinVerify", mapOf("pin" to "583920"))["error"])
        assertEquals("weak-pin:sequence", admin.handle("pinSetup", mapOf("pin" to "123456"))["error"])
        val setup = admin.handle("pinSetup", mapOf("pin" to "583920"))
        assertNotNull(setup["recoveryCode"])
        assertEquals("pin-already-set", admin.handle("pinSetup", mapOf("pin" to "583921"))["error"])
        val wrong = admin.handle("pinVerify", mapOf("pin" to "000001"))
        assertEquals("wrong-pin", wrong["error"])
        assertEquals(true, admin.handle("pinRecover", mapOf("code" to setup["recoveryCode"]))["ok"])
        // recovery code is one-time
        assertEquals("wrong-pin", admin.handle("pinRecover", mapOf("code" to setup["recoveryCode"]))["error"])
        assertEquals(true, admin.handle("endSession", emptyMap())["ok"])
    }

    @Test fun enableNeedsPinAndActiveProfile() {
        val t = session()
        assertEquals("no-active-profile", admin.handle("setEnabled", mapOf("token" to t, "enabled" to true))["error"])
        val id = newProfile(t, "kid", "child")
        assertEquals(true, admin.handle("switchProfile", mapOf("token" to t, "id" to id))["ok"])
        val r = admin.handle("setEnabled", mapOf("token" to t, "enabled" to true))
        assertEquals(true, r["ok"]); assertEquals(true, r["changed"])
        assertTrue(repo.config().enabled)
    }

    @Test fun rulesCategoriesAndAppsThroughTheChannel() {
        val t = session()
        val id = newProfile(t, "teen", "teen")
        val add = admin.handle("addRule", mapOf("token" to t, "profileId" to id, "kind" to "root", "value" to "Example.COM.", "action" to "block"))
        assertEquals(true, add["changed"])
        @Suppress("UNCHECKED_CAST")
        assertEquals("example.com", (add["rule"] as Map<String, Any?>)["value"])
        assertEquals("invalid-argument", admin.handle("addRule", mapOf("token" to t, "profileId" to id, "kind" to "cidr", "value" to "10.0.0.1/8", "action" to "block"))["error"])
        assertEquals("mandatory-category", admin.handle("setCategory", mapOf("token" to t, "profileId" to id, "category" to "malware", "on" to false))["error"])
        assertEquals(true, admin.handle("setCategory", mapOf("token" to t, "profileId" to id, "category" to "games", "on" to true))["ok"])
        assertEquals(true, admin.handle("restrictApp", mapOf("token" to t, "profileId" to id, "package" to "com.game", "on" to true))["ok"])
        assertEquals(listOf("com.game"), admin.handle("appRestrictions", mapOf("profileId" to id))["apps"])
        @Suppress("UNCHECKED_CAST")
        val rules = admin.handle("rules", mapOf("profileId" to id))["rules"] as List<Map<String, Any?>>
        assertEquals(1, rules.size)
        assertEquals(true, admin.handle("removeRule", mapOf("token" to t, "id" to rules[0]["id"]))["ok"])
        assertEquals("unknown-method", admin.handle("nope", emptyMap())["error"])
    }

    @Test fun profileSwitchingKeepsEachProfilesRules() {
        val t = session()
        val a = newProfile(t, "a"); val b = newProfile(t, "b")
        admin.handle("addRule", mapOf("token" to t, "profileId" to a, "kind" to "exact", "value" to "a.example", "action" to "block"))
        admin.handle("addRule", mapOf("token" to t, "profileId" to b, "kind" to "exact", "value" to "b.example", "action" to "block"))
        admin.handle("switchProfile", mapOf("token" to t, "id" to a))
        admin.handle("switchProfile", mapOf("token" to t, "id" to b))
        assertEquals(b, repo.config().activeProfileId)
        assertEquals(listOf("a.example"), repo.rules(a).map { it.value })
        assertEquals(listOf("b.example"), repo.rules(b).map { it.value })
        @Suppress("UNCHECKED_CAST")
        val h = admin.handle("history", mapOf("token" to t))["history"] as List<Map<String, Any?>>
        assertEquals(b, h[0]["to"])
    }

    @Test fun eventsAreAggregatedAndNeverCarryUrls() {
        val t = session()
        val ev = ShieldEvents { now }
        ev.record("dns_block", 2, ShieldCategory.ADULT, "com.a", "x.example")
        ev.record("dns_block", 2, ShieldCategory.ADULT, "com.a", "x.example")
        now += 120_000
        ev.record("dns_block", 2, ShieldCategory.ADULT, "com.a", "x.example")
        ev.flush { repo.addEvents(it) }
        now += 60_000
        @Suppress("UNCHECKED_CAST")
        val rows = admin.handle("events", mapOf("token" to t, "from" to 0L, "to" to now))["events"] as List<Map<String, Any?>>
        assertEquals(1, rows.size)
        assertEquals(3L, rows[0]["count"])
        assertNull(rows[0]["domain"]) // domain logging is opt-in (off)
        assertEquals("invalid-argument", admin.handle("events", mapOf("token" to t, "from" to now, "to" to 0L))["error"])
    }

    // ------------------------------------------------------------ status

    @Test fun statusIsNeverProtectedWithAHole() {
        fun st(i: ShieldStatus.Inputs) = ShieldStatus.compute(i)
        val base = ShieldStatus.Inputs(enabled = true, tunnelUp = true, snapshotLive = true, engineHookInstalled = true)
        assertEquals(ShieldStatus.State.PROTECTED, st(base).state)
        assertEquals(emptyList<String>(), st(base).reasons)
        assertEquals(ShieldStatus.State.VALIDATION_FAILED, st(base.copy(engineHookInstalled = false)).state)
        assertEquals(listOf("engine-hook-not-installed"), st(base.copy(engineHookInstalled = false)).reasons)
        assertEquals(listOf("snapshot-invalid", "engine-hook-not-installed"), st(base.copy(snapshotLive = false, engineHookInstalled = false)).reasons)
        assertEquals(ShieldStatus.State.DEGRADED, st(base.copy(ipv6Captured = false)).state)
        assertEquals(ShieldStatus.State.DEGRADED, st(base.copy(perAppExclusions = listOf("com.x"))).state)
        val exposed = base.copy(listeners = listOf(
            ShieldStatus.Listener(1819, true, false), ShieldStatus.Listener(1820, false, false),
            ShieldStatus.Listener(1821, true, true), ShieldStatus.Listener(1822, true, false)))
        assertEquals(listOf("local-socks-exposed:1819,1822"), st(exposed).reasons)
        // a listener that is up but guarded is not an exposure
        assertEquals(ShieldStatus.State.PROTECTED, st(base.copy(listeners = listOf(ShieldStatus.Listener(1819, true, true)))).state)
        assertEquals(ShieldStatus.State.INACTIVE, st(base.copy(enabled = false)).state)
        assertEquals(listOf("no-tunnel"), st(base.copy(tunnelUp = false)).reasons)
        assertEquals(listOf("reconnect-required"), st(base.copy(tunnelUp = false, unshieldedTunnel = true)).reasons)
        assertEquals(ShieldStatus.State.VALIDATION_FAILED, st(base.copy(error = "shield-snapshot-rejected:rc=-3")).state)
        assertEquals(listOf("app-blocking-unsupported"), st(base.copy(appBlockingSupported = false, hasAppRestrictions = true)).reasons)
        assertEquals(listOf("private-dns-strict"), st(base.copy(privateDnsStrict = true)).reasons)
    }

    @Test fun exclusionAuditReportsEveryAppPrecisely() {
        val installed = setOf("com.a", "com.b")
        val dis = ExclusionAudit.audit("disallow", listOf("com.a", "com.gone", "me"), "me") { it in installed }
        assertTrue(dis.degrading)
        assertEquals(
            listOf("me" to ExclusionAudit.AppState.SELF_EXCLUDED, "com.a" to ExclusionAudit.AppState.EXCLUDED_DISALLOWED,
                "com.gone" to ExclusionAudit.AppState.NOT_INSTALLED),
            dis.entries.map { it.packageName to it.state },
        )
        assertEquals(listOf("com.a"), dis.reasons())
        val allow = ExclusionAudit.audit("allow", listOf("com.b"), "me") { it in installed }
        assertTrue(allow.degrading && allow.othersExcluded)
        assertEquals(listOf("allow-mode:all-unlisted-apps"), allow.reasons())
        // allow list with nothing installed falls back to the whole device (as the Builder code)
        val degenerate = ExclusionAudit.audit("allow", listOf("com.gone"), "me") { it in installed }
        assertFalse(degenerate.degrading)
        assertEquals("all", degenerate.mode)
        assertFalse(ExclusionAudit.audit("all", emptyList(), "me") { true }.degrading)
        assertFalse(ExclusionAudit.audit("disallow", listOf("com.gone"), "me") { it in installed }.degrading)
    }

    // ------------------------------------------------------------ loopback gate

    @Test fun loopbackGateIsFailClosed() {
        fun d(own: Boolean?, c: Int?, s: Int?) = LoopbackGuard.decide(LoopbackGuard.Evidence(own, c, s, ownUid = 10123))
        assertTrue(d(true, -1, -1).allowed)
        assertTrue(d(true, null, null).allowed)
        assertEquals("foreign-uid:2000", d(false, 2000, -1).reason)
        assertEquals("foreign-uid:10200", d(null, -1, 10200).reason)
        assertFalse(d(false, -1, -1).allowed)          // INVALID_UID, not ours
        assertFalse(d(false, 10123, -1).allowed)       // our uid but another process: still refused
        assertFalse(d(null, null, null).allowed)       // nothing known
        assertFalse(d(false, null, null).allowed)
        assertTrue(d(false, 0, -1).reason.startsWith("foreign-uid:0"))
    }

    @Test fun loopbackAddressesCompareAcrossV4MappedForms() {
        val v4 = java.net.InetSocketAddress(java.net.InetAddress.getByAddress(byteArrayOf(127, 0, 0, 1)), 46464)
        val mappedBytes = ByteArray(16).also { it[10] = -1; it[11] = -1; it[12] = 127; it[15] = 1 }
        val mapped = java.net.InetSocketAddress(java.net.Inet6Address.getByAddress(null, mappedBytes, -1), 46464)
        assertTrue(LoopbackGuard.sameEndpoint(v4, mapped))
        assertFalse(LoopbackGuard.sameEndpoint(v4, java.net.InetSocketAddress(v4.address, 46465)))
        val other = java.net.InetSocketAddress(java.net.InetAddress.getByAddress(byteArrayOf(127, 0, 0, 2)), 46464)
        assertFalse(LoopbackGuard.sameEndpoint(v4, other))
    }

    // ------------------------------------------------------------ counters

    @Test fun u32CountersAreReadWrapSafe() {
        assertEquals(7L, ShieldCounters.delta(0xffff_fffdL, 4L))
        assertEquals(0L, ShieldCounters.delta(5L, 5L))
        val c = ShieldCounters()
        assertEquals(10L, c.observe(0, 10L))
        assertEquals(0xffff_ffffL, c.observe(0, 0xffff_ffffL))
        assertEquals(0xffff_ffffL + 3, c.observe(0, 2L))          // wrapped
        assertEquals(0xffff_ffffL + 3, c.observe(0, -1L))         // engine gone: kept
        assertEquals(0xffff_ffffL + 8, c.observe(0, 5L))          // new engine starts at 0
        assertEquals(-1L, c.observe(99, 1L))
    }

    // ------------------------------------------------------------ export / import

    private fun prefs() = listOf(
        SettingsBackup.Pref("aethone.settings.protocol", "s", "masque"),
        SettingsBackup.Pref("aethone.settings.killSwitch", "b", true),
        SettingsBackup.Pref("aethone.settings.hybridRules.v110", "s", "{\"rules\":[\"a\\\"b\"]}"),
        SettingsBackup.Pref("aethone.settings.count", "l", 42L),
        SettingsBackup.Pref("other.key", "s", "dropped"),
    )

    @Test fun exportImportRoundTripWithoutPinMaterial() {
        val t = session()
        val id = newProfile(t, "kid", "child")
        admin.handle("addRule", mapOf("token" to t, "profileId" to id, "kind" to "root", "value" to "bad.example", "action" to "block"))
        admin.handle("addRule", mapOf("token" to t, "profileId" to id, "kind" to "cidr", "value" to "10.1.0.0/16", "action" to "block"))
        admin.handle("restrictApp", mapOf("token" to t, "profileId" to id, "package" to "com.game", "on" to true))
        admin.handle("switchProfile", mapOf("token" to t, "id" to id))
        admin.handle("setEnabled", mapOf("token" to t, "enabled" to true))
        val text = SettingsBackup.export(prefs(), repo, now, "1.0.2")
        assertFalse(text.contains("583920"))
        val ps = repo.pinState()!!
        assertFalse(text.contains(ps.hash.joinToString("") { "%02x".format(it) }))
        assertFalse(text.contains("\"pin"))
        assertFalse(text.contains("other.key"))

        val parsed = SettingsBackup.parse(text)
        assertEquals(4, parsed.prefs.size)
        assertEquals("{\"rules\":[\"a\\\"b\"]}", parsed.prefs.first { it.key.endsWith("v110") }.value)
        val fresh = InMemoryShieldRepository()
        SettingsBackup.applyShield(parsed.shield!!, fresh, now)
        assertFalse("imported shield must stay off until a new PIN is set", fresh.config().enabled)
        assertNull(fresh.pinState())
        assertEquals(id, fresh.config().activeProfileId)
        assertEquals(setOf("bad.example", "10.1.0.0/16"), fresh.rules(id).map { it.value }.toSet())
        assertEquals(listOf("com.game"), fresh.appRestrictions(id).map { it.packageName })
        assertEquals(repo.profile(id)!!.categories, fresh.profile(id)!!.categories)
        // the imported configuration still compiles to a valid snapshot
        val snap = ShieldCompiler.compile(fresh.profile(id)!!, fresh.rules(id), ShieldCompiler.CategoryDatabase(), 1)
        assertTrue(snap.domains >= 1)
    }

    @Test fun importRejectsInvalidFiles() {
        fun bad(text: String, code: String) {
            try {
                SettingsBackup.parse(text); fail("accepted: $text")
            } catch (e: SettingsBackup.BackupError) {
                assertTrue("${e.code} vs $code", e.code.startsWith(code))
            }
        }
        bad("not json", "not-json")
        bad("[]", "not-an-object")
        bad("{\"format\":\"x\",\"version\":1}", "wrong-format")
        bad("{\"format\":\"aethone-settings\",\"version\":2,\"app\":{\"prefs\":[]}}", "newer-version")
        bad("{\"format\":\"aethone-settings\",\"version\":1}", "no-app-section")
        bad("{\"format\":\"aethone-settings\",\"version\":1,\"app\":{\"prefs\":[{\"key\":\"evil\",\"type\":\"s\",\"value\":\"x\"}]}}", "bad-pref-key")
        bad("{\"format\":\"aethone-settings\",\"version\":1,\"app\":{\"prefs\":[{\"key\":\"aethone.settings.a\",\"type\":\"b\",\"value\":\"x\"}]}}", "bad-pref-value")
        val prof = "{\"id\":\"p1\",\"preset\":\"child\",\"unknownPolicy\":\"allow\",\"categories\":[\"malware\"]}"
        bad("{\"format\":\"aethone-settings\",\"version\":1,\"app\":{\"prefs\":[]},\"familyShield\":{\"profiles\":[$prof]}}", "shield-mandatory-category")
        val rule = "{\"id\":\"p1\",\"preset\":\"child\",\"unknownPolicy\":\"allow\",\"rules\":[{\"kind\":\"cidr\",\"value\":\"10.0.0.1/8\",\"action\":\"block\"}]}"
        bad("{\"format\":\"aethone-settings\",\"version\":1,\"app\":{\"prefs\":[]},\"familyShield\":{\"profiles\":[$rule]}}", "shield-bad-rule-value")
        val ok = "{\"id\":\"p1\",\"preset\":\"child\",\"unknownPolicy\":\"allow\"}"
        bad("{\"format\":\"aethone-settings\",\"version\":1,\"app\":{\"prefs\":[]},\"familyShield\":{\"activeProfileId\":\"zz\",\"profiles\":[$ok]}}", "shield-bad-active-profile")
        bad("{\"format\":\"aethone-settings\",\"version\":1,\"version\":1}", "not-json") // duplicate key
        bad("x".repeat(SettingsBackup.MAX_BYTES + 1), "too-large")
    }

    @Test fun miniJsonRoundTrip() {
        val v = mapOf("a" to listOf(1L, 2.5, true, null, "q\"\\\n\u0001ü"), "b" to emptyMap<String, Any?>())
        assertEquals(v, MiniJson.parse(MiniJson.write(v)))
        try { MiniJson.parse("{\"a\":1,}"); fail() } catch (_: MiniJson.ParseError) {}
        try { MiniJson.parse("[1] x"); fail() } catch (_: MiniJson.ParseError) {}
        try { MiniJson.parse("[".repeat(100) + "]".repeat(100)); fail() } catch (_: MiniJson.ParseError) {}
    }
}
