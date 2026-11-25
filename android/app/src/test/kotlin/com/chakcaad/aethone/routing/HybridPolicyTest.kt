package com.chakcaad.aethone.routing

import com.chakcaad.aethone.routing.HybridPolicy.Decision
import com.chakcaad.aethone.routing.HybridPolicy.Kind
import com.chakcaad.aethone.routing.HybridPolicy.Rule
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/// Hybrid per-tunnel routing — policy engine unit tests (docs/hybrid-routing.md §5).
/// Profile under test: AETHER → PSIPHON — tunnels [psiphon (default, WARP→Psiphon), warp].
class HybridPolicyTest {
    private val tunnels = listOf("psiphon", "warp")
    private fun policy(vararg rules: Rule) = HybridPolicy.build("psiphonChain", tunnels, rules.toList())
    private fun ip(vararg b: Int) = b.map { it.toByte() }.toByteArray()
    private fun v6(text: String) = HybridPolicy.parseAddress(text)!!
    private fun route(d: Decision) = (d as Decision.Route).tunnel

    @Test fun packageIdMatches() {
        val p = policy(Rule("1", Kind.APP, "org.telegram.messenger", "warp"))
        assertEquals(1, route(p.decide(listOf("org.telegram.messenger"), null, ip(1, 1, 1, 1))))
        assertEquals(0, route(p.decide(listOf("com.instagram.android"), null, ip(1, 1, 1, 1))))
        // a shared uid: any of its packages with a rule matches
        assertEquals(1, route(p.decide(listOf("x.y", "org.telegram.messenger"), null, null)))
    }

    @Test fun exactDomainRespectsBoundaries() {
        val p = policy(Rule("1", Kind.DOMAIN, "example.com", "warp"))
        assertEquals(1, route(p.decide(emptyList(), "example.com", null)))
        assertEquals(1, route(p.decide(emptyList(), "EXAMPLE.com.", null)))
        assertEquals(0, route(p.decide(emptyList(), "notexample.com", null)))
        assertEquals(0, route(p.decide(emptyList(), "www.example.com", null)))
    }

    @Test fun wildcardMatchesSubdomainsOnly() {
        val p = policy(Rule("1", Kind.WILDCARD, "*.example.com", "warp"))
        assertEquals(1, route(p.decide(emptyList(), "www.example.com", null)))
        assertEquals(1, route(p.decide(emptyList(), "a.b.example.com", null)))
        assertEquals(0, route(p.decide(emptyList(), "example.com", null)))
        assertEquals(0, route(p.decide(emptyList(), "badexample.com", null)))
    }

    @Test fun mostSpecificWildcardWins() {
        val p = policy(
            Rule("1", Kind.WILDCARD, "*.google.com", "warp"),
            Rule("2", Kind.WILDCARD, "*.mail.google.com", "psiphon"),
        )
        assertEquals(0, route(p.decide(emptyList(), "x.mail.google.com", null)))
        assertEquals(1, route(p.decide(emptyList(), "drive.google.com", null)))
    }

    @Test fun idnIsNormalised() {
        assertEquals("xn--mgba3a4f16a.ir", HybridPolicy.normalizeName("ایران.ir"))
        val p = policy(Rule("1", Kind.DOMAIN, "ایران.ir", "warp"))
        assertEquals(1, route(p.decide(emptyList(), "xn--mgba3a4f16a.ir", null)))
    }

    @Test fun ipv4SingleAndCidr() {
        val p = policy(
            Rule("1", Kind.CIDR, "1.1.1.1", "warp"),
            Rule("2", Kind.CIDR, "192.168.1.0/24", "psiphon"),
        )
        assertEquals(1, route(p.decide(emptyList(), null, ip(1, 1, 1, 1))))
        assertEquals(0, route(p.decide(emptyList(), null, ip(1, 1, 1, 2))))
        val d = p.decide(emptyList(), null, ip(192, 168, 1, 77)) as Decision.Route
        assertEquals("2", d.ruleId)
    }

