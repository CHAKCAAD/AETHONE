package com.chakcaad.aethone

import android.content.Context
import android.util.Log
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.security.SecureRandom
import java.util.concurrent.TimeUnit
import org.json.JSONObject

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

    /// The control endpoint of the RUNNING sidecar (loopback port + bearer
    /// token), used for Lantern server listing / selection.
    @Volatile
    private var controlPort: Int = 0

    @Volatile
    private var controlToken: String = ""

    /// A free loopback port for the control socket. The sidecar binds it a
    /// moment later; the token still guards every request.
    private fun freeLoopbackPort(): Int =
        ServerSocket(0, 1, InetAddress.getByName("127.0.0.1")).use { it.localPort }

    @Synchronized
    fun start(
        context: Context,
        port: Int,
        dataDir: String,
        locale: String,
        connectTimeout: Int = 180,
        location: String = "",
    ) {
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
        val ctlPort = freeLoopbackPort()
        val budget = connectTimeout.coerceIn(30, 300)
        val cmd = listOf(
            bin.absolutePath,
            "--data-dir", data.absolutePath,
            "--log-dir", logs.absolutePath,
            "--socks-address", "127.0.0.1:$port",
            // App-chosen loopback control port + per-process bearer token
            // (Lantern server listing / selection — see control()).
            "--control-socket", "127.0.0.1:$ctlPort",
            "--control-token", token,
            "--locale", locale,
            "--autoconnect",
            "--connect-timeout", budget.toString(),
        ) + (
            // v1.0.2 — the Lantern location pick: connect straight to it.
            if (location.matches(Regex("^[A-Za-z]{2}$"))) listOf("--location", location.uppercase())
            else emptyList()
        )
        val pb = ProcessBuilder(cmd)
            .directory(data)
            .redirectOutput(ProcessBuilder.Redirect.INHERIT)
            .redirectError(ProcessBuilder.Redirect.INHERIT)
        pb.environment()["HOME"] = data.absolutePath
        pb.environment()["TMPDIR"] = context.cacheDir.absolutePath
        lastExit = null
        process = pb.start()
        controlPort = ctlPort
        controlToken = token
        Log.i(TAG, "Lantern sidecar started (socks 127.0.0.1:$port)")
    }

    @Synchronized
    fun stop() {
        val p = process ?: return
        process = null
        controlPort = 0
        controlToken = ""
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

    /// One request on the sidecar's control socket: a JSON line
    /// {token, method, path, body} out, one JSON line back. Blocking —
    /// call off the main thread. Throws when the sidecar is not running.
    fun control(method: String, path: String, body: String?): String {
        val p = process
        val ctl = controlPort
        if (p == null || !p.isAlive || ctl == 0) {
            throw IllegalStateException("the Lantern sidecar is not running")
        }
        val req = JSONObject()
            .put("token", controlToken)
            .put("method", method)
            .put("path", path)
        if (!body.isNullOrEmpty()) req.put("body", JSONObject(body))
        Socket().use { sock ->
            sock.connect(InetSocketAddress("127.0.0.1", ctl), 3000)
            // /ping can block up to ~60 s inside Radiance.
            sock.soTimeout = 90_000
            val out = OutputStreamWriter(sock.getOutputStream(), Charsets.UTF_8)
            out.write(req.toString())
            out.write("\n")
            out.flush()
            val reader = BufferedReader(InputStreamReader(sock.getInputStream(), Charsets.UTF_8))
            return reader.readLine() ?: throw IllegalStateException("empty Lantern control reply")
        }
    }
}
