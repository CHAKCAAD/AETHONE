package com.chakcaad.aethone

import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.system.Os
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/// Hosts the `aethone/engine` MethodChannel — the M2 seam between the Dart
/// PlatformEngineAdapter and the Android side (paths, VPN consent, service
/// lifecycle, zeptun counters, the v4.19 proxy core-hold). Tunnel events
/// flow back through [EngineBridge].
///
/// v4.21 — two diagnostics additions (owner device-test round 3: «چطوره اون
/// بخش متن خطا لاگ کل هسته هارو هم بده تا بهتر بتونیم دیباگ کنیم»):
///  * the PROCESS stderr (fd 1 + fd 2) is redirected into
///    filesDir/logs/core-log.txt at activity start — the embedded Aether
///    core logs through env_logger → stderr, so its full startup/error
///    lines land in one tailable file (adb-free debugging on the owner's
///    device);
///  * `readCoreLog` / `clearCoreLog` channel methods tail/truncate that
///    file for the settings diagnostics page.
class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "AethoneMain"
        private const val REQ_VPN_PERMISSION = 4711

        /// v4.19 (#1 diagnostics): the last Java-level crash lands here so
        /// the next device test can hand it over even without adb.
        const val CRASH_LOG = "aethone-crash.txt"

        /// v4.21 — the captured stderr of the whole process (both engines).
        const val CORE_LOG_DIR = "logs"
        const val CORE_LOG = "core-log.txt"

        /// The capture is capped: a fresh file replaces anything larger
        /// (the tail the app shows needs the RECENT lines, not years of
        /// history).
        private const val CORE_LOG_MAX_BYTES = 4L * 1024 * 1024
    }

    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        installCoreLogRedirect()
    }

    /// v4.21 — dup2 the process stdout+stderr onto an append-mode file.