    @Test fun ipv6AndCidr6() {
        val p = policy(
            Rule("1", Kind.CIDR, "2606:4700:4700::1111", "warp"),
            Rule("2", Kind.CIDR, "2001:db8::/32", "warp"),
        )
        assertEquals(1, route(p.decide(emptyList(), null, v6("2606:4700:4700::1111"))))
        assertEquals(1, route(p.decide(emptyList(), null, v6("2001:db8:1::5"))))
        assertEquals(0, route(p.decide(emptyList(), null, v6("2001:db9::1"))))
        // an IPv4 rule never matches an IPv6 destination
        assertEquals(0, route(policy(Rule("3", Kind.CIDR, "0.0.0.0/0", "warp")).decide(emptyList(), null, v6("::1"))))
    }

    @Test fun longestPrefixWinsThenEarlierRule() {
        val p = policy(
            Rule("wide", Kind.CIDR, "10.0.0.0/8", "warp"),
            Rule("narrow", Kind.CIDR, "10.1.0.0/16", "psiphon"),
        )
        assertEquals("narrow", (p.decide(emptyList(), null, ip(10, 1, 2, 3)) as Decision.Route).ruleId)
        assertEquals("wide", (p.decide(emptyList(), null, ip(10, 2, 2, 3)) as Decision.Route).ruleId)
    }

    @Test fun priorityAppThenExactThenWildcardThenIp() {
        val p = policy(
            Rule("app", Kind.APP, "org.telegram.messenger", "warp"),
            Rule("exact", Kind.DOMAIN, "instagram.com", "psiphon"),
            Rule("wild", Kind.WILDCARD, "*.instagram.com", "warp"),
            Rule("ip", Kind.CIDR, "157.240.0.0/16", "warp"),
        )
        // app beats a domain rule naming the other tunnel
        assertEquals("app", (p.decide(listOf("org.telegram.messenger"), "instagram.com", null) as Decision.Route).ruleId)
        assertEquals("exact", (p.decide(emptyList(), "instagram.com", null) as Decision.Route).ruleId)
        assertEquals("wild", (p.decide(emptyList(), "www.instagram.com", null) as Decision.Route).ruleId)
        assertEquals("ip", (p.decide(emptyList(), null, ip(157, 240, 1, 1)) as Decision.Route).ruleId)
        // a fake-IP (domain-known) flow never consults IP rules
        assertNull((p.decide(emptyList(), "other.org", null) as Decision.Route).ruleId)
    }

    @Test fun conflictsAreDeterministic() {
        val p = policy(
            Rule("first", Kind.DOMAIN, "example.com", "warp"),
            Rule("second", Kind.DOMAIN, "Example.com", "psiphon"),
        )
        assertEquals("first", (p.decide(emptyList(), "example.com", null) as Decision.Route).ruleId)
        assertTrue(p.rejected.any { it.first.id == "second" && it.second == "duplicate" })
    }

    @Test fun defaultRouteWithoutRules() {
        val p = policy()
        assertEquals(Decision.Route(0, null), p.decide(listOf("any.app"), "example.com", ip(8, 8, 8, 8)))
    }

    @Test fun disabledRulesAreIgnored() {
        val p = policy(Rule("1", Kind.DOMAIN, "example.com", "warp", enabled = false))
        assertEquals(0, route(p.decide(emptyList(), "example.com", null)))
    }

    @Test fun unavailableTunnelFailsClosed() {
        val p = policy(Rule("1", Kind.APP, "org.telegram.messenger", "tor"))
        assertEquals(Decision.Refuse("1"), p.decide(listOf("org.telegram.messenger"), null, null))
        assertTrue(p.rejected.any { it.second == "tunnel-unavailable" })
    }

    @Test fun invalidValuesAreRejected() {
        for (bad in listOf("1.1.1", "300.1.1.1", "10.0.0.1/24", "1.1.1.1/33", "::g", "example.com")) {
            assertNull(bad, HybridPolicy.canonical(Kind.CIDR, bad))
        }
        for (bad in listOf("", "com", "-a.com", "a..com", "*.com.", "exa mple.com")) {
            assertNull(bad, HybridPolicy.canonical(Kind.DOMAIN, bad))
        }
        assertNull(HybridPolicy.canonical(Kind.WILDCARD, "example.com"))
        assertNull(HybridPolicy.canonical(Kind.APP, "telegram"))
        assertEquals("192.168.1.0/24", HybridPolicy.canonical(Kind.CIDR, " 192.168.1.0/24 "))
        assertEquals("*.example.com", HybridPolicy.canonical(Kind.WILDCARD, "*.Example.COM"))
    }
}
