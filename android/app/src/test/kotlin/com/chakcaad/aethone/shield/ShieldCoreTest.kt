package com.chakcaad.aethone.shield

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/// Family Shield — age profiles, profile switching, names/CIDR, content
/// sources, events, SOCKS auth plan, status.
class ShieldCoreTest {
    @Test fun agePresets() {
        assertEquals(UnknownPolicy.BLOCK, AgePresets.unknownPolicy(AgePreset.TODDLER))
        for (p in listOf(AgePreset.CHILD, AgePreset.TEEN, AgePreset.OLDER_TEEN, AgePreset.CUSTOM)) {
            assertEquals(UnknownPolicy.ALLOW, AgePresets.unknownPolicy(p))
        }
        // stricter for younger ages; mandatory categories are never part of a preset
        assertTrue(AgePresets.categories(AgePreset.CHILD).containsAll(AgePresets.categories(AgePreset.TEEN)))
        assertTrue(AgePresets.categories(AgePreset.TEEN).containsAll(AgePresets.categories(AgePreset.OLDER_TEEN)))
        for (p in AgePreset.entries) assertTrue(AgePresets.categories(p).none { it.mandatory })
        assertEquals(3, AgePreset.TODDLER.minAge)
        assertEquals(17, AgePreset.OLDER_TEEN.maxAge)
        // every category is visible: each has a stable key and bit
        assertEquals(ShieldCategory.entries.size, ShieldCategory.entries.map { it.key }.toSet().size)
        assertEquals(ShieldCategory.MALWARE.mask or ShieldCategory.PHISHING.mask, ShieldCategory.mandatoryMask)
    }

    @Test fun profileSwitchingKeepsEveryProfilesData() {
        var now = 1000L
        val repo = InMemoryShieldRepository()
        val pm = ProfileManager(repo) { now++ }
        val a = pm.create("Sara", AgePreset.CHILD)
        val b = pm.create("Ali", AgePreset.TEEN)
        pm.addRule(a.id, RuleKind.ROOT, "Example.COM.", RuleAction.BLOCK)
        pm.restrictApp(a.id, "com.game.x", true)
        pm.addRule(b.id, RuleKind.WILDCARD, "*.school.example", RuleAction.ALLOW)
        pm.switchTo(a.id)
        pm.switchTo(b.id)
        pm.setCategory(b.id, ShieldCategory.SOCIAL, true)
        assertEquals(b.id, pm.active()!!.id)
        // a's data untouched by the switch and by b's edits
        assertEquals(listOf("example.com"), repo.rules(a.id).map { it.value })
        assertEquals(listOf("com.game.x"), repo.appRestrictions(a.id).map { it.packageName })
        assertFalse(repo.profile(a.id)!!.categories.isEmpty())
        assertEquals("school.example", repo.rules(b.id).single().value)
        assertTrue(ShieldCategory.SOCIAL in repo.profile(b.id)!!.categories)
        // history: newest first, with from/to
        val h = repo.history(10)
        assertEquals(2, h.size)
        assertEquals(a.id, h[0].fromProfileId)
        assertEquals(b.id, h[0].toProfileId)
        assertNull(h[1].fromProfileId)
        // generation moves on every change (drives snapshot rebuilds)
        val g = repo.config().generation
        pm.setUnknownPolicy(b.id, UnknownPolicy.BLOCK)
        assertNotEquals(g, repo.config().generation)
        // mandatory categories can not be switched off
        try { pm.setCategory(b.id, ShieldCategory.MALWARE, false); throw AssertionError() } catch (_: IllegalArgumentException) {}
        // the active profile can not be deleted
        try { pm.delete(b.id); throw AssertionError() } catch (_: IllegalArgumentException) {}
        pm.delete(a.id)
        assertTrue(repo.rules(a.id).isEmpty())
    }

    @Test fun ruleValidation() {
        val pm = ProfileManager(InMemoryShieldRepository())
        val p = pm.create("x", AgePreset.CUSTOM)
        assertEquals("xn--mnchen-3ya.de", pm.addRule(p.id, RuleKind.ROOT, "München.de", RuleAction.BLOCK).value)
        assertEquals("10.0.0.0/8", pm.addRule(p.id, RuleKind.CIDR, "10.0.0.0/8", RuleAction.BLOCK).value)
        for (bad in listOf("", "a..b", "exa mple.com", "1.2.3.4", "http://x.com")) {
            try { pm.addRule(p.id, RuleKind.ROOT, bad, RuleAction.BLOCK); throw AssertionError(bad) } catch (_: IllegalArgumentException) {}
        }
        try { pm.addRule(p.id, RuleKind.CIDR, "10.0.0.1/8", RuleAction.BLOCK); throw AssertionError() } catch (_: IllegalArgumentException) {}
    }

    @Test fun namesAndCidrs() {
        assertEquals("www.xn--bcher-kva.example", DomainNames.normalize("WWW.Bücher.example."))
        assertNull(DomainNames.normalize("bad_label..x"))
        assertEquals(listOf("a.b.example.com", "b.example.com", "example.com", "com"), DomainNames.suffixes("a.b.example.com"))
        assertFalse(DomainNames.suffixes("notexample.com").contains("example.com"))
        val c = Cidr.parse("2001:db8::/32")!!
        assertTrue(c.contains(Cidr.parseV6("2001:db8:1::1")!!))
        assertFalse(c.contains(Cidr.parseV6("2001:db9::1")!!))
        assertEquals("2001:db8:0:0:0:0:0:0/32", c.toString())
        assertNull(Cidr.parse("256.0.0.1"))
        assertNull(Cidr.parse("10.0.0.0/33"))
        assertNull(Cidr.parse("example.com"))
    }

