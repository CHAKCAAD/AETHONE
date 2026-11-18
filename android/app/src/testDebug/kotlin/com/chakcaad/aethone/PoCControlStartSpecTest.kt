package com.chakcaad.aethone

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/// Stage 2 per-app routing (PoC, round 4) — automated tests for the
/// route-start documents the debug-only PoCControlActivity accepts/rejects.
///
/// Runs on the JVM (`:app:testDebugUnitTest` — the DEBUG-only test source
/// set: the spec class itself lives in src/debug/kotlin, so a release unit
/// test compile never sees either): the spec and PoCRoutes are pure Kotlin
/// + org.json, so valid/malformed documents are exercised exactly as the
/// device entry point will see them — the same [PoCRoutes.parse] authority
/// the service start path and the live-update broadcast use. The
/// extras-key contract with AethoneVpnService is pinned so a rename on
/// either side fails HERE instead of on the owner's device.
class PoCControlStartSpecTest {

    // ------------------------------------------------------------------
    // The canonical valid route-start document (the device procedure's own
    // example): an engine socks5 route + a direct route, Firefox assigned
    // to direct, everything else defaulting to the engine.
    // ------------------------------------------------------------------
    private val canonicalDoc =
        """{"routes":[""" +
            """{"id":"engine","kind":"socks5","server":"127.0.0.1:1819"},""" +
            """{"id":"direct","kind":"direct"}],""" +
            """"assignments":{"org.mozilla.firefox":"direct"}}"""

    // ================= valid documents =================

    @Test
    fun `canonical document validates with defaults`() {
        val spec = PoCControlStartSpec.validate(
            rawPort = null,
            rawPocRoutes = canonicalDoc,
            rawTcpOnly = null,
            rawSocksStrict = null,
        )
        assertTrue(spec is PoCControlStartSpec.Spec.Valid)
        spec as PoCControlStartSpec.Spec.Valid
        assertEquals(1819, spec.port) // absent -> the service's default
        assertEquals(2, spec.routeCount)
        assertEquals(1, spec.assignmentCount)
        assertFalse(spec.tcpOnly)
        assertFalse(spec.socksStrict)
        assertEquals(canonicalDoc, spec.pocRoutesJson) // forwarded verbatim
    }

    @Test
    fun `explicit port and flags validate`() {
        val spec = PoCControlStartSpec.validate(
            rawPort = 1821,
            rawPocRoutes = canonicalDoc,
            rawTcpOnly = true,
            rawSocksStrict = true,
        )
        assertTrue(spec is PoCControlStartSpec.Spec.Valid)
        spec as PoCControlStartSpec.Spec.Valid
        assertEquals(1821, spec.port)
        assertTrue(spec.tcpOnly)
        assertTrue(spec.socksStrict)
    }

    @Test
    fun `port boundaries 1 and 65535 are valid`() {
        for (p in intArrayOf(1, 65535)) {
            val spec = PoCControlStartSpec.validate(p, canonicalDoc, null, null)
            assertTrue("port $p should be valid", spec is PoCControlStartSpec.Spec.Valid)
            assertEquals(p, (spec as PoCControlStartSpec.Spec.Valid).port)
        }
    }

    @Test
    fun `empty routes list with no assignments is a valid minimal document`() {
        // Parse-level valid (the service installs the flow callback and
        // every flow takes the default route — a legitimate test start for
        // observing route_asked/route_fallback counters).
        val spec = PoCControlStartSpec.validate(
            null, """{"routes":[]}""", null, null,
        )
        assertTrue(spec is PoCControlStartSpec.Spec.Valid)
        spec as PoCControlStartSpec.Spec.Valid
        assertEquals(0, spec.routeCount)
        assertEquals(0, spec.assignmentCount)
    }

    @Test
    fun `strict flag inside a socks5 route entry survives to the service doc`() {
        val doc =
            """{"routes":[{"id":"psiphon","kind":"socks5",""" +
                """"server":"127.0.0.1:1821","strict":true}],""" +
                """"assignments":{"com.example.app":"psiphon"}}"""
        val spec = PoCControlStartSpec.validate(null, doc, null, null)
        assertTrue(spec is PoCControlStartSpec.Spec.Valid)
        assertEquals(1, (spec as PoCControlStartSpec.Spec.Valid).routeCount)
        // PoCRoutes must have accepted the strict flag (it feeds
        // pocRoutesToml's strict list).
        val parsed = PoCRoutes.parse(doc)
        assertTrue(parsed.routes.first().strict)
    }

    // ================= spec-level rejections =================

    @Test
    fun `absent poc_routes is rejected`() {
        val spec = PoCControlStartSpec.validate(null, null, null, null)
        assertTrue(spec is PoCControlStartSpec.Spec.Invalid)
        assertTrue(
            (spec as PoCControlStartSpec.Spec.Invalid).reason.contains("poc_routes extra is required"),
        )
    }

    @Test
    fun `blank poc_routes is rejected`() {
        val spec = PoCControlStartSpec.validate(null, "   ", null, null)
        assertTrue(spec is PoCControlStartSpec.Spec.Invalid)
    }

    @Test
    fun `port 0 is rejected`() {
        val spec = PoCControlStartSpec.validate(0, canonicalDoc, null, null)
        assertTrue(spec is PoCControlStartSpec.Spec.Invalid)
        assertTrue((spec as PoCControlStartSpec.Spec.Invalid).reason.contains("port"))
    }

