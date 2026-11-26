package com.chakcaad.aethone.shield

import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/// Family Shield — parent PIN core (pure JVM; the Android Keystore pepper is
/// injected, see KeystorePepper).
///
///  * KDF: PBKDF2-HMAC-SHA256 (RFC 8018), 16-byte random salt, 600 000
///    iterations by default (OWASP Password Storage Cheat Sheet,
///    PBKDF2-HMAC-SHA256: 600,000). Implemented on Mac("HmacSHA256") so it is
///    identical on API 24/25 (no PBKDF2WithHmacSHA256 there) and on the JVM.
///  * Pepper (post-hash): stored = HMAC(Keystore key, PBKDF2(pin, salt)).
///    The key never leaves the Keystore, so a copied database can not be
///    brute-forced off the device (a 6-digit PIN has only 10^6 values — the
///    KDF cost alone would not stop that).
///  * Backoff: 5 free attempts, then 30 s doubling per failure, capped at 1 h;
///    the counter and lock survive restarts (persisted before answering).
///  * One-time recovery code (shown once at setup, only its hash is kept).
///  * Short-lived session token (5 min) for admin operations.
///  * No default PIN: until a PIN is set every admin operation is refused.
interface Pepper {
    fun mac(data: ByteArray): ByteArray
}

data class PinState(
    val iterations: Int,
    val salt: ByteArray,
    val hash: ByteArray,
    val failCount: Int = 0,
    val lockedUntil: Long = 0L,
    val recoverySalt: ByteArray? = null,
    val recoveryHash: ByteArray? = null,
    val recoveryUsed: Boolean = false,
    val biometricEnabled: Boolean = false,
    val createdAt: Long = 0L,
) {
    override fun equals(other: Any?): Boolean = other is PinState && other.iterations == iterations &&
        other.salt.contentEquals(salt) && other.hash.contentEquals(hash) && other.failCount == failCount &&
        other.lockedUntil == lockedUntil && other.recoveryUsed == recoveryUsed
    override fun hashCode(): Int = hash.contentHashCode()
}