    @Test fun contentSourcesParseDedupeValidateVersion() {
        val hosts = "# c\n0.0.0.0 ads.example\n127.0.0.1 localhost\n0.0.0.0 Bad..x\n0.0.0.0 www.root.example\n"
        val p = ContentSources.parse(ContentSources.Format.HOSTS_EXACT, hosts)
        assertEquals(setOf("ads.example", "www.root.example"), p.names)
        assertEquals(1, p.skipped)
        assertEquals(setOf("a.example"), ContentSources.parse(ContentSources.Format.ADBLOCK_ROOT, "! x\n||a.example^\n").names)
        val src = ContentSources.all.first { it.id == "hagezi-gambling" }.copy(minEntries = 2)
        val sb = ContentSources.all.first { it.id == "stevenblack-gambling" }.copy(minEntries = 1)
        val build = ContentSources.buildDatabase(
            listOf(
                ContentSources.SourceResult(src, "root.example\ncasino.example\n", 1),
                // exact entry already covered by the root list of the same category → deduped
                ContentSources.SourceResult(sb, "0.0.0.0 www.root.example\n0.0.0.0 other.example\n", 1),
            ),
        )
        assertEquals(setOf("root.example", "casino.example"), build.db.domains.keys)
        assertEquals(setOf("other.example"), build.db.exactDomains.keys)
        assertEquals(16, build.version.length)
        // truncated download: refused, previous version kept
        val small = ContentSources.buildDatabase(listOf(ContentSources.SourceResult(src, "one.example\n", 1)))
        assertEquals("too-few-entries:1<2", small.rejected.single().second)
        val shrunk = ContentSources.buildDatabase(listOf(ContentSources.SourceResult(src, "a.example\nb.example\n", 1)), mapOf(src.id to 100))
        assertTrue(shrunk.rejected.single().second.startsWith("shrunk"))
        // licences recorded; UT1 never bundled; URLhaus absent
        assertTrue(ContentSources.all.filter { it.id.startsWith("ut1") }.all { !it.bundleAllowed && it.licence == "CC BY-SA 4.0" })
        assertTrue(ContentSources.all.none { it.url.contains("urlhaus") || it.url.contains("abuse.ch") })
        assertTrue(ContentSources.all.all { it.attribution.isNotBlank() && it.licenceUrl.startsWith("https://") })
        val v = ContentSources.Versions()
        v.promote("a"); v.promote("b")
        assertTrue(v.rollback())
        assertEquals("a", v.active)
        assertFalse(v.rollback())
    }

    @Test fun eventsAggregateAndHideDomainsUnlessOptedIn() {
        val ev = ShieldEvents { 125_000L }
        ev.record("flow_block", 4, ShieldCategory.ADULT, "com.x", "secret.example")
        ev.record("flow_block", 4, ShieldCategory.ADULT, "com.x", "other.example")
        val rows = ArrayList<EventBucket>()
        ev.flush { rows += it }
        assertEquals(1, rows.size)
        assertEquals(2L, rows[0].count)
        assertNull(rows[0].domain)
        assertEquals(120_000L, rows[0].minute)
        ev.logDomains = true
        ev.record("dns_block", 4, null, null, "Secret.Example.")
        ev.flush { rows += it }
        assertEquals("secret.example", rows.last().domain)
        // a failing sink keeps the batch
        ev.record("flow_block")
        try { ev.flush { throw IllegalStateException("db") } } catch (_: IllegalStateException) {}
        assertEquals(1, ev.pendingCount())
        val repo = InMemoryShieldRepository()
        ev.flush { repo.addEvents(it) }
        assertEquals(1, repo.events(0, Long.MAX_VALUE).size)
    }

    @Test fun socksAuthPlanAndStatus() {
        // no pinned core can enforce SOCKS auth today: nothing is claimed protected
        assertEquals(listOf(1819, 1820, 1821, 1822), SocksAuth.unprotected(listOf(1822, 1819, 1820, 1821, 1819)))
        val c = SocksAuth.newCredentials()
        assertTrue(c.username.length >= 8 && c.password.length >= 32)
        assertNotEquals(c, SocksAuth.newCredentials())
        assertTrue(SocksAuth.tomlLines(c).contains("username = \"${c.username}\""))
        assertEquals("", SocksAuth.tomlLines(null))

        val ok = ShieldStatus.compute(ShieldStatus.Inputs(enabled = true, tunnelUp = true, snapshotLive = true))
        assertEquals(ShieldStatus.State.PROTECTED, ok.state)
        val deg = ShieldStatus.compute(
            ShieldStatus.Inputs(true, true, true, ipv6Captured = false, perAppExclusions = listOf("com.x"),
                listeners = listOf(ShieldStatus.Listener(1819, listening = true, guarded = false))),
        )
        assertEquals(ShieldStatus.State.DEGRADED, deg.state)
        assertEquals(listOf("ipv6-not-captured", "per-app-exclusions:1", "local-socks-exposed:1819"), deg.reasons)
        assertEquals(ShieldStatus.State.INACTIVE, ShieldStatus.compute(ShieldStatus.Inputs(false, true, true)).state)
        assertEquals(ShieldStatus.State.VALIDATION_FAILED, ShieldStatus.compute(ShieldStatus.Inputs(true, false, false, error = "shield-x")).state)
    }
}
