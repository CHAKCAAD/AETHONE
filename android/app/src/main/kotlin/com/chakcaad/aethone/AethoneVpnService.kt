package com.chakcaad.aethone

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import java.io.File

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

        /// v4.31 — the selected mode carries UDP or not: every tor/psiphon
        /// family mode reaches the internet over TCP only (transport_modes
        /// `tcpOnly`; the core's socks listener accepts the UDP ASSOCIATE
        /// and then silently DROPS every non-DNS datagram, socks.rs
        /// “this listener reaches the internet over tcp only”). With UDP
        /// left enabled in zeptun, the device's QUIC/UDP flows vanish into
        /// that black hole — apps hang retransmitting instead of falling
        /// back to TCP (owner round 7: «تونل در لوکیشن های سایفون نمیتونه
        /// خوب دیتا رو رد کنه … به مقدار دیتا رد و بدل میشه و بعد دویاره
        /// دیتایی رد نمیشه» — proxy on the same port worked). With
        /// `handler.socks5.udp = "disabled"` zeptun REFUSES the flow at
        /// open (handler.zig udpOpen) and answers ICMP port-unreachable
        /// (stack/udp.zig → icmp.sendUnreachable) — the honest
        /// "this network has no UDP" every app falls back from.
        const val EXTRA_TCP_ONLY = "tcpOnly"

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

        /// v4.26 — the tunnel-session generation bookkeeping. [noteStart]
        /// records the session the Dart side is STARTING; [requestStop]
        /// records the stop. A `startForegroundService` delivery can land
        /// AFTER a `stopService` was already processed (OEM scheduler
        /// orderings) — that straggler start used to establish a TUN
        /// nobody owned while the app showed «disconnected» (owner round 4:
        /// «فقط اتصال هسته اول قطع میشه و همچنان تونل برقراره»). A start
        /// whose session is ≤ the stop generation now tears itself down.
        @Volatile
        private var liveSession = 0

        @Volatile
        private var stopGeneration = 0

        /// MainActivity.startVpn calls this BEFORE startForegroundService.
        fun noteStart(session: Int) {
            liveSession = session
        }

        /// v4.26 — the hardened stop path (MainActivity.stopVpn):
        ///  1. bump the stop generation — any start still in flight for a
        ///     session ≤ it self-terminates in onStartCommand;
        ///  2. tell the LIVE instance (if any) to tear zeptun + the TUN
        ///     down right now — `stopService()` alone only asks the system
        ///     to schedule onDestroy;
        ///  3. stopService as the belt-and-braces lifecycle call.
        fun requestStop(context: Context) {
            if (liveSession > stopGeneration) stopGeneration = liveSession
            instance?.stopFromUser()
            try {
                context.stopService(
                    Intent(context, AethoneVpnService::class.java),
                )
            } catch (t: Throwable) {
                Log.w(TAG, "stopService threw", t)
            }
        }

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

    /// v4.31 — the udp mode zeptun is CURRENTLY serving; a mode switch
    /// between a UDP-carrying leg and a TCP-only one on the SAME port
    /// (e.g. MASQUE 1819 → PSIPHON ONLY 1819) must restart zeptun, exactly
    /// like a port change — the blackhole/ICMP behaviour differs.
    private var socksTcpOnly: Boolean = false

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
        val tcpOnly = intent?.getBooleanExtra(EXTRA_TCP_ONLY, false) ?: false
        // v4.26 — the straggler gate: this start was superseded by a stop
        // (a `stopVpn` processed while the start delivery was still in
        // flight — the lost-cancel window's platform half). Establishing
        // the TUN here would orphan it: nobody is waiting for `up`.
        if (sessionId != 0 && sessionId <= stopGeneration) {
            Log.i(
                TAG,
                "stale tunnel start (session $sessionId ≤ stop $stopGeneration) — refusing",
            )
            stopTunnel("stale-start")
            stopSelf()
            return START_NOT_STICKY
        }
        // v4.28 — the zeptun PRE-FLIGHT (owner round 5: «tunnel start
        // failed start-threw:NoClassDefFoundError»). NoClassDefFoundError is
        // the RETRY face of an earlier, swallowed class-init failure: the
        // first System.loadLibrary("zeptun-jni") threw (an
        // UnsatisfiedLinkError — a missing .so, a missing symbol, a rejected
        // alignment…), the object's <clinit> stays failed for the REST of
        // the process, and every later touch degrades to a bare
        // NoClassDefFoundError that names NOTHING. The old
        // start-threw:<simpleName> surfaced exactly that anonymous retry
        // face. The pre-flight forces the load HERE — before any TUN
        // exists — and reports the FULL cause chain plus the on-disk
        // nativeLibraryDir listing, so the next device report names the
        // real missing piece instead of a bare retry symptom.
        try {
            Zeptun.nativeVersion()
        } catch (t: Throwable) {
            val dir = applicationInfo.nativeLibraryDir
            Log.e(
                TAG,
                "zeptun bridge load failed (nativeLibraryDir=$dir: " +
                    "${File(dir).list()?.joinToString(prefix = "[", separator = ", ", postfix = "]")})",
                t,
            )
            EngineBridge.emit(downEvent("zeptun-load-failed:${describeChain(t)}"))
            stopSelf()
            return START_NOT_STICKY
        }
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
            if (!startTunnel(port, tcpOnly)) {
                EngineBridge.emit(downEvent("establish-failed"))
                stopSelf()
                return START_NOT_STICKY
            }
        } catch (t: Throwable) {
            Log.e(TAG, "tunnel start threw", t)
            EngineBridge.emit(downEvent("start-threw:${describeChain(t)}"))
            stopTunnel("start-threw")
            stopSelf()
            return START_NOT_STICKY
        }
        return START_NOT_STICKY
    }

    /// v4.28 — the full throwable chain for the emitted reason:
    /// `NoClassDefFoundError: … caused by UnsatisfiedLinkError: dlopen
    /// failed: …`. The bare simpleName hid everything the diagnosis needs;
    /// the chain is bounded so a UI reason line never becomes a dump.
    private fun describeChain(t: Throwable): String {
        val sb = StringBuilder(t.javaClass.simpleName)
        t.message?.takeIf { it.isNotBlank() }?.let { sb.append(": ").append(it) }
        var cause = t.cause
        var budget = 300
        while (cause != null && budget > 0) {
            val part =
                " caused by ${cause.javaClass.simpleName}: ${cause.message ?: ""}"
            sb.append(part)
            budget -= part.length
            cause = cause.cause
        }
        return sb.toString().take(500)
    }

    /// v4.26 — the synchronous user-stop path (companion [requestStop]):
    /// zeptun + TUN down immediately, the foreground notification removed,
    /// the service stopped. `stopService()` remains as the lifecycle call;
    /// onDestroy's own stopTunnel is idempotent.
    fun stopFromUser() {
        stopTunnel("user-stop")
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    /// v4.21 — event maps stamped with THIS instance's session id.
    private fun upEvent(port: Int): Map<String, Any?> =
        mapOf("event" to "up", "port" to port, "session" to sessionId)

    private fun downEvent(reason: String): Map<String, Any?> =
        mapOf("event" to "down", "reason" to reason, "session" to sessionId)

    private fun startTunnel(port: Int, tcpOnly: Boolean): Boolean {
        if (zeptunUp) {
            // v4.20: a mode switch (e.g. 1819 → 1820) between connects used
            // to keep serving the OLD port — zeptun would relay into a
            // listener nothing serves anymore. A different target is a
            // full restart; the same target is the plain "already serving"
            // re-entry (activity restart re-invoked the service).
            // v4.31: the UDP mode counts as part of the target — the same
            // port with a different tcpOnly answers flows differently
            // (ICMP-unreachable vs relayed UDP ASSOCIATE).
            if (port != socksPort || tcpOnly != socksTcpOnly) {
                Log.i(
                    TAG,
                    "socks target changed $socksPort/$socksTcpOnly -> $port/$tcpOnly; restarting zeptun",
                )
                stopTunnel("port-change")
            } else {
                EngineBridge.emit(upEvent(port))
                return true
            }
        }
        // v4.29 — the cold-start adoption (run #53 on the apk-smoke gate:
        // «Builder.establish() returned null» DESPITE the granted
        // ACTIVATE_VPN appop). establish()'s FIRST gate is system-side
        // in-memory state, not the appop: after a system_server boot (or
        // any start that skipped the Dart walk's prepareVpn leg) Vpn's
        // mOwnerUID is still the legacy-VPN uid and establish() honestly
        // returns null — AOSP Vpn.java: «if (Binder.getCallingUid() !=
        // mOwnerUID) return null;» BEFORE the appop check. One prepare()
        // call fixes the state ITSELF: with consent already granted,
        // VpnService.prepare() adopts our package system-side
        // (Vpn.prepare → prepareInternal → mOwnerUID = our uid) and
        // returns null — no dialog. It returns an INTENT only when consent
        // is genuinely missing (establish would refuse anyway); the Dart
        // walk's own prepareVpn leg surfaces the dialog there. On the
        // normal connected path this call is a pure no-op (already the
        // current prepared package → prepare returns true → null intent).
        if (VpnService.prepare(this) != null) {
            Log.e(TAG, "consent missing (prepare returned an intent) — refusing to establish")
            return false
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
        // of truth: the zeptun config keys at the frozen pin). v4.31 — the
        // `udp = "disabled"` line for TCP-only modes: zeptun then refuses
        // every UDP flow at open and answers the device with ICMP
        // port-unreachable (src/stack/udp.zig → icmp.sendUnreachable), so
        // QUIC-happy apps fall back to TCP immediately instead of
        // blackholing into the core's drop-everything UDP relay. The
        // fake-IP DNS keeps working — zeptun answers it locally before
        // any flow reaches the handler (src/stack/dns.zig).
        val toml = """
            preset = "mobile"

            [handler]
            kind = "socks5"

            [handler.socks5]
            server = "127.0.0.1:$port"
            ${if (tcpOnly) "udp = \"disabled\"" else ""}

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
        socksTcpOnly = tcpOnly
        Log.i(
            TAG,
            "zeptun up on socks 127.0.0.1:$port udp=${if (tcpOnly) "disabled" else "enabled"} " +
                "(protect callback installed)",
        )
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
