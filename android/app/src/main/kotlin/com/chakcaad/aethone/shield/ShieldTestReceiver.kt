package com.chakcaad.aethone.shield

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import dev.zeptun.Zeptun
import java.io.InputStream
import java.io.OutputStream
import java.net.InetAddress
import java.net.Socket

/// CI emulator self-test driver for Family Shield (phase 2).
///
/// Two locks, both required:
///  * the receiver is NOT exported — only root / system (the CI harness runs
///    `adb root`) can deliver to it; no app on a device can;
///  * the system property `debug.aethone.shieldtest` must be `1` (set by the
///    harness; a production device never has it).
/// It drives the SAME admin API the method channel uses (PIN session,
/// profiles, rules, applyLive). The only test-specific hook is
/// [FamilyShield.testRestrictedAppIds] (the shell uid 2000 has no package).
///
/// It also hosts the SOCKS stub the emulator test tunnels into: a minimal
/// SOCKS5 server on 127.0.0.1:1819 behind [LoopbackGuard] that records every
/// CONNECT it receives (the "did blocked traffic leak into the tunnel" log)
/// and answers a banner. Every result is one logcat line, tag
/// `AethoneShieldTest`: `RESULT <name> <json>`.
class ShieldTestReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION = "com.chakcaad.aethone.SHIELD_TEST"
        private const val TAG = "AethoneShieldTest"
        const val TEST_PIN = "583920"
        @Volatile private var token: String? = null
        @Volatile private var stub: LoopbackGuard.GuardedListener? = null
        /// phase 2.1: the REAL Aether core job started by core-start
        @Volatile private var coreJob: Long = -1
        @Volatile private var coreLogRedirected = false

        fun enabledByProperty(): Boolean = try {
            val p = Runtime.getRuntime().exec(arrayOf("getprop", "debug.aethone.shieldtest"))
            val v = p.inputStream.bufferedReader().readText().trim()
            p.waitFor()
            v == "1"
        } catch (_: Throwable) {
            false
        }

        fun result(name: String, v: Any?) = Log.i(TAG, "RESULT $name ${MiniJson.write(v)}")
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION) return
        val pending = goAsync()
        val app = context.applicationContext
        Thread({
            try {
                if (!enabledByProperty()) {
                    Log.w(TAG, "self-test disabled (debug.aethone.shieldtest != 1)")
                    return@Thread
                }
                run(app, intent.getStringExtra("cmd") ?: "", intent)
            } catch (t: Throwable) {
                Log.e(TAG, "self-test command failed", t)
                result("error", mapOf("cmd" to intent.getStringExtra("cmd"), "error" to (t.javaClass.simpleName + ": " + t.message)))
            } finally {
                pending.finish()
            }
        }, "aethone-shield-test").start()
    }

    /// The process may be restarted between commands (state lives in the
    /// SQLite store): the session is re-opened with the test PIN on demand.
    private fun session(app: Context): String? {
        val pin = FamilyShield.pin(app)
        if (!pin.checkToken(token) && pin.isSet) {
            token = (ShieldChannel.handle(app, "pinVerify", mapOf("pin" to TEST_PIN)) as Map<*, *>)["token"] as? String
        }
        return token
    }

    private fun profileId(app: Context, k: String?): String? =
        FamilyShield.repo(app).profiles().firstOrNull { it.name == "ci-" + (k ?: "a") }?.id

    private fun admin(app: Context, m: String, a: Map<String, Any?> = emptyMap()): Map<String, Any?> {
        val r = ShieldChannel.handle(app, m, a + mapOf("token" to session(app)))
        @Suppress("UNCHECKED_CAST")
        return r as Map<String, Any?>
    }

    private fun run(app: Context, cmd: String, i: Intent) {
        when (cmd) {
            "setup" -> {
                if (!FamilyShield.pin(app).isSet) ShieldChannel.handle(app, "pinSetup", mapOf("pin" to TEST_PIN))
                session(app)
                val profileIds = HashMap<String, String?>()
                for (k in listOf("a", "b")) {
                    if (profileId(app, k) == null) admin(app, "createProfile", mapOf("name" to "ci-$k", "preset" to "custom"))
                    profileIds[k] = profileId(app, k)
                    admin(app, "setUnknownPolicy", mapOf("profileId" to profileIds[k], "policy" to "allow"))
                }
                admin(app, "addRule", mapOf("profileId" to profileIds["a"], "kind" to "root", "value" to "blocked.aethone-test.example", "action" to "block"))
                admin(app, "addRule", mapOf("profileId" to profileIds["b"], "kind" to "root", "value" to "switch.aethone-test.example", "action" to "block"))
                admin(app, "switchProfile", mapOf("id" to profileIds["a"]))
                val en = admin(app, "setEnabled", mapOf("enabled" to true))
                // negative: a gated call without a session must be refused
                val refused = FamilyShield.admin(app).handle("setEnabled", mapOf("enabled" to false))
                result("setup", mapOf("ok" to (token != null && en["ok"] == true), "gatedWithoutToken" to refused["error"], "profiles" to profileIds))
            }
            "stub" -> {
                stub?.stop()
                stub = LoopbackGuard.GuardedListener(app, i.getIntExtra("port", 1819), { e, v, from ->
                    result("guard", mapOf("verdict" to v.toString(), "from" to from.toString(), "ownProcess" to e.ownProcess,
                        "uidClientView" to e.uidClientView, "uidServerView" to e.uidServerView, "ownUid" to e.ownUid))
                }) { s -> socks(s) }.start()
                result("stub", mapOf("ok" to true, "pid" to android.os.Process.myPid(), "procNetTcpReadable" to LoopbackGuard.procNetReadable()))
            }
            "stub-stop" -> { stub?.stop(); stub = null; result("stub-stop", mapOf("ok" to true)) }
            "block", "allow-rule" -> {
                val r = admin(app, "addRule", mapOf("profileId" to profileId(app, i.getStringExtra("profile")),
                    "kind" to "root", "value" to i.getStringExtra("domain"), "action" to "block"))
                result(cmd, mapOf("ok" to r["ok"], "applied" to r["applied"], "error" to r["error"]))
            }
            "switch" -> {
                val r = admin(app, "switchProfile", mapOf("id" to profileId(app, i.getStringExtra("to"))))
                result("switch", mapOf("ok" to r["ok"], "applied" to r["applied"], "error" to r["error"], "to" to i.getStringExtra("to")))
            }
            "restrict-uid" -> {
                val uid = i.getIntExtra("uid", -1)
                if (i.getBooleanExtra("on", true)) FamilyShield.testRestrictedAppIds += uid % 100_000
                else FamilyShield.testRestrictedAppIds -= uid % 100_000
                val rv = try { Zeptun.nativeRevalidateFlows() } catch (t: Throwable) { -99 }
                result("restrict-uid", mapOf("uid" to uid, "on" to i.getBooleanExtra("on", true), "revalidate" to rv))
            }
            "status" -> result("status", FamilyShield.status(app) + mapOf("pid" to android.os.Process.myPid()))
            "own-connect" -> {
                // an in-process client of the guarded listener (must be admitted)
                val port = i.getIntExtra("port", 1819)
                val ok = try {
                    Socket(InetAddress.getByName("127.0.0.1"), port).use { s ->
                        s.soTimeout = 3000
                        s.getOutputStream().write(byteArrayOf(5, 1, 0))
                        val b = ByteArray(2)
                        readFully(s.getInputStream(), b)
                        b[0] == 5.toByte() && b[1] == 0.toByte()
                    }
                } catch (_: Exception) { false }
                result("own-connect", mapOf("handshake" to ok))
            }
            // ---------------------------------------------- phase 2.1: real cores
            "core-start" -> {
                // the REAL in-process Aether core (libaether.so, same C API as
                // the app's dart:ffi path) with the loopback gate armed
                val mode = i.getStringExtra("mode") ?: "masque"
                val gate = i.getBooleanExtra("gate", true)
                redirectCoreLog(app)
                stopCore()
                val session = if (gate) LoopbackSession.arm(app) else { LoopbackSession.disarm(app); null }
                val files = app.filesDir.absolutePath
                val lib = app.applicationInfo.nativeLibraryDir
                val args = mutableListOf(
                    "--bind", "127.0.0.1:1819", "--config", "$files/aether/warp.toml", "--log-level", "info",
                    "--scan", "turbo", "--quick-reconnect", "--protocol", "masque",
                )
                when (mode) {
                    "psiphon-only", "psiphon-chain" -> {
                        args += if (mode == "psiphon-only") "--psiphon-only" else "--psiphon"
                        args += listOf("--psiphon-bin", "$lib/libpsiphon.so", "--psiphon-dir", "$files/aether/psiphon")
                    }
                    "tor-chain" -> {
                        args += "--tor"
                        for (pt in listOf("obfs4", "snowflake", "webtunnel", "meek_lite")) args += listOf("--tor-pt", "$pt=$lib/liblyrebird.so")
                        args += listOf("--tor-dir", "$files/aether/tor-state")
                    }
                }
                session?.let { args += listOf("--loopback-gate", it.file.absolutePath) }
                val reply = Zeptun.nativeAetherCall(0, org.json.JSONArray(args).toString(), 0)
                coreJob = try { org.json.JSONObject(reply).optLong("job", -1) } catch (_: Exception) { -1 }
                result("core-start", mapOf("mode" to mode, "gate" to gate, "job" to coreJob, "ok" to (coreJob >= 0), "reply" to reply.take(300)))
            }
            "core-poll" -> result("core-poll", mapOf("job" to coreJob, "reply" to if (coreJob >= 0) Zeptun.nativeAetherCall(1, null, coreJob).take(600) else "none"))
            "core-stop" -> { stopCore(); result("core-stop", mapOf("ok" to true)) }
            "lantern-start" -> {
                redirectCoreLog(app)
                val gate = i.getBooleanExtra("gate", true)
                if (gate) LoopbackSession.arm(app) else LoopbackSession.disarm(app)
                com.chakcaad.aethone.LanternSidecar.start(app, 1822, java.io.File(app.filesDir, "lantern-e2e").absolutePath, "en-US", 150, "")
                result("lantern-start", mapOf("ok" to true, "authArmed" to com.chakcaad.aethone.LanternSidecar.authArmed))
            }
            "lantern-stop" -> { com.chakcaad.aethone.LanternSidecar.stop(); result("lantern-stop", mapOf("ok" to true)) }
            "lantern-status" -> result("lantern-status", com.chakcaad.aethone.LanternSidecar.status())
            "listeners" -> {
                val ls = FamilyShield.probeListeners(app)
                result("listeners", mapOf(
                    "gate" to (LoopbackSession.current(app) != null),
                    "declared" to LoopbackSession.declared(app).map { mapOf("port" to it.port, "kind" to it.kind, "guard" to it.guard) },
                    "listeners" to ls.map { mapOf("port" to it.port, "listening" to it.listening, "guarded" to it.guarded, "guard" to it.guard, "probe" to it.probe, "kind" to it.kind) },
                ))
            }
            "own-socks" -> {
                // an in-process SOCKS5 client (the app's own probe path): with
                // the session credentials when `auth` (wrong ones with `wrong`),
                // then CONNECT www.cloudflare.com:80 and one HTTP request
                val port = i.getIntExtra("port", 1819)
                val auth = i.getBooleanExtra("auth", true)
                val wrong = i.getBooleanExtra("wrong", false)
                result("own-socks", ownSocks(app, port, auth, wrong, i.getBooleanExtra("connect", true)) + mapOf("port" to port))
            }
            "break" -> {
                // fail-closed check: enabled shield whose active profile is gone
                val repo = FamilyShield.repo(app)
                repo.saveConfig(repo.config().copy(activeProfileId = "missing-profile", generation = repo.config().generation + 1))
                result("break", mapOf("ok" to true))
            }
            "repair" -> {
                val repo = FamilyShield.repo(app)
                repo.saveConfig(repo.config().copy(activeProfileId = profileId(app, "a"), generation = repo.config().generation + 1))
                result("repair", mapOf("ok" to true))
            }
            "export" -> {
                val text = ShieldChannel.exportText(app)
                val parsed = SettingsBackup.parse(text)
                result("export", mapOf("bytes" to text.length, "prefs" to parsed.prefs.size,
                    "profiles" to parsed.shield?.profiles?.size, "containsPin" to text.contains(TEST_PIN)))
            }
            else -> result("unknown", mapOf("cmd" to cmd))
        }
    }

    private fun stopCore() {
        val id = coreJob
        if (id < 0) return
        try { Zeptun.nativeAetherCall(2, null, id) } catch (_: Throwable) {}
        // the core lets go of its listeners as the job ends
        for (n in 0 until 40) {
            val r = try { Zeptun.nativeAetherCall(1, null, id) } catch (_: Throwable) { "" }
            if (!r.contains("running")) break
            Thread.sleep(250)
        }
        try { Zeptun.nativeAetherCall(3, null, id) } catch (_: Throwable) {}
        coreJob = -1
    }

    /// The core logs to fd 2 (env_logger) and the child cores inherit it: in
    /// the test process it goes to files/shield-e2e-core.log (read by the
    /// harness as root). Installed once per process.
    private fun redirectCoreLog(app: Context) {
        if (coreLogRedirected) return
        try {
            val f = java.io.File(app.filesDir, "shield-e2e-core.log")
            val fos = java.io.FileOutputStream(f, true)
            android.system.Os.dup2(fos.fd, 2)
            android.system.Os.dup2(fos.fd, 1)
            coreLogRedirected = true
        } catch (t: Throwable) {
            Log.w(TAG, "core log redirect failed", t)
        }
    }

    private fun ownSocks(app: Context, port: Int, auth: Boolean, wrong: Boolean, connect: Boolean): Map<String, Any?> {
        val out = LinkedHashMap<String, Any?>()
        val creds = LoopbackSession.current(app)?.credentials
        try {
            Socket().use { s ->
                s.connect(java.net.InetSocketAddress(InetAddress.getByName("127.0.0.1"), port), 3000)
                s.soTimeout = 15_000
                val o = s.getOutputStream()
                val inp = s.getInputStream()
                val withAuth = auth && creds != null
                o.write(if (withAuth) byteArrayOf(5, 2, 0, 2) else byteArrayOf(5, 1, 0))
                val m = ByteArray(2); readFully(inp, m)
                out["method"] = m[1].toInt() and 0xff
                if (m[1].toInt() == 0x02) {
                    val user = creds!!.username.toByteArray()
                    val pass = (if (wrong) "00".repeat(32) else creds.password).toByteArray()
                    o.write(byteArrayOf(1, user.size.toByte()) + user + byteArrayOf(pass.size.toByte()) + pass)
                    val a = ByteArray(2); readFully(inp, a)
                    out["auth"] = if (a[1].toInt() == 0) "ok" else "refused"
                    if (a[1].toInt() != 0) { out["handshake"] = false; return out }
                } else if (m[1].toInt() != 0) { out["handshake"] = false; return out }
                out["handshake"] = true
                if (!connect) return out
                val host = "www.cloudflare.com".toByteArray()
                o.write(byteArrayOf(5, 1, 0, 3, host.size.toByte()) + host + byteArrayOf(0, 80))
                s.soTimeout = 60_000
                val head = ByteArray(4); readFully(inp, head)
                out["connectReply"] = head[1].toInt() and 0xff
                if (head[1].toInt() != 0) return out
                val skip = when (head[3].toInt()) { 1 -> 4; 4 -> 16; 3 -> inp.read(); else -> 0 }
                readFully(inp, ByteArray(skip + 2))
                o.write("GET /cdn-cgi/trace HTTP/1.1\r\nHost: www.cloudflare.com\r\nConnection: close\r\n\r\n".toByteArray())
                val body = inp.readBytes().toString(Charsets.ISO_8859_1)
                out["http"] = body.lineSequence().firstOrNull()?.take(40)
                out["traceIp"] = Regex("(?m)^ip=(.*)$").find(body)?.groupValues?.get(1)?.let { if (it.isNotEmpty()) "present" else null }
            }
        } catch (e: Exception) {
            out["error"] = e.javaClass.simpleName + ":" + (e.message ?: "")
        }
        return out
    }

    private fun readFully(input: InputStream, b: ByteArray) {
        var o = 0
        while (o < b.size) {
            val n = input.read(b, o, b.size - o)
            if (n < 0) throw java.io.EOFException()
            o += n
        }
    }

    /// Minimal SOCKS5 (no auth, CONNECT only) that records the destination.
    private fun socks(s: Socket) {
        s.soTimeout = 0
        val inp = s.getInputStream()
        val out: OutputStream = s.getOutputStream()
        val head = ByteArray(2)
        readFully(inp, head)
        if (head[0] != 5.toByte()) return
        readFully(inp, ByteArray(head[1].toInt() and 0xff))
        out.write(byteArrayOf(5, 0))
        val req = ByteArray(4)
        readFully(inp, req)
        val host = when (req[3].toInt()) {
            1 -> ByteArray(4).also { readFully(inp, it) }.let { InetAddress.getByAddress(it).hostAddress }
            4 -> ByteArray(16).also { readFully(inp, it) }.let { "[" + InetAddress.getByAddress(it).hostAddress + "]" }
            3 -> { val l = inp.read(); ByteArray(l).also { readFully(inp, it) }.toString(Charsets.US_ASCII) }
            else -> return
        }
        val pb = ByteArray(2)
        readFully(inp, pb)
        val port = ((pb[0].toInt() and 0xff) shl 8) or (pb[1].toInt() and 0xff)
        val dest = "$host:$port"
        if (req[1].toInt() != 1) {
            out.write(byteArrayOf(5, 7, 0, 1, 0, 0, 0, 0, 0, 0)) // command not supported
            result("stub-refused", mapOf("dest" to dest, "cmd" to req[1].toInt()))
            return
        }
        result("stub-connect", mapOf("dest" to dest))
        out.write(byteArrayOf(5, 0, 0, 1, 0, 0, 0, 0, 0, 0))
        out.write("AETHONE-STUB $dest\n".toByteArray())
        out.flush()
        val t0 = System.currentTimeMillis()
        var reason = "eof"
        try {
            val buf = ByteArray(4096)
            while (inp.read(buf) >= 0) { /* drain */ }
        } catch (e: Exception) {
            reason = e.javaClass.simpleName + ":" + (e.message ?: "")
        }
        result("stub-close", mapOf("dest" to dest, "reason" to reason, "ms" to (System.currentTimeMillis() - t0)))
    }
}