class ParentPin(
    private val repo: ShieldRepository,
    private val pepper: Pepper,
    private val clock: () -> Long = System::currentTimeMillis,
    private val iterations: Int = DEFAULT_ITERATIONS,
    private val random: SecureRandom = SecureRandom(),
) {
    companion object {
        const val DEFAULT_ITERATIONS = 600_000
        const val FREE_ATTEMPTS = 5
        const val BASE_LOCK_MS = 30_000L
        const val MAX_LOCK_MS = 3_600_000L
        const val SESSION_MS = 5 * 60_000L
        const val MIN_LEN = 6
        const val MAX_LEN = 12
        private const val RECOVERY_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

        fun pbkdf2(password: ByteArray, salt: ByteArray, iterations: Int, length: Int = 32): ByteArray {
            require(iterations >= 1)
            val mac = Mac.getInstance("HmacSHA256")
            // SecretKeySpec refuses an empty key; PINs / recovery codes are never empty
            require(password.isNotEmpty()) { "empty secret" }
            mac.init(SecretKeySpec(password, "HmacSHA256"))
            val out = ByteArray(length)
            var block = 1
            var pos = 0
            while (pos < length) {
                mac.update(salt)
                mac.update(byteArrayOf((block ushr 24).toByte(), (block ushr 16).toByte(), (block ushr 8).toByte(), block.toByte()))
                var u = mac.doFinal()
                val t = u.copyOf()
                for (i in 1 until iterations) {
                    u = mac.doFinal(u)
                    for (j in t.indices) t[j] = (t[j].toInt() xor u[j].toInt()).toByte()
                }
                val n = minOf(t.size, length - pos)
                System.arraycopy(t, 0, out, pos, n)
                pos += n
                block++
            }
            return out
        }

        /// PIN rules: 6–12 digits, not one repeated digit, not a straight
        /// ascending/descending run, not a well-known PIN.
        fun pinProblem(pin: String): String? {
            if (pin.length !in MIN_LEN..MAX_LEN) return "length"
            if (!pin.all { it in '0'..'9' }) return "digits-only"
            if (pin.toSet().size == 1) return "repeated"
            val d = pin.map { it - '0' }
            if (d.zipWithNext().all { (a, b) -> b == (a + 1) % 10 }) return "sequence"
            if (d.zipWithNext().all { (a, b) -> b == (a + 9) % 10 }) return "sequence"
            if (pin in setOf("123123", "121212", "112233", "696969", "131313", "123321", "654321")) return "common"
            return null
        }
    }

    sealed class Result {
        data class Ok(val token: String, val expiresAt: Long) : Result()
        data class Wrong(val attemptsBeforeLock: Int, val lockedUntil: Long) : Result()
        data class Locked(val until: Long) : Result()
        object NotSet : Result()
    }

    private val sessions = HashMap<String, Long>()

    val isSet: Boolean get() = repo.pinState() != null

    private fun derive(secret: String, salt: ByteArray, iters: Int): ByteArray =
        pepper.mac(pbkdf2(secret.toByteArray(Charsets.UTF_8), salt, iters))

    private fun randomBytes(n: Int) = ByteArray(n).also { random.nextBytes(it) }

    private fun newRecoveryCode(): String {
        val sb = StringBuilder()
        repeat(16) { i ->
            if (i > 0 && i % 4 == 0) sb.append('-')
            sb.append(RECOVERY_ALPHABET[random.nextInt(RECOVERY_ALPHABET.length)])
        }
        return sb.toString()
    }

    private fun normRecovery(code: String) = code.uppercase().filter { it.isLetterOrDigit() }

    /// First-time setup only (no default PIN exists). Returns the one-time
    /// recovery code, which is shown once and never stored in clear.
    @Synchronized fun setup(pin: String, biometric: Boolean = false): String {
        check(repo.pinState() == null) { "PIN already set" }
        return store(pin, biometric)
    }

    /// Changes the PIN; needs a live admin session. Issues a new recovery code.
    @Synchronized fun change(token: String, newPin: String): String {
        check(checkToken(token)) { "admin session required" }
        val bio = repo.pinState()?.biometricEnabled ?: false
        return store(newPin, bio)
    }

    private fun store(pin: String, biometric: Boolean): String {
        pinProblem(pin)?.let { throw IllegalArgumentException("weak PIN: $it") }
        val salt = randomBytes(16)
        val code = newRecoveryCode()
        val rsalt = randomBytes(16)
        repo.savePinState(
            PinState(
                iterations = iterations,
                salt = salt,
                hash = derive(pin, salt, iterations),
                recoverySalt = rsalt,
                recoveryHash = derive(normRecovery(code), rsalt, iterations),
                biometricEnabled = biometric,
                createdAt = clock(),
            ),
        )
        sessions.clear()
        return code
    }

    @Synchronized fun verify(pin: String): Result = attempt { s -> MessageDigest.isEqual(derive(pin, s.salt, s.iterations), s.hash) }

    /// One-time recovery: a correct code opens a session (to set a new PIN)
    /// and is consumed. Wrong codes count toward the same backoff.
    @Synchronized fun recover(code: String): Result = attempt(consumeRecovery = true) { s ->
        val rh = s.recoveryHash
        val rs = s.recoverySalt
        !s.recoveryUsed && rh != null && rs != null && MessageDigest.isEqual(derive(normRecovery(code), rs, s.iterations), rh)
    }

    private fun attempt(consumeRecovery: Boolean = false, check: (PinState) -> Boolean): Result {
        val s = repo.pinState() ?: return Result.NotSet
        val now = clock()
        if (s.lockedUntil > now) return Result.Locked(s.lockedUntil)
        if (check(s)) {
            repo.savePinState(s.copy(failCount = 0, lockedUntil = 0L, recoveryUsed = s.recoveryUsed || consumeRecovery))
            return issue(now)
        }
        val fails = s.failCount + 1
        val lock = lockFor(fails)
        val until = if (lock > 0) now + lock else 0L
        // persisted BEFORE answering: killing the app does not reset backoff
        repo.savePinState(s.copy(failCount = fails, lockedUntil = until))
        return Result.Wrong(maxOf(0, FREE_ATTEMPTS - fails), until)
    }

    fun lockFor(fails: Int): Long {
        if (fails < FREE_ATTEMPTS) return 0L
        val steps = fails - FREE_ATTEMPTS
        if (steps >= 20) return MAX_LOCK_MS
        return minOf(MAX_LOCK_MS, BASE_LOCK_MS shl steps)
    }

    private fun issue(now: Long): Result.Ok {
        val token = randomBytes(24).joinToString("") { "%02x".format(it) }
        val exp = now + SESSION_MS
        sessions.entries.removeAll { it.value <= now }
        sessions[token] = exp
        return Result.Ok(token, exp)
    }

    /// True while [token] is a live admin session (expired ones are dropped).
    @Synchronized fun checkToken(token: String?): Boolean {
        if (token == null) return false
        val exp = sessions[token] ?: return false
        if (exp <= clock()) {
            sessions.remove(token)
            return false
        }
        return true
    }

    @Synchronized fun endSessions() = sessions.clear()

    @Synchronized fun setBiometric(token: String, on: Boolean) {
        check(checkToken(token)) { "admin session required" }
        val s = repo.pinState() ?: error("no PIN")
        repo.savePinState(s.copy(biometricEnabled = on))
    }

    /// Biometric unlock (BiometricPrompt success with the Keystore-bound
    /// key): opens a session only when the parent enabled it and the PIN is
    /// not locked out. The prompt itself lives in the activity (phase 2).
    @Synchronized fun biometricSession(): Result {
        val s = repo.pinState() ?: return Result.NotSet
        if (!s.biometricEnabled) return Result.Wrong(0, 0L)
        val now = clock()
        if (s.lockedUntil > now) return Result.Locked(s.lockedUntil)
        return issue(now)
    }
}

/// Test / non-Android pepper: HMAC-SHA256 with a fixed key.
class StaticPepper(private val key: ByteArray) : Pepper {
    override fun mac(data: ByteArray): ByteArray {
        val m = Mac.getInstance("HmacSHA256")
        m.init(SecretKeySpec(key, "HmacSHA256"))
        return m.doFinal(data)
    }
}
