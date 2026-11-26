package com.chakcaad.aethone.shield

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.PBEKeySpec

/// Family Shield — parent PIN core: KDF, verify, backoff, recovery, sessions.
class ParentPinTest {
    private var now = 1_000_000L
    private val repo = InMemoryShieldRepository()
    // few iterations keep the test fast; production uses 600 000
    private val pin = ParentPin(repo, StaticPepper(ByteArray(32) { 7 }), { now }, iterations = 1000)

    @Test fun pbkdf2MatchesRfc7914AndJca() {
        // RFC 7914 §11, PBKDF2-HMAC-SHA256 test vector 1
        val out = ParentPin.pbkdf2("passwd".toByteArray(), "salt".toByteArray(), 1, 64)
        assertEquals(
            "55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc49ca9cccf179b645991664b39d77ef317c71b845b1e30bd509112041d3a19783",
            out.joinToString("") { "%02x".format(it) },
        )
        val salt = ByteArray(16) { it.toByte() }
        val mine = ParentPin.pbkdf2("482915".toByteArray(), salt, 2000)
        val jca = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")
            .generateSecret(PBEKeySpec("482915".toCharArray(), salt, 2000, 256)).encoded
        assertArrayEquals(jca, mine)
        assertEquals(600_000, ParentPin.DEFAULT_ITERATIONS)
    }

    @Test fun noDefaultPinAndWeakPinsRefused() {
        assertFalse(pin.isSet)
        assertEquals(ParentPin.Result.NotSet, pin.verify("000000"))
        for (weak in listOf("12345", "111111", "123456", "987654", "12a456", "1234567890123")) {
            try { pin.setup(weak); throw AssertionError(weak) } catch (_: IllegalArgumentException) {}
        }
        assertFalse(pin.isSet)
    }

    @Test fun verifyIssuesShortLivedSession() {
        pin.setup("482915")
        val s = repo.pinState()!!
        assertEquals(16, s.salt.size)
        assertFalse(s.hash.contentEquals(ParentPin.pbkdf2("482915".toByteArray(), s.salt, 1000))) // peppered
        val ok = pin.verify("482915") as ParentPin.Result.Ok
        assertTrue(pin.checkToken(ok.token))
        now += ParentPin.SESSION_MS + 1
        assertFalse(pin.checkToken(ok.token))
        assertFalse(pin.checkToken(null))
        assertFalse(pin.checkToken("forged"))
    }

    @Test fun backoffLocksAndSurvivesRestart() {
        pin.setup("482915")
        repeat(4) { assertTrue(pin.verify("000001") is ParentPin.Result.Wrong) }
        val fifth = pin.verify("000001") as ParentPin.Result.Wrong
        assertEquals(now + 30_000L, fifth.lockedUntil)
        // even the right PIN is refused while locked
        assertTrue(pin.verify("482915") is ParentPin.Result.Locked)
        // a "restarted app" (new instance, same store) is still locked
        val again = ParentPin(repo, StaticPepper(ByteArray(32) { 7 }), { now }, iterations = 1000)
        assertTrue(again.verify("482915") is ParentPin.Result.Locked)
        now += 30_001
        assertTrue(pin.verify("000002") is ParentPin.Result.Wrong) // 6th fail → 60 s
        assertEquals(now + 60_000L, repo.pinState()!!.lockedUntil)
        now += 60_001
        assertTrue(pin.verify("482915") is ParentPin.Result.Ok)
        assertEquals(0, repo.pinState()!!.failCount)
        assertEquals(ParentPin.MAX_LOCK_MS, pin.lockFor(40))
    }

    @Test fun recoveryCodeIsOneTime() {
        val code = pin.setup("482915")
        assertEquals(19, code.length)
        val ok = pin.recover(code.lowercase().replace("-", " ")) as ParentPin.Result.Ok
        val newCode = pin.change(ok.token, "730164")
        assertTrue(pin.verify("730164") is ParentPin.Result.Ok)
        assertTrue(pin.verify("482915") is ParentPin.Result.Wrong)
        // the old code is gone; the new one works once
        assertTrue(pin.recover(code) is ParentPin.Result.Wrong)
        assertTrue(pin.recover(newCode) is ParentPin.Result.Ok)
        assertTrue(pin.recover(newCode) is ParentPin.Result.Wrong)
    }

    @Test fun adminOpsNeedSession() {
        pin.setup("482915")
        try { pin.change("nope", "730164"); throw AssertionError() } catch (_: IllegalStateException) {}
        try { pin.setup("730164"); throw AssertionError() } catch (_: IllegalStateException) {}
        assertTrue(pin.biometricSession() is ParentPin.Result.Wrong) // biometric not enabled
        val t = (pin.verify("482915") as ParentPin.Result.Ok).token
        pin.setBiometric(t, true)
        assertTrue(pin.biometricSession() is ParentPin.Result.Ok)
        pin.endSessions()
        assertFalse(pin.checkToken(t))
    }
}
