package com.chakcaad.aethone.shield

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import dev.zeptun.Zeptun
import java.io.File
import java.security.MessageDigest

/// Real-device test driver for Family Shield — DEBUG SOURCE SET ONLY.
///
/// This class lives in `src/debug/` and is declared only in
/// `src/debug/AndroidManifest.xml`, so it exists solely in the debuggable
/// device-acceptance build (`com.chakcaad.aethone.da`). Release builds do not
/// contain it (the CI job `device-test-apk` fails if a release APK ever
/// declares it). Driven by `scripts/device-test/shield.sh`.
///
/// Three locks, all required:
///  * the receiver is exported only with `android:permission=
///    "android.permission.DUMP"` — held by the adb shell, grantable to an
///    ordinary app only through adb (`development` protection level), so no
///    app on the phone can drive it;
///  * the system property `debug.aethone.shieldtest` must be `1` (set by the
///    owner's script over adb, cleared by `hooks.sh off` and by a reboot);
///  * it only exists in the debug-signed DA build.
///
/// It calls the SAME admin API the method channel uses
/// ([ShieldChannel.handle], PIN-session gated) and the same export/import
/// code as the picker ([ShieldChannel.exportText] / [ShieldChannel.importText]).
/// Results: one logcat line per command, tag `AethoneDeviceTest`,
/// `RESULT <cmd> <json>`.
class DeviceTestReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION = "com.chakcaad.aethone.DEVICE_TEST"
        private const val TAG = "AethoneDeviceTest"
        /// The device-test build's parent PIN (the same fixed test PIN the CI
        /// e2e uses). Never used by a release build.
        const val TEST_PIN = ShieldTestReceiver.TEST_PIN
        const val PROFILE = "device-test"
        @Volatile private var token: String? = null

        fun result(name: String, v: Any?) = Log.i(TAG, "RESULT $name ${MiniJson.write(v)}")
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION) return
        val pending = goAsync()
        val app = context.applicationContext
        val cmd = intent.getStringExtra("cmd") ?: ""
        Thread({
            try {
                if (!ShieldTestReceiver.enabledByProperty()) {
                    Log.w(TAG, "device test hooks disabled (debug.aethone.shieldtest != 1)")
                    result("disabled", mapOf("cmd" to cmd))
                    return@Thread
                }
                run(app, cmd, intent)
            } catch (t: Throwable) {
                Log.e(TAG, "device test command failed", t)
                result("error", mapOf("cmd" to cmd, "error" to (t.javaClass.simpleName + ": " + t.message)))
            } finally {
                pending.finish()
            }
        }, "aethone-device-test").start()
    }

    private fun session(app: Context): String? {
        val pin = FamilyShield.pin(app)
        if (pin.isSet && !pin.checkToken(token)) {
            token = (ShieldChannel.handle(app, "pinVerify", mapOf("pin" to TEST_PIN)) as Map<*, *>)["token"] as? String
        }
        return token
    }

    private fun activeProfile(app: Context): String? = FamilyShield.repo(app).config().activeProfileId

    @Suppress("UNCHECKED_CAST")
    private fun handle(app: Context, method: String, a: Map<String, Any?>, withSession: Boolean = true): Map<String, Any?> {
        val args = if (withSession) a + mapOf("token" to session(app)) else a
        return (ShieldChannel.handle(app, method, args) as? Map<String, Any?>) ?: mapOf("ok" to false, "error" to "no-answer")
    }

    /// Extras `a.<key>` become admin arguments (typed by `am`: --es/--ez/--ei/--el);
    /// `a.<outer>.<inner>` builds a nested map (e.g. `a.strict.enabled`).
    /// The string value `@active` is replaced by the active profile id.
    @Suppress("UNCHECKED_CAST", "DEPRECATION")
    private fun extrasArgs(app: Context, i: Intent): Map<String, Any?> {
        val b = i.extras ?: return emptyMap()
        val out = LinkedHashMap<String, Any?>()
        for (k in b.keySet()) {
            if (!k.startsWith("a.")) continue
            var v: Any? = b.get(k)
            if (v == "@active") v = activeProfile(app)
            val path = k.removePrefix("a.").split('.')
            var m: MutableMap<String, Any?> = out
            for (p in path.dropLast(1)) {
                m = (m.getOrPut(p) { LinkedHashMap<String, Any?>() } as MutableMap<String, Any?>)
            }
            m[path.last()] = v
        }
        return out
    }

    private fun dir(app: Context): File = File(app.getExternalFilesDir(null), "device-test").apply { mkdirs() }

    private fun sha256(b: ByteArray): String = MessageDigest.getInstance("SHA-256").digest(b).joinToString("") { "%02x".format(it) }

    private fun run(app: Context, cmd: String, i: Intent) {
        when (cmd) {
            "ping" -> result("ping", mapOf("ok" to true, "pid" to android.os.Process.myPid(), "package" to app.packageName))
            // PIN + one custom profile ("device-test", unknown = allow) + shield enabled.
            "setup" -> {
                val pin = FamilyShield.pin(app)
                var recovery: Any? = null
                if (!pin.isSet) recovery = (ShieldChannel.handle(app, "pinSetup", mapOf("pin" to TEST_PIN)) as Map<*, *>)["recoveryCode"]
                session(app)
                var pid = FamilyShield.repo(app).profiles().firstOrNull { it.name == PROFILE }?.id
                if (pid == null) {
                    handle(app, "createProfile", mapOf("name" to PROFILE, "preset" to (i.getStringExtra("preset") ?: "custom")))
                    pid = FamilyShield.repo(app).profiles().firstOrNull { it.name == PROFILE }?.id
                }
                handle(app, "setUnknownPolicy", mapOf("profileId" to pid, "policy" to "allow"))
                val sw = handle(app, "switchProfile", mapOf("id" to pid))
                val en = handle(app, "setEnabled", mapOf("enabled" to true))
                result("setup", mapOf("ok" to (token != null && en["ok"] == true), "profileId" to pid,
                    "switch" to sw["ok"], "enable" to en, "recoveryCode" to recovery))
            }
            "status" -> result("status", FamilyShield.status(app) + mapOf("pid" to android.os.Process.myPid()))
            "config" -> result("config", handle(app, "config", emptyMap(), withSession = false))
            // Generic admin call: --es method <name> plus a.<arg> extras.
            // --ez nosession true sends it WITHOUT a parent session (gating / backoff tests).
            "admin" -> {
                val m = i.getStringExtra("method") ?: throw IllegalArgumentException("missing method")
                val r = handle(app, m, extrasArgs(app, i), withSession = !i.getBooleanExtra("nosession", false))
                result("admin", mapOf("method" to m, "answer" to r))
            }
            // Shell-uid (2000) app restriction: the shell has no package, so the
            // real restrictApp path can not name it (same hook as the CI e2e).
            "restrict-uid" -> {
                val uid = i.getIntExtra("uid", 2000)
                val on = i.getBooleanExtra("on", true)
                if (on) FamilyShield.testRestrictedAppIds += uid % 100_000 else FamilyShield.testRestrictedAppIds -= uid % 100_000
                val rv = try { Zeptun.nativeRevalidateFlows() } catch (t: Throwable) { -99 }
                result("restrict-uid", mapOf("uid" to uid, "on" to on, "revalidate" to rv))
            }
            "export-file" -> {
                val text = ShieldChannel.exportText(app)
                val f = File(dir(app), i.getStringExtra("file") ?: "aethone-settings-export.json")
                val bytes = text.toByteArray(Charsets.UTF_8)
                f.writeBytes(bytes)
                val parsed = SettingsBackup.parse(text)
                result("export-file", mapOf("ok" to true, "path" to f.absolutePath, "bytes" to bytes.size, "sha256" to sha256(bytes),
                    "prefs" to parsed.prefs.size, "profiles" to parsed.shield?.profiles?.size,
                    "containsTestPin" to text.contains(TEST_PIN)))
            }
            "import-file" -> {
                val f = File(dir(app), i.getStringExtra("file") ?: "aethone-settings-export.json")
                if (!f.isFile) {
                    result("import-file", mapOf("ok" to false, "error" to "no-file", "path" to f.absolutePath))
                    return
                }
                val bytes = f.readBytes()
                if (bytes.size > SettingsBackup.MAX_BYTES) {
                    result("import-file", mapOf("ok" to false, "error" to "invalid-file", "detail" to "too-large"))
                    return
                }
                val tok = if (i.getBooleanExtra("nosession", false)) null else session(app)
                val r = ShieldChannel.importText(app, String(bytes, Charsets.UTF_8), tok)
                result("import-file", r + mapOf("path" to f.absolutePath, "sha256" to sha256(bytes)))
            }
            else -> result("unknown", mapOf("cmd" to cmd))
        }
    }
}
