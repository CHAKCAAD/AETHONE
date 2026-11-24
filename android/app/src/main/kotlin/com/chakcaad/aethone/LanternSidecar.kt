package com.chakcaad.aethone

import android.content.Context
import android.util.Log
import java.io.File
import java.security.SecureRandom
import java.util.concurrent.TimeUnit

/// feature/lantern-core — the Lantern core (getlantern/radiance) as a
/// SIDECAR process, the same shape MSN-GUARD's prototype proved
/// (core/lanternbridge, feature/lantern-prototype):
///
///  * the binary ships as jniLibs/<abi>/liblantern.so (extractNativeLibs /
///    useLegacyPackaging — it lands in nativeLibraryDir with the exec bit,
///    exactly like libpsiphon.so / liblyrebird.so);
///  * Radiance runs with RADIANCE_USE_SOCKS_PROXY: NO TUN of its own — a
///    loopback mixed SOCKS5/HTTP inbound on 127.0.0.1:1822. AETHONE stays
///    the sole owner of the VpnService; zeptun forwards the TUN to 1822 and
///    the app uid is already excluded from the TUN (no routing loop);
///  * `--autoconnect`: the sidecar connects to Lantern's public servers by
///    itself; the listener appears only once connected, so the Dart walk's
///    listener wait + end-to-end probe gate Connected;
///  * stdout/stderr are INHERITED: they land in the process' fd 1/2, which
///    MainActivity already captures into the core-log tail (diagnostics);
///  * telemetry stays off (lanternbridge.Init: TelemetryConsent = false).
object LanternSidecar {
    private const val TAG = "AethoneLantern"
    private const val BINARY = "liblantern.so"

    @Volatile
    private var process: Process? = null

    @Volatile
    private var lastExit: Int? = null

    @Synchronized
    fun start(context: Context, port: Int, dataDir: String, locale: String) {
        stop()
        val bin = File(context.applicationInfo.nativeLibraryDir, BINARY)
        if (!bin.exists()) {
            throw IllegalStateException(
                "$BINARY is not packaged in this build (nativeLibraryDir)",
            )
        }
        val data = File(dataDir).apply { mkdirs() }
        val logs = File(data, "logs").apply { mkdirs() }
        val token = ByteArray(24).also { SecureRandom().nextBytes(it) }
            .joinToString("") { "%02x".format(it) }
        val cmd = listOf(
            bin.absolutePath,
            "--data-dir", data.absolutePath,
            "--log-dir", logs.absolutePath,
            "--socks-address", "127.0.0.1:$port",
            // Ephemeral loopback control port + per-process bearer token
            // (kept for later server selection; unused by the walk).
            "--control-socket", "127.0.0.1:0",
            "--control-token", token,
            "--locale", locale,
            "--autoconnect",
            "--connect-timeout", "180",
        )
        val pb = ProcessBuilder(cmd)
            .directory(data)
            .redirectOutput(ProcessBuilder.Redirect.INHERIT)
            .redirectError(ProcessBuilder.Redirect.INHERIT)
        pb.environment()["HOME"] = data.absolutePath
        pb.environment()["TMPDIR"] = context.cacheDir.absolutePath
        lastExit = null
        process = pb.start()
        Log.i(TAG, "Lantern sidecar started (socks 127.0.0.1:$port)")
    }

    @Synchronized
    fun stop() {
        val p = process ?: return
        process = null
        try {
            p.destroy() // SIGTERM — the sidecar shuts Radiance down cleanly
            if (!p.waitFor(3, TimeUnit.SECONDS)) {
                p.destroyForcibly()
                p.waitFor(2, TimeUnit.SECONDS)
            }
            lastExit = try { p.exitValue() } catch (_: Throwable) { null }
        } catch (t: Throwable) {
            Log.w(TAG, "Lantern sidecar stop failed", t)
        }
    }

    fun status(): Map<String, Any?> {
        val p = process
        if (p != null && p.isAlive) {
            return mapOf("running" to true, "exitCode" to null)
        }
        val code = if (p != null) {
            try { p.exitValue() } catch (_: Throwable) { null }
        } else {
            lastExit
        }
        return mapOf("running" to false, "exitCode" to code)
    }
}
