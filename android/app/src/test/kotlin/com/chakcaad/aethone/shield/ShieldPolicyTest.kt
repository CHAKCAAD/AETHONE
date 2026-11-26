package com.chakcaad.aethone.shield

import com.chakcaad.aethone.shield.ShieldDecision.Decision
import com.chakcaad.aethone.shield.ShieldSnapshot.Level
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/// Family Shield — rule priority, categories, allow/block lists, unknown-domain
/// policy, app restrictions by uid (docs/family-shield-testing.md).
class ShieldPolicyTest {
    private val db = ShieldCompiler.CategoryDatabase(
        domains = mapOf(
            "adult.example" to ShieldCategory.ADULT.mask,
            "casino.example" to ShieldCategory.GAMBLING.mask,
            "malware.example" to ShieldCategory.MALWARE.mask,
            "phish.example" to ShieldCategory.PHISHING.mask,
            "social.example" to ShieldCategory.SOCIAL.mask,
            "kids.example" to ShieldCategory.KIDS_SAFE.mask,
            "game.example" to ShieldCategory.GAMES.mask,
        ),
        cidrs = mapOf(Cidr.parse("198.51.100.0/24")!! to ShieldCategory.BYPASS.mask),
        exactDomains = mapOf("only-exact.example" to ShieldCategory.ADULT.mask),
    )

    private fun profile(p: AgePreset, id: String = "p1") = AgePresets.build(id, p.key, p, 0L)

    private fun reader(p: AgeProfile, rules: List<ParentRule> = emptyList()) =
        ShieldSnapshot.Reader.parse(ShieldCompiler.compile(p, rules, db, 1).bytes)

    private fun rule(kind: RuleKind, v: String, a: RuleAction, profile: String = "p1") =
        ParentRule("r-$v-$a", profile, kind, v, a)

    @Test fun mandatorySecurityAlwaysBlocksEvenWithAllowlist() {
        val p = profile(AgePreset.OLDER_TEEN).copy(categories = emptySet())
        val r = reader(p, listOf(rule(RuleKind.ROOT, "malware.example", RuleAction.ALLOW), rule(RuleKind.ROOT, "phish.example", RuleAction.ALLOW)))
        val m = r.checkName("dl.malware.example")
        assertTrue(m.block)
        assertEquals(Level.MANDATORY, m.level)
        assertEquals(ShieldCategory.MALWARE, m.categoryOrNull)
        assertEquals(Level.MANDATORY, r.checkName("phish.example").level)
    }

    @Test fun parentBlocklistBeatsAllowlistAndCategoriesOff() {
        val p = profile(AgePreset.OLDER_TEEN)
        val r = reader(p, listOf(rule(RuleKind.ROOT, "news.example", RuleAction.BLOCK), rule(RuleKind.EXACT, "news.example", RuleAction.ALLOW)))
        assertEquals(Level.PARENT_BLOCK, r.checkName("news.example").level)
        assertEquals(Level.PARENT_BLOCK, r.checkName("www.news.example").level)
    }

    @Test fun allowlistOverridesCategoriesOnly() {
        val p = profile(AgePreset.CHILD)
        val r = reader(p, listOf(rule(RuleKind.ROOT, "social.example", RuleAction.ALLOW)))
        val v = r.checkName("m.social.example")
        assertFalse(v.block)
        assertEquals(Level.PARENT_ALLOW, v.level)
        // without the allow entry the category blocks
        assertEquals(Level.CATEGORY, reader(p).checkName("m.social.example").level)
    }

    @Test fun categoriesFollowTheProfile() {
        val child = reader(profile(AgePreset.CHILD))
        val older = reader(profile(AgePreset.OLDER_TEEN))
        assertTrue(child.checkName("social.example").block)
        assertFalse(older.checkName("social.example").block)
        assertTrue(older.checkName("casino.example").block)
        assertFalse(child.checkName("game.example").block)
        // exact (hosts-style) list entries block only the listed name
        assertTrue(child.checkName("only-exact.example").block)
        assertFalse(child.checkName("www.only-exact.example").block)
    }

    @Test fun unknownDomainPolicyPerProfile() {
        val toddler = reader(profile(AgePreset.TODDLER), listOf(rule(RuleKind.ROOT, "school.example", RuleAction.ALLOW)))
        val u = toddler.checkName("random.org")
        assertTrue(u.block)
        assertEquals(Level.UNKNOWN, u.level)
        assertFalse(toddler.checkName("www.school.example").block)
        // the kids-safe positive list counts as allowed in allowlist-only mode
        assertFalse(toddler.checkName("kids.example").block)
        // a categorized domain stays blocked even in a toddler profile
        assertEquals(Level.CATEGORY, toddler.checkName("adult.example").level)
        // other presets allow unknown domains
        assertFalse(reader(profile(AgePreset.TEEN)).checkName("random.org").block)
    }

    @Test fun labelBoundaryAndWildcard() {
        val r = reader(profile(AgePreset.TEEN), listOf(rule(RuleKind.WILDCARD, "wild.example", RuleAction.BLOCK)))
        assertFalse(r.checkName("notadult.example").block)
        assertTrue(r.checkName("adult.example").block)
        assertFalse(r.checkName("wild.example").block)
        assertTrue(r.checkName("a.wild.example").block)
    }

