package com.chakcaad.aethone.shield

import android.content.Context
import android.system.Os
import android.util.Log
import java.io.File
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import java.security.SecureRandom
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit

/// Family Shield phase 2.1 — the loopback gate session of the REAL cores.
///
/// When the shield is enabled and a TUN (tunnel mode) session starts, the app
/// arms one gate session: a fresh 256-bit secret in
/// `noBackupFilesDir/loopback-gate/secret` (dir 0700, file 0600 — app-private,
/// never in argv, never backed up). Every core is started against it:
///
/// | listener | guard (runtime) |
/// |----------|-----------------|
/// | Aether 1819 / 1820 (tor) / 1821 (psiphon forward) / http proxies | in-core accept gate (scripts/aether-loopback-gate.patch): own-process socket match, RST otherwise; the socks5 server also admits the session secret (RFC 1929) for the Psiphon child |
/// | Psiphon child's own socks5 (random loopback port, or 1821 in reverse mode) | LocalProxyAuthLoopback + LocalProxyUsername/Password (scripts/psiphon-local-proxy-auth.patch) |
/// | Lantern 1822 (sing-box mixed inbound) | inbound users = the secret (scripts/radiance-socks-auth.patch, `--socks-auth-file`); UDP forced off (sing's UDP relay re-latches to any sender) |
///
/// zeptun authenticates with the same credentials (`[handler.socks5]`
/// username/password). Status never trusts this table: [probe] verifies each
/// declared / known listener from ANOTHER process at runtime.
object LoopbackSession {
    private const val TAG = "AethoneGate"
    const val USER = "aethone"
    private const val DIR = "loopback-gate"

    data class Session(val file: File, val secret: String) {
        val credentials: SocksAuth.Credentials get() = SocksAuth.Credentials(USER, secret)
    }

    @Volatile private var current: Session? = null

    private fun dir(context: Context) = File(context.noBackupFilesDir, DIR)

    /// A new session (new secret) for the next tunnel. Throws when the file
    /// can not be written privately (the caller then starts no gated core).
    @Synchronized
    fun arm(context: Context): Session {
        val d = dir(context)
        if (!d.isDirectory && !d.mkdirs()) throw IllegalStateException("loopback-gate dir")
        Os.chmod(d.absolutePath, 0x1c0) // 0700
        val secret = ByteArray(32).also { SecureRandom().nextBytes(it) }.joinToString("") { "%02x".format(it) }
        val f = File(d, "secret")
        val tmp = File(d, "secret.tmp")
        tmp.delete()
        tmp.writeText(secret)
        Os.chmod(tmp.absolutePath, 0x180) // 0600
        if (!tmp.renameTo(f)) throw IllegalStateException("loopback-gate secret")
        File(d, "aether-listeners.json").delete()
        probeCache.clear()
        return Session(f, secret).also { current = it; Log.i(TAG, "loopback gate armed (session secret rotated)") }
    }

    /// No gate for the next session (shield off, or proxy mode).
    @Synchronized
    fun disarm(context: Context) {
        current = null
        probeCache.clear()
        val d = dir(context)
        File(d, "secret").delete()
        File(d, "aether-listeners.json").delete()
    }

    /// The armed session, if any. After a process restart the secret file
    /// may still exist: it is re-adopted (the cores of that session read it).
    fun current(context: Context): Session? {
        current?.let { return it }
        val f = File(dir(context), "secret")
        val s = try { f.readText().trim() } catch (_: Exception) { return null }
        if (s.length != 64 || !s.all { it in '0'..'9' || it in 'a'..'f' }) return null
        return Session(f, s).also { current = it }
    }

    // ------------------------------------------------------------ status

    /// A listener the Aether core declares (its runtime list, written by the
    /// gate next to the secret).
    data class Declared(val port: Int, val kind: String, val guard: String)

    fun declared(context: Context): List<Declared> {
        val f = File(dir(context), "aether-listeners.json")
        val text = try { f.readText() } catch (_: Exception) { return emptyList() }
        return try {
            val o = org.json.JSONObject(text)
            if (o.optInt("pid", -1) != android.os.Process.myPid()) return emptyList()
            val a = o.optJSONArray("listeners") ?: return emptyList()
            (0 until a.length()).map { i ->
                val l = a.getJSONObject(i)
                Declared(l.getInt("port"), l.optString("kind"), l.optString("guard"))
            }
        } catch (_: Exception) { emptyList() }
    }

