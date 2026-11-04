package com.chakcaad.aethone

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat

import dev.zeptun.Zeptun

/// The whole-device tunnel («حالت اتصال: تونل»): establishes the TUN
/// interface through [VpnService.Builder] and hands its descriptor to the
/// embedded zeptun engine via the upstream JNI bridge (architecture B+).
///
/// Routing facts (prompt §4 + zeptun Android wiki, frozen pins):
///  * the SYSTEM owns the routes — `Builder` includes/excludes, `auto_route`
///    stays off (the mobile build drops the route module entirely);
///  * route-loop prevention: [Builder.addDisallowedApplication] exempts the
///    app's own uid (covers Aether, the UI and zeptun) AND zeptun's protect
///    callback routes its upstream sockets via `VpnService.protect`;
///  * the TUN parameters mirror zeptun's mobile preset defaults exactly:
///    MTU 1500, address 172.19.0.1/30 (device default), DNS 172.19.0.2
///    (dnsAddress4 = host(2) of the /30, answered by the fake-IP DNS).
///
/// The service is START_NOT_STICKY on purpose: the Aether core runs
/// in-process, so a sticky restart after process death would bring the
/// tunnel up with a DEAD core — a silent black hole. If the process dies,
/// the tunnel dies with it and the user reconnects (honest failure).
class AethoneVpnService : VpnService() {

    companion object {
        const val EXTRA_PORT = "port"

        /// v4.21 — the Dart-side tunnel-session stamp (see MainActivity's
        /// startVpn): every event THIS instance emits carries it back so the
        /// adapter can drop the stale instance's late `down/destroy` events
        /// (owner device-test: «در حالت تونل … tunnelStartFailed / destroy»
        /// from a service that was already being torn down).
        const val EXTRA_SESSION = "session"
        private const val TAG = "AethoneVpn"
        private const val CHANNEL_ID = "aethone_vpn"
        private const val NOTIFICATION_ID = 1

        // ZeptunStats field order (include/zeptun.h): 0 rx_packets,
        // 1 rx_bytes, 2 tx_packets, 3 tx_bytes. TUN rx = device → engine
        // (upload from the user's perspective); TUN tx = download.
        private const val STATS_RX_BYTES = 1
        private const val STATS_TX_BYTES = 3

        @Volatile
        private var instance: AethoneVpnService? = null

        fun status(): Map<String, Any?> {
            val svc = instance ?: return mapOf("running" to false, "port" to null)
            return mapOf("running" to true, "port" to svc.socksPort)
        }

        fun counters(): Map<String, Any?> {
            val svc = instance
                ?: return mapOf("rxBytes" to -1L, "txBytes" to -1L)
            return mapOf(
                "rxBytes" to svc.readCounter(STATS_RX_BYTES),
                "txBytes" to svc.readCounter(STATS_TX_BYTES),
            )
        }
    }

    private var descriptor: ParcelFileDescriptor? = null
    private var socksPort: Int = 1819
    private var zeptunUp = false