    @Test
    fun `port above 65535 is rejected`() {
        val spec = PoCControlStartSpec.validate(65536, canonicalDoc, null, null)
        assertTrue(spec is PoCControlStartSpec.Spec.Invalid)
    }

    @Test
    fun `wrong-typed port extra surfaces as the sentry and is rejected`() {
        // PoCControlActivity maps a present-but-wrong-typed extra to -1
        // (intExtraOrAbsent); the spec must reject it, not default it.
        val spec = PoCControlStartSpec.validate(-1, canonicalDoc, null, null)
        assertTrue(spec is PoCControlStartSpec.Spec.Invalid)
        assertTrue((spec as PoCControlStartSpec.Spec.Invalid).reason.contains("port must be 1..65535"))
    }

    // ================= malformed route-start documents =================

    private fun rejectedBy(doc: String): String {
        val spec = PoCControlStartSpec.validate(null, doc, null, null)
        assertTrue("expected Invalid for: $doc", spec is PoCControlStartSpec.Spec.Invalid)
        return (spec as PoCControlStartSpec.Spec.Invalid).reason
    }

    @Test
    fun `empty object without routes key parses as the empty table`() {
        // optJSONArray("routes") ?: JSONArray() — {} is the empty table,
        // a parse-level valid minimal document (boundary clarification).
        val spec = PoCControlStartSpec.validate(null, "{}", null, null)
        assertTrue(spec is PoCControlStartSpec.Spec.Valid)
        assertEquals(0, (spec as PoCControlStartSpec.Spec.Valid).routeCount)
    }

    @Test
    fun `not-json-at-all is rejected`() {
        assertTrue(rejectedBy("not json at all").contains("rejected"))
    }

    @Test
    fun `unknown route kind is rejected`() {
        val reason = rejectedBy(
            """{"routes":[{"id":"r","kind":"wireguard"}]}""",
        )
        assertTrue(reason.contains("kind"))
    }

    @Test
    fun `socks5 without server is rejected`() {
        assertTrue(
            rejectedBy("""{"routes":[{"id":"r","kind":"socks5"}]}""").contains("server"),
        )
    }

    @Test
    fun `socks5 server without port is rejected`() {
        assertTrue(
            rejectedBy(
                """{"routes":[{"id":"r","kind":"socks5","server":"127.0.0.1"}]}""",
            ).contains("host:port"),
        )
    }

    @Test
    fun `socks5 server with non-numeric port is rejected`() {
        assertTrue(
            rejectedBy(
                """{"routes":[{"id":"r","kind":"socks5","server":"127.0.0.1:http"}]}""",
            ).contains("invalid port"),
        )
    }

    @Test
    fun `direct route carrying a server is rejected`() {
        assertTrue(
            rejectedBy(
                """{"routes":[{"id":"d","kind":"direct","server":"1.2.3.4:9"}]}""",
            ).contains("must not carry a server"),
        )
    }

    @Test
    fun `duplicate route ids are rejected`() {
        assertTrue(
            rejectedBy(
                """{"routes":[{"id":"r","kind":"direct"},{"id":"r","kind":"direct"}]}""",
            ).contains("duplicate"),
        )
    }

    @Test
    fun `empty or whitespace route id is rejected`() {
        assertTrue(
            rejectedBy("""{"routes":[{"id":" ","kind":"direct"}]}""").contains("route id invalid"),
        )
        assertTrue(
            rejectedBy("""{"routes":[{"id":"","kind":"direct"}]}""").contains("route id invalid"),
        )
    }

    @Test
    fun `more than 8 routes are rejected`() {
        val routes = (1..9).joinToString(",") {
            """{"id":"r$it","kind":"direct"}"""
        }
        assertTrue(rejectedBy("""{"routes":[$routes]}""").contains("at most 8"))
    }

    @Test
    fun `assignment referencing an unknown route id is rejected`() {
        assertTrue(
            rejectedBy(
                """{"routes":[{"id":"r","kind":"direct"}],""" +
                    """"assignments":{"com.example.app":"nope"}}""",
            ).contains("unknown route"),
        )
    }

    // ================= the forwarding contract =================

    @Test
    fun `spec extra keys equal the service constants`() {
        // The activity reads with the SPEC's keys but forwards under the
        // SERVICE's — a drift on either side fails here, not on a device.
        assertEquals(AethoneVpnService.EXTRA_PORT, PoCControlStartSpec.EXTRA_PORT)
        assertEquals(AethoneVpnService.EXTRA_POC_ROUTES, PoCControlStartSpec.EXTRA_POC_ROUTES)
        assertEquals(AethoneVpnService.EXTRA_TCP_ONLY, PoCControlStartSpec.EXTRA_TCP_ONLY)
        assertEquals(AethoneVpnService.EXTRA_SOCKS_STRICT, PoCControlStartSpec.EXTRA_SOCKS_STRICT)
    }

    @Test
    fun `spec default port equals the service default`() {
        // AethoneVpnService's own fallback when the extra is absent.
        assertEquals(1819, PoCControlStartSpec.DEFAULT_PORT)
    }

    @Test
    fun `adb component is the DA package with the fq activity class`() {
        assertEquals(
            "com.chakcaad.aethone.da/com.chakcaad.aethone.PoCControlActivity",
            PoCControlStartSpec.ADB_COMPONENT,
        )
    }
}
