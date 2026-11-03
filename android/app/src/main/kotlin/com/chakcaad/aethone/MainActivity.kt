package com.chakcaad.aethone

import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/// Hosts the `aethone/engine` MethodChannel — the M2 seam between the Dart
/// PlatformEngineAdapter and the Android side (paths, VPN consent, service
/// lifecycle, zeptun counters, the v4.19 proxy core-hold). Tunnel events
/// flow back through [EngineBridge].
class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "AethoneMain"
        private const val REQ_VPN_PERMISSION = 4711

        /// v4.19 (#1 diagnostics): the last Java-level crash lands here so
        /// the next device test can hand it over even without adb.
        const val CRASH_LOG = "aethone-crash.txt"
    }

    private var pendingPermissionResult: MethodChannel.Result? = null

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
                    val intent = Intent(this, AethoneVpnService::class.java)
                        .putExtra(AethoneVpnService.EXTRA_PORT, port)
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