    @Test fun cidrRulesApplyToRealAddressesOnly() {
        val r = reader(profile(AgePreset.CHILD), listOf(rule(RuleKind.CIDR, "2001:db8::/32", RuleAction.BLOCK)))
        assertEquals(Level.CATEGORY, r.checkFlow(null, byteArrayOf(198.toByte(), 51, 100, 7), false, 6, 443).level)
        assertFalse(r.checkFlow(null, byteArrayOf(198.toByte(), 51, 100, 7), true, 6, 443).block)
        assertEquals(Level.PARENT_BLOCK, r.checkFlow(null, Cidr.parseV6("2001:db8::5")!!, false, 6, 443).level)
    }

    @Test fun conflictingRulesAreReportedAndBlockWins() {
        val p = profile(AgePreset.TEEN)
        val res = ShieldCompiler.compile(p, listOf(rule(RuleKind.ROOT, "x.example", RuleAction.ALLOW), rule(RuleKind.ROOT, "x.example", RuleAction.BLOCK)), db, 1)
        assertEquals(listOf("root:x.example"), res.conflicts)
        assertEquals(Level.PARENT_BLOCK, ShieldSnapshot.Reader.parse(res.bytes).checkName("x.example").level)
    }

    @Test fun otherProfilesRulesAreIgnored() {
        val p = profile(AgePreset.TEEN, "p1")
        val r = reader(p, listOf(rule(RuleKind.ROOT, "other.example", RuleAction.BLOCK, profile = "p2")))
        assertFalse(r.checkName("other.example").block)
    }

    // ---- app layer (level 3) and its place in the priority --------------

    private val appIds = setOf(10_123)
    private fun native(block: Boolean, level: Int, cat: Int = 0) = ShieldSnapshot.Verdict(true, block, level, cat)

    @Test fun appRestrictionMatchesUidByAppId() {
        val d = ShieldDecision.decide(native(false, Level.NONE), 10_123, appIds)
        assertEquals(Level.APP, (d as Decision.Block).level)
        // work profile copy of the same app (user 10)
        assertTrue(ShieldDecision.decide(native(false, Level.NONE), 1_010_123, appIds) is Decision.Block)
        assertTrue(ShieldDecision.decide(native(false, Level.NONE), 10_124, appIds) is Decision.Allow)
    }

    @Test fun invalidOrMissingUidFallsBackToDestinationVerdict() {
        assertTrue(ShieldDecision.decide(native(false, Level.NONE), ShieldDecision.INVALID_UID, appIds) is Decision.Allow)
        assertTrue(ShieldDecision.decide(native(false, Level.NONE), null, appIds) is Decision.Allow)
        val d = ShieldDecision.decide(native(true, Level.CATEGORY, 3), null, appIds)
        assertEquals(Level.CATEGORY, (d as Decision.Block).level)
        assertEquals(ShieldCategory.ADULT, d.category)
    }

    @Test fun priorityMandatoryAndBlocklistBeforeAppBeforeCategory() {
        assertEquals(Level.MANDATORY, (ShieldDecision.decide(native(true, Level.MANDATORY, 1), 10_123, appIds) as Decision.Block).level)
        assertEquals(Level.PARENT_BLOCK, (ShieldDecision.decide(native(true, Level.PARENT_BLOCK), 10_123, appIds) as Decision.Block).level)
        assertEquals(Level.APP, (ShieldDecision.decide(native(true, Level.CATEGORY, 3), 10_123, appIds) as Decision.Block).level)
        assertEquals(Level.APP, (ShieldDecision.decide(native(true, Level.UNKNOWN), 10_123, appIds) as Decision.Block).level)
        // the allowlist never opens a restricted app
        assertEquals(Level.APP, (ShieldDecision.decide(native(false, Level.PARENT_ALLOW), 10_123, appIds) as Decision.Block).level)
    }

    @Test fun inactiveNativeSnapshotFailsClosed() {
        val d = ShieldDecision.decide(ShieldSnapshot.Verdict.INACTIVE, 10_999, emptySet())
        assertEquals("no-snapshot", (d as Decision.Block).reason)
    }

    @Test fun routeGateRejectsBeforeHybridAndNeverMeters() {
        var hybridAsked = false
        val blocked = RouteGate.combine(Decision.Block(Level.CATEGORY, null, "category"), metering = true) { hybridAsked = true; 16 }
        assertEquals(RouteGate.ROUTE_REJECT, blocked.answer)
        assertFalse(blocked.observe)
        assertFalse(hybridAsked)
        val ok = RouteGate.combine(Decision.Allow(Level.NONE), metering = true) { 17 }
        assertEquals(17, ok.answer)
        assertTrue(ok.observe)
        // no shield: the hybrid answer is untouched (single-tunnel / hybrid regression)
        assertEquals(0, RouteGate.combine(null, metering = false) { 0 }.answer)
        assertFalse(RouteGate.combine(null, metering = true) { RouteGate.ROUTE_REJECT }.observe)
        assertTrue(RouteGate.needsUid(false, false, true))
        assertFalse(RouteGate.needsUid(false, false, false))
    }

    @Test fun verdictEncodingMatchesNative() {
        val v = ShieldSnapshot.Verdict(true, true, Level.CATEGORY, 3)
        assertEquals(0x80030401.toInt(), v.encode())
        assertEquals(v, ShieldSnapshot.Verdict.decode(v.encode()))
        assertFalse(ShieldSnapshot.Verdict.decode(0).active)
        assertNull(ShieldSnapshot.Verdict.decode(0x80000000.toInt()).categoryOrNull)
    }
}
