package com.chakcaad.aethone.shield

import android.content.Context
import android.content.SharedPreferences
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/// `aethone/family_shield` — the Family Shield method channel (phase 2).
///
/// Native is the source of truth: every call goes to [ShieldAdmin] (PIN
/// sessions, profiles, rules) or [FamilyShield] (status, live apply). All
/// work runs off the main thread. A mutating call that succeeded is applied
/// live (atomic snapshot swap + zeptun_revalidate_flows, no tunnel restart)
/// and the answer carries `applied` = null | error code ("not-running" =
/// takes effect at the next connect).
///
/// Settings export / import use the system document picker; MainActivity
/// owns the picker (onActivityResult) and calls [exportTo] / [importFrom].
object ShieldChannel {
    private const val TAG = "AethoneShieldCh"
    const val NAME = "aethone/family_shield"
    private const val FLUTTER_PREFS = "FlutterSharedPreferences"
    private const val FLUTTER_PREFIX = "flutter."

    fun register(context: Context, messenger: BinaryMessenger, picker: (String, Map<String, Any?>, MethodChannel.Result) -> Unit): MethodChannel {
        val app = context.applicationContext
        val ch = MethodChannel(messenger, NAME)
        ch.setMethodCallHandler { call, result ->
            @Suppress("UNCHECKED_CAST")
            val args = (call.arguments as? Map<String, Any?>) ?: emptyMap()
            when (call.method) {
                "settingsExport", "settingsImport" -> picker(call.method, args, result)
                else -> io(result) { handle(app, call.method, args) }
            }
        }
        return ch
    }

    fun handle(app: Context, method: String, args: Map<String, Any?>): Any? = when (method) {
        "status" -> FamilyShield.status(app)
        "exclusionAudit" -> FamilyShield.exclusionAudit(app).let { a ->
            mapOf("mode" to a.mode, "othersExcluded" to a.othersExcluded, "degrading" to a.degrading,
                "apps" to a.entries.map { mapOf("package" to it.packageName, "state" to it.state.wire) })
        }
        "flushEvents" -> { FamilyShield.flush(); mapOf("ok" to true) }
        else -> {
            if (method == "events") FamilyShield.flush() // batched rows first
            val r = FamilyShield.admin(app).handle(method, args)
            if (r["changed"] == true) {
                val err = FamilyShield.applyLive(app)
                r + mapOf("applied" to (err ?: "ok"))
            } else r
        }
    }

    private fun io(result: MethodChannel.Result, block: () -> Any?) {
        val main = Handler(Looper.getMainLooper())
        Thread({
            try {
                val v = block()
                main.post { result.success(v) }
            } catch (t: Throwable) {
                Log.e(TAG, "shield call failed", t)
                main.post { result.error("shield", t.javaClass.simpleName, null) }
            }
        }, "aethone-shield-io").start()
    }

    // ----------------------------------------------------- export / import

    private fun flutterPrefs(app: Context): SharedPreferences = app.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)

    fun currentPrefs(app: Context): List<SettingsBackup.Pref> = flutterPrefs(app).all.mapNotNull { (k, v) ->
        if (!k.startsWith(FLUTTER_PREFIX + SettingsBackup.PREF_PREFIX) || v == null) return@mapNotNull null
        val key = k.removePrefix(FLUTTER_PREFIX)
        when (v) {
            is String -> SettingsBackup.Pref(key, "s", v)
            is Boolean -> SettingsBackup.Pref(key, "b", v)
            is Long -> SettingsBackup.Pref(key, "l", v)
            is Int -> SettingsBackup.Pref(key, "i", v)
            is Float -> SettingsBackup.Pref(key, "f", v)
            else -> null // string sets are not used by the app
        }
    }

    fun exportText(app: Context): String {
        val ver = try { app.packageManager.getPackageInfo(app.packageName, 0).versionName } catch (_: Exception) { null }
        return SettingsBackup.export(currentPrefs(app), FamilyShield.repo(app), System.currentTimeMillis(), ver)
    }

    /// Validates and applies an import. When a parent PIN is set on THIS
    /// install, a live admin session is required (a child can not use an
    /// import to replace the protection). Returns the channel answer.
    fun importText(app: Context, text: String, token: String?): Map<String, Any?> {
        val pin = FamilyShield.pin(app)
        if (pin.isSet && !pin.checkToken(token)) return mapOf("ok" to false, "error" to "session-required")
        val parsed = try { SettingsBackup.parse(text) } catch (e: SettingsBackup.BackupError) {
            return mapOf("ok" to false, "error" to "invalid-file", "detail" to e.code)
        }
        val ed = flutterPrefs(app).edit()
        for (p in parsed.prefs) {
            val k = FLUTTER_PREFIX + p.key
            when (p.type) {
                "s" -> ed.putString(k, p.value as String)
                "b" -> ed.putBoolean(k, p.value as Boolean)
                "l" -> ed.putLong(k, p.value as Long)
                "i" -> ed.putInt(k, p.value as Int)
                "f" -> ed.putFloat(k, p.value as Float)
                "d" -> ed.putFloat(k, (p.value as Double).toFloat())
            }
        }
        if (!ed.commit()) return mapOf("ok" to false, "error" to "write-failed")
        var shieldImported = false
        parsed.shield?.let {
            SettingsBackup.applyShield(it, FamilyShield.repo(app), System.currentTimeMillis())
            FamilyShield.applyLive(app)
            shieldImported = true
        }
        return mapOf(
            "ok" to true,
            "prefs" to parsed.prefs.size,
            "shieldImported" to shieldImported,
            // the imported shield stays off until a parent PIN is set + it is enabled
            "pinRequired" to (shieldImported && !pin.isSet),
            // the Flutter side caches preferences: restart the app to load them
            "restartRequired" to true,
        )
    }
}
