package com.chakcaad.aethone.shield

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/// Family Shield phase 2.1: real-core loopback guards — the status rule that
/// a listener is guarded only from runtime evidence (a guard in force AND a
/// refused foreign-process probe), and the zeptun credential lines.
class ShieldPhase21Test {
    private fun st(vararg l: ShieldStatus.Listener) = ShieldStatus.compute(
        ShieldStatus.Inputs(enabled = true, tunnelUp = true, snapshotLive = true, listeners = l.toList()),
    )

    @Test fun guardedNeedsAGuardAndARefusedForeignProbe() {
        val P = LoopbackSession.Probe
        assertTrue(LoopbackSession.guarded(true, "own-process", P.RESET))
        assertTrue(LoopbackSession.guarded(true, "secret", P.AUTH_REQUIRED))
        assertTrue(LoopbackSession.guarded(true, "own-process+secret", P.OTHER))
        // a declared guard whose listener still answers no-auth is exposed
        assertFalse(LoopbackSession.guarded(true, "own-process", P.ANSWERED_NO_AUTH))
        // no runtime guard (an unpatched core that happens to reset) is exposed
        assertFalse(LoopbackSession.guarded(true, null, P.RESET))
        // a probe that could not run is never evidence
        assertFalse(LoopbackSession.guarded(true, "secret", P.UNAVAILABLE))
        assertFalse(LoopbackSession.guarded(true, "secret", null))
        assertFalse(LoopbackSession.guarded(false, "secret", P.AUTH_REQUIRED))
    }

    @Test fun statusIsProtectedOnlyWhenEveryListeningPortIsGuarded() {
        val aether = ShieldStatus.Listener(1819, true, true, "own-process+secret", "reset", "socks5")
        val psiChild = ShieldStatus.Listener(40123, true, true, "secret", "auth-required", "psiphon child socks5")
        val forward = ShieldStatus.Listener(1821, true, true, "own-process", "reset", "psiphon socks5")
        assertEquals(ShieldStatus.State.PROTECTED, st(aether, psiChild, forward).state)
        val lanternOpen = ShieldStatus.Listener(1822, true, false, null, "answered-no-auth", "lantern")
        val r = st(aether, psiChild, forward, lanternOpen)
        assertEquals(ShieldStatus.State.DEGRADED, r.state)
        assertEquals(listOf("local-socks-exposed:1822"), r.reasons)
        // the Psiphon child's random port is reported like any other listener
        val childOpen = psiChild.copy(guarded = false, guard = null, probe = "answered-no-auth")
        assertEquals(listOf("local-socks-exposed:40123"), st(aether, childOpen).reasons)
    }

    @Test fun zeptunCredentialLines() {
        val secret = "ab".repeat(32)
        val lines = SocksAuth.tomlLines(SocksAuth.Credentials(LoopbackSession.USER, secret))
        assertEquals("username = \"aethone\"\npassword = \"$secret\"", lines)
        assertEquals("", SocksAuth.tomlLines(null))
    }
}
