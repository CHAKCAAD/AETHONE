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
import java.io.FileInputStream
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
/// v4.21 diagnostics + v4.26 bounds (owner device-test rounds 3–4):
///  * the PROCESS stderr (fd 1 + fd 2) is redirected ONCE per process onto
///    a pipe drained by a reader thread that writes a BOUNDED, ROTATING
///    `filesDir/logs/core-log.txt` (≈2 MiB hard ceiling) — the embedded
///    Aether core, zeptun and the child cores (lyrebird / psiphon) all log
///    there, and the old unbounded append used to grow ~80 MB per hour of
///    use (owner: «حدود ۸۰ مگ داده تو ۱ ساعت استفاده»);
///  * `readCoreLog` / `clearCoreLog` channel methods tail/clear that file
///    for the settings diagnostics page;
///  * `setCoreJob` / `getCoreJob` / `clearCoreJob` carry the PROCESS-durable
///    aether job id (isolate-restart hardening — see the companion doc).
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

        /// v4.26 — the previous rotation (the capture keeps at most ONE).
        const val CORE_LOG_PREV = "core-log.1.txt"

        /// v4.26 — the capture is BOUNDED now: the reader thread rotates the
        /// file at this size and keeps one previous rotation, so the whole
        /// capture tops out at ≈2× this. The old append-mode redirect was
        /// capped only at activity start — a tunnel session that kept the
        /// process alive for hours grew the file unbounded (~80 MB per hour
        /// of use with the chatty child cores; owner round 4:
        /// «حدود ۸۰ مگ داده تو ۱ ساعت»).
        private const val CORE_LOG_MAX_BYTES = 1L * 1024 * 1024

        /// v4.26 — the pipe+reader redirect installs exactly ONCE per
        /// process (every activity recreation used to open ANOTHER
        /// FileOutputStream and dup2 over it, leaking a fd each time).
        @Volatile
        private var logRedirectInstalled = false

        /// v4.26 — the reader thread is the single writer: a clear request
        /// is consumed on its next chunk (no sparse append offsets).
        @Volatile
        private var clearCoreLogRequested = false

        /// v4.26 — the PROCESS-DURABLE aether job id (owner round 4:
        /// «توی حالت متصل هم وقتی اتصال رو قطع میکنی همچنان تونل فعاله…
        /// باید اپ رو کلا بندی»). The Rust job registry is process-scoped,
        /// but the Dart isolate is not: after the activity/engine is
        /// recreated the fresh adapter had no job id, its disconnect
        /// cancelled NOTHING and the orphaned core kept the SOCKS port bound
        /// until a force-close. The companion outlives the isolate, so the
        /// fresh adapter adopts the id on resync (`getCoreJob`) and the
        /// disconnect actually cancels the core.
        @Volatile
        private var coreJobId: Int? = null
    }

    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        installCoreLogRedirect()
    }

    /// v4.34 — owner round 10: «هنوز هم داده های زیادی تولید میکنه اپ که
    /// فکر میکنم به خاطر لاگ هسته ها باشه لطفا بعد از هربار بسته شدن اپ
    /// فایل لاگ حذف بشه تا انقدر داده جمع نشه». The capture dies with the
    /// CLOSED app:
    ///  * at process start the redirect wipes BOTH generations — every
    ///    process starts with an EMPTY capture (a force-killed session
    ///    leaves no residue either);
    ///  * when the activity finishes FOR REAL (back / swipe-away —
    ///    `isFinishing`, NOT a config-change recreation) the capture is
    ///    deleted right away; if the process lives on (a running tunnel
    ///    service), the single-writer reader thread reopens a FRESH file
    ///    on its next chunk — the capture never grows back from the old
    ///    one.
    override fun onDestroy() {
        if (EngineBridge.channel != null) {
            EngineBridge.channel = null
        }
        if (isFinishing) {
            clearCoreLog()
        }
        super.onDestroy()
    }

    /// v4.26 — BOUNDED, ROTATING capture. The process stdout+stderr are
    /// dup2'd onto a pipe drained by a dedicated reader thread that writes
    /// `core-log.txt`, rotating at [CORE_LOG_MAX_BYTES] into
    /// `core-log.1.txt` (one previous generation kept). The redirect installs
    /// exactly ONCE per process (the old code re-opened a new append stream
    /// and dup2'd over it on every activity recreation, leaking a fd each
    /// time and never capping the file DURING a session).
    ///
    /// Rust's env_logger (aether), the zeptun JNI bridge and the spawned
    /// child cores (lyrebird / psiphon-tunnel-core — chatty at `info`) all
    /// write to fd 1/2, so everything still lands in the diagnostics tail —
    /// just bounded now. `Log.*` calls keep going to logcat (liblog, not
    /// stderr), so adb debugging is unaffected.
    private fun installCoreLogRedirect() {
        if (logRedirectInstalled) return
        try {
            val dir = File(filesDir, CORE_LOG_DIR)
            if (!dir.exists()) dir.mkdirs()
            val current = File(dir, CORE_LOG)
            // v4.34 — EVERY process starts with an empty capture (owner:
            // the log must not survive the closed app). The old code kept
            // a sub-ceiling current file across launches.
            current.delete()
            File(dir, CORE_LOG_PREV).delete()

            val pipe = Os.pipe()
            val reader = Thread({
                val buf = ByteArray(64 * 1024)
                val input = FileInputStream(pipe[0])
                var out: FileOutputStream? = null
                var written = 0L

                fun reopen(truncate: Boolean) {
                    try {
                        out?.close()
                    } catch (_: Throwable) {
                    }
                    out = null
                    if (!truncate && current.length() >= CORE_LOG_MAX_BYTES) {
                        val prev = File(dir, CORE_LOG_PREV)
                        prev.delete()
                        current.renameTo(prev)
                    }
                    out = FileOutputStream(current, !truncate)
                    written = 0L
                }

                try {
                    reopen(false)
                    val stamp = SimpleDateFormat(
                        "yyyy-MM-dd HH:mm:ss", Locale.US,
                    ).format(Date())
                    out!!.write("\n=== AETHONE session $stamp ===\n".toByteArray())
                    while (true) {
                        val n = input.read(buf)
                        if (n <= 0) break
                        if (clearCoreLogRequested) {
                            clearCoreLogRequested = false
                            reopen(true)
                        } else if (written >= CORE_LOG_MAX_BYTES) {
                            reopen(false)
                        }
                        out!!.write(buf, 0, n)
                        written += n
                    }
                } catch (_: Throwable) {
                    // Diagnostics only — never take the app down with it.
                }
            }, "aethone-core-log")
            reader.isDaemon = true
            reader.start()

            Os.dup2(pipe[1], 1)
            Os.dup2(pipe[1], 2)
            logRedirectInstalled = true
        } catch (t: Throwable) {
            // Diagnostics only — never let it break the app start.
            Log.w(TAG, "core-log redirect failed", t)
        }
    }

    /// The tail of the captured core log (bounded read from the end —
    /// v4.26: across the current file and its one previous rotation, so a
    /// tail request right after a rotation still shows recent lines).
    private fun readCoreLog(tailBytes: Int): Map<String, Any?> {
        return try {
            val dir = File(filesDir, CORE_LOG_DIR)
            val current = File(dir, CORE_LOG)
            val prev = File(dir, CORE_LOG_PREV)
            if (!current.exists()) {
                return mapOf("text" to "", "totalBytes" to 0L)
            }
            val tail = tailBytes.coerceIn(1024, 1024 * 1024).toLong()
            val total = current.length() + prev.length()
            val fromPrev = (tail - current.length())
                .coerceAtLeast(0)
                .coerceAtMost(prev.length())
            val builder = StringBuilder()
            if (fromPrev > 0) {
                RandomAccessFile(prev, "r").use { raf ->
                    raf.seek(prev.length() - fromPrev)
                    val bytes = ByteArray(fromPrev.toInt())
                    raf.readFully(bytes)
                    builder.append(String(bytes, Charsets.UTF_8))
                }
            }
            RandomAccessFile(current, "r").use { raf ->
                val start = (current.length() - (tail - fromPrev))
                    .coerceAtLeast(0)
                raf.seek(start)
                val bytes = ByteArray((current.length() - start).toInt())
                raf.readFully(bytes)
                builder.append(String(bytes, Charsets.UTF_8))
            }
            mapOf(
                "text" to builder.toString(),
                "totalBytes" to total,
            )
        } catch (t: Throwable) {
            mapOf("text" to "read failed: ${t.message}", "totalBytes" to 0L)
        }
    }

    private fun clearCoreLog() {
        // The reader thread performs the truncation on its next chunk
        // (single-writer discipline). The immediate deletions give the UI
        // an instant effect; the reader reopens cleanly right after —
        // writes that went to the unlinked inode in between are simply
        // gone, which is exactly what "clear" promises.
        clearCoreLogRequested = true
        try {
            val dir = File(filesDir, CORE_LOG_DIR)
            File(dir, CORE_LOG).delete()
            File(dir, CORE_LOG_PREV).delete()
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
                    // v4.31 — the selected mode's UDP capability: TCP-only
                    // modes configure zeptun with udp=disabled so UDP flows
                    // get ICMP-unreachable instead of the core's silent
                    // drop (see AethoneVpnService.EXTRA_TCP_ONLY).
                    val tcpOnly = call.argument<Boolean>("tcpOnly") ?: false
                    // v4.26 — record the session BEFORE the start goes out:
                    // a stop that lands while this start is still in flight
                    // bumps the stop generation past it, and the straggler
                    // start then refuses to establish the TUN (the orphan
                    // tunnel of the lost-cancel bug).
                    AethoneVpnService.noteStart(session)
                    val intent = Intent(this, AethoneVpnService::class.java)
                        .putExtra(AethoneVpnService.EXTRA_PORT, port)
                        .putExtra(AethoneVpnService.EXTRA_SESSION, session)
                        .putExtra(AethoneVpnService.EXTRA_TCP_ONLY, tcpOnly)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(null)
                }
                "stopVpn" -> {
                    // v4.26 — the hardened stop: generation bump + direct
                    // instance teardown + stopService (see
                    // AethoneVpnService.requestStop). The old bare
                    // `stopService()` left the straggler-start and
                    // slow-onDestroy windows open.
                    AethoneVpnService.requestStop(this)
                    result.success(null)
                }
                // v4.26 — the process-durable aether job id (see the
                // companion doc): recorded at every coreStart, adopted by a
                // recreated isolate on resync, cleared with the session.
                "setCoreJob" -> {
                    coreJobId = call.argument<Int>("job")
                    result.success(null)
                }
                "getCoreJob" -> result.success(mapOf("job" to coreJobId))
                "clearCoreJob" -> {
                    coreJobId = null
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