    /// v4.21 — the session stamp from the start intent (0 when absent,
    /// e.g. an external start); echoed on EVERY event this instance emits.
    private var sessionId: Int = 0

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForegroundCompat()
        val port = intent?.getIntExtra(EXTRA_PORT, 1819) ?: 1819
        socksPort = port
        sessionId = intent?.getIntExtra(EXTRA_SESSION, 0) ?: 0
        // v4.19 (#1 hardening): the tunnel leg is the one place where a
        // thrown Java-level error used to KILL the process mid-connection
        // (an UnsatisfiedLinkError from the JNI bridge, a lifecycle
        // exception…). Every throwable is now converted into the honest
        // "down" event — Dart fails the walk with tunnelStartFailed and the
        // app survives to show it. Native crashes (SIGSEGV inside the
        // embedded cores) stay uncatchable, as everywhere on Android — the
        // uncaught-exception breadcrumb in MainActivity covers the Java
        // seam and adb logcat remains the native-truth source.
        try {
            if (!startTunnel(port)) {
                EngineBridge.emit(downEvent("establish-failed"))
                stopSelf()
                return START_NOT_STICKY
            }
        } catch (t: Throwable) {
            Log.e(TAG, "tunnel start threw", t)
            EngineBridge.emit(downEvent("start-threw:${t.javaClass.simpleName}"))
            stopTunnel("start-threw")
            stopSelf()
            return START_NOT_STICKY
        }
        return START_NOT_STICKY
    }

    /// v4.21 — event maps stamped with THIS instance's session id.
    private fun upEvent(port: Int): Map<String, Any?> =
        mapOf("event" to "up", "port" to port, "session" to sessionId)

    private fun downEvent(reason: String): Map<String, Any?> =
        mapOf("event" to "down", "reason" to reason, "session" to sessionId)

    private fun startTunnel(port: Int): Boolean {
        if (zeptunUp) {
            // v4.20: a mode switch (e.g. 1819 → 1820) between connects used
            // to keep serving the OLD port — zeptun would relay into a
            // listener nothing serves anymore. A different target is a
            // full restart; the same target is the plain "already serving"
            // re-entry (activity restart re-invoked the service).
            if (port != socksPort) {
                Log.i(TAG, "socks target changed $socksPort -> $port; restarting zeptun")
                stopTunnel("port-change")
            } else {
                EngineBridge.emit(upEvent(port))
                return true
            }
        }
        val builder = Builder()
            .setSession("AETHONE")
            .setMtu(1500)
            .addAddress("172.19.0.1", 30)
            .addRoute("0.0.0.0", 0)
            .addDnsServer("172.19.0.2")
        try {
            builder.addDisallowedApplication(packageName)
        } catch (e: Exception) {
            // Only possible for a missing package name — record and continue;
            // zeptun's protect() callback is the second loop guard.
            Log.w(TAG, "addDisallowedApplication failed", e)
        }
        val fd: ParcelFileDescriptor = builder.establish() ?: run {
            Log.e(TAG, "Builder.establish() returned null (revoked or no permission)")
            return false
        }
        descriptor = fd

        // Must match ZeptunConfigToml.build on the Dart side (single source
        // of truth: the zeptun config keys at the frozen pin).
        val toml = """
            preset = "mobile"

            [handler]
            kind = "socks5"

            [handler.socks5]
            server = "127.0.0.1:$port"

            [dns]
            fake_ip = true
        """.trimIndent()

        val rc = Zeptun.nativeStart(this, fd.fd, toml)
        if (rc != 0) {
            Log.e(TAG, "zeptun nativeStart failed rc=$rc (port=$port)")
            fd.close()
            descriptor = null
            return false
        }
        zeptunUp = true
        Log.i(TAG, "zeptun up on socks 127.0.0.1:$port (protect callback installed)")
        EngineBridge.emit(upEvent(port))
        return true
    }

    private fun stopTunnel(reason: String) {
        if (zeptunUp) {
            try {
                Zeptun.nativeStop()
            } catch (t: Throwable) {
                // Teardown must never take the process down with it.
                Log.e(TAG, "zeptun nativeStop threw ($reason)", t)
            }
            zeptunUp = false
        }
        descriptor?.close()
        descriptor = null
        Log.i(TAG, "tunnel down ($reason)")
    }

    /// The user (or the system) revoked the VPN — never keep zeptun running
    /// on a dead descriptor.
    override fun onRevoke() {
        stopTunnel("revoked")
        EngineBridge.emit(
            mapOf("event" to "revoked", "session" to sessionId),
        )
        stopSelf()
        super.onRevoke()
    }

    override fun onDestroy() {
        stopTunnel("destroy")
        EngineBridge.emit(downEvent("destroy"))
        instance = null
        super.onDestroy()
    }

    private fun readCounter(index: Int): Long =
        if (zeptunUp) Zeptun.nativeCounter(index) else -1L

    private fun startForegroundCompat() {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    getString(R.string.vpn_channel_name),
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
        }
        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(getString(R.string.vpn_notification_title))
            .setContentText(getString(R.string.vpn_notification_text))
            .setOngoing(true)
            .setContentIntent(contentIntent)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            // specialUse + PROPERTY_SPECIAL_USE_FGS_SUBTYPE=vpn-tunnel in the
            // manifest (the only honest type for a VpnService FGS on 14+).
            ServiceCompat.startForeground(
                this,
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }
}