    /// The result of one foreign-process probe of a loopback listener.
    enum class Probe(val wire: String, val refused: Boolean) {
        /// the listener answered a no-auth SOCKS5 greeting with "no auth" — open to anyone
        ANSWERED_NO_AUTH("answered-no-auth", false),
        /// [5, 0xFF]: no acceptable method (auth required)
        AUTH_REQUIRED("auth-required", true),
        /// reset / closed before any byte (accept gate)
        RESET("reset", true),
        /// some other answer (not a usable no-auth SOCKS5 session)
        OTHER("other", true),
        /// the probe could not run (no toybox nc): fail-closed, never guarded
        UNAVAILABLE("probe-unavailable", false),
    }

    private data class Cached(val at: Long, val probe: Probe)
    private val probeCache = ConcurrentHashMap<Int, Cached>()

    /// Probes 127.0.0.1:[port] from ANOTHER process (toybox nc, a child of
    /// this app: same uid, different process — exactly what the own-process
    /// gate must refuse, and it holds no secret). Sends a no-auth SOCKS5
    /// greeting. Cached 15 s per port.
    fun probe(port: Int, now: Long = System.currentTimeMillis()): Probe {
        probeCache[port]?.let { if (now - it.at < 15_000) return it.probe }
        val p = foreignGreeting(port)
        probeCache[port] = Cached(now, p)
        return p
    }

    private fun foreignGreeting(port: Int): Probe {
        val nc = listOf("/system/bin/toybox", "/system/bin/nc").firstOrNull { File(it).canExecute() } ?: return Probe.UNAVAILABLE
        val cmd = if (nc.endsWith("toybox")) listOf(nc, "nc", "-w", "2", "127.0.0.1", port.toString())
        else listOf(nc, "-w", "2", "127.0.0.1", port.toString())
        return try {
            val proc = ProcessBuilder(cmd).redirectErrorStream(false).start()
            proc.outputStream.use { it.write(byteArrayOf(5, 1, 0)); it.flush() }
            val buf = ByteArray(16)
            var n = 0
            val reader = Thread {
                try {
                    val ins = proc.inputStream
                    while (n < 2) { val r = ins.read(buf, n, buf.size - n); if (r < 0) break; n += r }
                } catch (_: Exception) {}
            }
            reader.start()
            reader.join(3500)
            if (!proc.waitFor(1, TimeUnit.SECONDS)) proc.destroyForcibly()
            val exit = try { proc.exitValue() } catch (_: Exception) { -1 }
            when {
                n >= 2 && buf[0] == 5.toByte() && buf[1] == 0.toByte() -> Probe.ANSWERED_NO_AUTH
                n >= 2 && buf[0] == 5.toByte() && buf[1] == 0xff.toByte() -> Probe.AUTH_REQUIRED
                n == 0 && exit == 127 -> Probe.UNAVAILABLE
                n == 0 -> Probe.RESET
                else -> Probe.OTHER
            }
        } catch (t: Throwable) {
            Log.w(TAG, "foreign probe of $port could not run: ${t.javaClass.simpleName}")
            Probe.UNAVAILABLE
        }
    }

    /// Plain TCP reachability from this process (cheap: is anything listening).
    fun listening(port: Int): Boolean = try {
        Socket().use { s -> s.connect(InetSocketAddress(InetAddress.getByName("127.0.0.1"), port), 150); true }
    } catch (_: Exception) { false }

    /// Pure decision (unit-tested): a listening port counts as guarded only
    /// when a guard is in force for it at runtime ([guard] non-null: declared
    /// by the gated core, or owned by a LoopbackGuard listener, or the Lantern
    /// sidecar started with the session secret) AND the foreign probe was
    /// refused. Anything else — including a probe that could not run — is
    /// exposed.
    fun guarded(listening: Boolean, guard: String?, probe: Probe?): Boolean =
        listening && guard != null && probe != null && probe.refused
}
