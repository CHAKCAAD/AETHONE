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
        private val profileIds = HashMap<String, String>()

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

    private fun admin(app: Context, m: String, a: Map<String, Any?> = emptyMap()): Map<String, Any?> {
        val r = ShieldChannel.handle(app, m, a + mapOf("token" to token))
        @Suppress("UNCHECKED_CAST")
        return r as Map<String, Any?>
    }

    private fun run(app: Context, cmd: String, i: Intent) {
        when (cmd) {
            "setup" -> {
                if (!FamilyShield.pin(app).isSet) admin(app, "pinSetup", mapOf("pin" to TEST_PIN))
                val v = admin(app, "pinVerify", mapOf("pin" to TEST_PIN))
                token = v["token"] as? String
                for (k in listOf("a", "b")) {
                    @Suppress("UNCHECKED_CAST")
                    val p = admin(app, "createProfile", mapOf("name" to "ci-$k", "preset" to "custom"))["profile"] as Map<String, Any?>
                    profileIds[k] = p["id"] as String
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
                result("stub", mapOf("ok" to true, "procNetTcpReadable" to LoopbackGuard.procNetReadable()))
            }
            "block", "allow-rule" -> {
                val r = admin(app, "addRule", mapOf("profileId" to (i.getStringExtra("profile")?.let { profileIds[it] } ?: profileIds["a"]),
                    "kind" to "root", "value" to i.getStringExtra("domain"), "action" to "block"))
                result(cmd, mapOf("ok" to r["ok"], "applied" to r["applied"], "error" to r["error"]))
            }
            "switch" -> {
                val r = admin(app, "switchProfile", mapOf("id" to profileIds[i.getStringExtra("to") ?: "a"]))
                result("switch", mapOf("ok" to r["ok"], "applied" to r["applied"], "to" to i.getStringExtra("to")))
            }
            "restrict-uid" -> {
                val uid = i.getIntExtra("uid", -1)
                if (i.getBooleanExtra("on", true)) FamilyShield.testRestrictedAppIds += uid % 100_000
                else FamilyShield.testRestrictedAppIds -= uid % 100_000
                val rv = try { Zeptun.nativeRevalidateFlows() } catch (t: Throwable) { -99 }
                result("restrict-uid", mapOf("uid" to uid, "on" to i.getBooleanExtra("on", true), "revalidate" to rv))
            }
            "status" -> result("status", FamilyShield.status(app))
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
            "break" -> {
                // fail-closed check: enabled shield whose active profile is gone
                val repo = FamilyShield.repo(app)
                repo.saveConfig(repo.config().copy(activeProfileId = "missing-profile", generation = repo.config().generation + 1))
                result("break", mapOf("ok" to true))
            }
            "repair" -> {
                val repo = FamilyShield.repo(app)
                repo.saveConfig(repo.config().copy(activeProfileId = profileIds["a"], generation = repo.config().generation + 1))
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