/// Rust's env_logger (aether) and the zeptun JNI both write to stderr;
/// Android normally routes that to logcat, which the app itself cannot
/// read back without READ_LOGS. After this redirect the lines ALSO land
    /// in a file the diagnostics page tails. Runs before any engine starts
    /// (the core is only ever started from Dart, which needs this activity).
    private fun installCoreLogRedirect() {
        try {
            val dir = File(filesDir, CORE_LOG_DIR)
            if (!dir.exists()) dir.mkdirs()
            val file = File(dir, CORE_LOG)
            if (file.length() > CORE_LOG_MAX_BYTES) {
                file.delete()
            }
            val out = FileOutputStream(file, true)
            // A session separator so consecutive runs are readable.
            val stamp = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date())
            out.write("\n=== AETHONE session $stamp ===\n".toByteArray())
            out.flush()
            val fd = out.fd
            Os.dup2(fd, 1)
            Os.dup2(fd, 2)
        } catch (t: Throwable) {
            // Diagnostics only — never let it break the app start.
            Log.w(TAG, "core-log redirect failed", t)
        }
    }

    /// The tail of the captured core log (bounded read from the end).
    private fun readCoreLog(tailBytes: Int): Map<String, Any?> {
        return try {
            val file = File(File(filesDir, CORE_LOG_DIR), CORE_LOG)
            if (!file.exists()) return mapOf("text" to "", "totalBytes" to 0L)
            val total = file.length()
            val tail = tailBytes.coerceIn(1024, 1024 * 1024).toLong()
            val start = (total - tail).coerceAtLeast(0)
            RandomAccessFile(file, "r").use { raf ->
                raf.seek(start)
                val bytes = ByteArray((total - start).toInt())
                raf.readFully(bytes)
                mapOf(
                    "text" to String(bytes, Charsets.UTF_8),
                    "totalBytes" to total,
                )
            }
        } catch (t: Throwable) {
            mapOf("text" to "read failed: ${t.message}", "totalBytes" to 0L)
        }
    }

    private fun clearCoreLog() {
        try {
            File(File(filesDir, CORE_LOG_DIR), CORE_LOG).delete()
        } catch (t: Throwable) {
            Log.w(TAG, "core-log clear failed", t)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        installCrashBreadcrumb()
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "aethone/engine",
        )
        EngineBridge.channel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "paths" -> result.success(
                    mapOf(
                        "filesDir" to filesDir.absolutePath,
                        "nativeLibraryDir" to applicationInfo.nativeLibraryDir,
                    ),
                )
                "prepareVpn" -> prepareVpn(result)
                "startVpn" -> {
                    val port = call.argument<Int>("port") ?: 1819
                    // v4.21 — the session stamp: every event this service
                    // instance emits carries it back, and Dart drops events
                    // from stale instances (the late-`destroy` race that
                    // failed fresh tunnel walks).
                    val session = call.argument<Int>("session") ?: 0
                    val intent = Intent(this, AethoneVpnService::class.java)
                        .putExtra(AethoneVpnService.EXTRA_PORT, port)
                        .putExtra(AethoneVpnService.EXTRA_SESSION, session)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(null)
                }
                "stopVpn" -> {
                    stopService(Intent(this, AethoneVpnService::class.java))
                    result.success(null)
                }
                "vpnStatus" -> result.success(AethoneVpnService.status())
                "zeptunCounters" -> result.success(AethoneVpnService.counters())
                // v4.19 (#7): the proxy-mode process hold (CoreHoldService).
                "startCoreHold" -> {
                    val port = call.argument<Int>("port") ?: 1819
                    val intent = Intent(this, CoreHoldService::class.java)
                        .putExtra(CoreHoldService.EXTRA_PORT, port)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(null)
                }
                "stopCoreHold" -> {
                    stopService(Intent(this, CoreHoldService::class.java))
                    result.success(null)
                }
                "coreHoldStatus" -> result.success(CoreHoldService.status())
                // v4.21 — the core diagnostics tail (settings log page).
                "readCoreLog" -> {
                    val tail = call.argument<Int>("tail") ?: 64 * 1024
                    result.success(readCoreLog(tail))
                }
                "clearCoreLog" -> {
                    clearCoreLog()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        // Best-effort notification permission (Android 13+): the foreground
        // services run without it too — the notification is simply hidden.
        if (Build.VERSION.SDK_INT >= 33) {
            requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 1)
        }
    }

    /// v4.19 (#1): the tunnel-mode crash on the owner's device could not be
    /// diagnosed without logs. Native crashes (SIGSEGV in an embedded core)
    /// are NOT catchable — but any uncaught JAVA throwable (the JNI bridge
    /// seam, the service lifecycle) now leaves a breadcrumb in filesDir
    /// before the process dies, so the next device test can fetch it with
    /// plain file access instead of adb logcat.
    private fun installCrashBreadcrumb() {
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            runCatching {
                val stamp = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US)
                    .format(Date())
                File(filesDir, CRASH_LOG).appendText(
                    "=== $stamp  thread=${thread.name} ===\n" +
                        Log.getStackTraceString(throwable) + "\n",
                )
            }
            previous?.uncaughtException(thread, throwable)
        }
    }

    override fun onDestroy() {
        if (EngineBridge.channel != null) {
            EngineBridge.channel = null
        }
        super.onDestroy()
    }

    private fun prepareVpn(result: MethodChannel.Result) {
        val intent = VpnService.prepare(this)
        if (intent == null) {
            result.success(mapOf("needsPermission" to false))
            return
        }
        pendingPermissionResult = result
        startActivityForResult(intent, REQ_VPN_PERMISSION)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQ_VPN_PERMISSION) {
            val granted = resultCode == RESULT_OK
            Log.i(TAG, "VPN permission granted=$granted")
            EngineBridge.emit(mapOf("event" to "permission", "granted" to granted))
            pendingPermissionResult?.success(mapOf("needsPermission" to true))
            pendingPermissionResult = null
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }
}
