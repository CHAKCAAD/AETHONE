package com.chakcaad.aethone.shield

import android.content.Context
import android.net.ConnectivityManager
import android.os.Build
import android.os.ParcelFileDescriptor
import android.os.Process
import android.system.Os
import android.util.Log
import java.io.File
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.atomic.AtomicBoolean

/// Family Shield — bypass (A): local SOCKS listeners. Phase-2 accept gate.
///
/// Loopback never crosses the TUN, so any app can dial 127.0.0.1:1819–1822
/// and use the tunnel unfiltered. The gate decides, for every ACCEPTED
/// loopback TCP connection, who the client is, and admits only AETHONE
/// itself. Fail-closed: unknown → reject.
///
/// Two independent client identifications (both are recorded):
///  1. own-process socket match: the accepted peer address is a socket
///     whose local end lives in THIS process (walk /proc/self/fd, keep the
///     `socket:[…]` links, getsockname/getpeername on a dup). This is how
///     the in-process clients (zeptun, Aether) are recognised.
///  2. ConnectivityManager.getConnectionOwnerUid (Android 10+, active VPN
///     app only), with (local = client, remote = listener) and the reverse
///     order. Platform finding (AOSP ConnectivityService): the result is
///     filtered to uids the VPN APPLIES to — AETHONE excludes itself from
///     its own VPN (loop prevention), so its own sockets come back as
///     INVALID_UID; other apps inside the VPN come back with their uid. It
///     can therefore name a FOREIGN client but never confirm our own.
///
/// Decision ([decide], pure): own-process match → allow; everything else
/// (foreign uid, INVALID_UID, lookup failure, Android < 10) → reject.
object LoopbackGuard {
    private const val TAG = "AethoneGuard"
    const val INVALID_UID = -1

    sealed class Verdict(val reason: String) {
        class Allow(reason: String) : Verdict(reason)
        class Reject(reason: String) : Verdict(reason)
        val allowed: Boolean get() = this is Allow
        override fun toString() = (if (allowed) "allow:" else "reject:") + reason
    }

    /// Evidence about one accepted connection.
    data class Evidence(
        /// null = the /proc/self/fd walk could not run
        val ownProcess: Boolean?,
        /// getConnectionOwnerUid(local = client, remote = listener)
        val uidClientView: Int?,
        /// getConnectionOwnerUid(local = listener, remote = client)
        val uidServerView: Int?,
        val ownUid: Int,
    )

    fun decide(e: Evidence): Verdict {
        if (e.ownProcess == true) return Verdict.Allow("own-process")
        val foreign = listOfNotNull(e.uidClientView, e.uidServerView)
            .firstOrNull { it != INVALID_UID && it >= 0 && it != e.ownUid }
        if (foreign != null) return Verdict.Reject("foreign-uid:$foreign")
        if (e.ownProcess == null) return Verdict.Reject("unknown:fd-walk-failed")
        // INVALID_UID / our own uid but NOT one of our sockets (another
        // process of ours, or an app excluded from the VPN): fail-closed
        return Verdict.Reject("unknown-uid:" + (e.uidClientView ?: "n/a") + "/" + (e.uidServerView ?: "n/a"))
    }

    // ---------------------------------------------------------------- Android

    /// True when [client] (the accepted socket's remote end) is a socket of
    /// this process connected to [listener]. Null when the walk failed.
    fun ownProcessSocket(client: InetSocketAddress, listener: InetSocketAddress): Boolean? {
        val dir = File("/proc/self/fd")
        val fds = dir.list() ?: return null
        var walked = false
        for (name in fds) {
            val fd = name.toIntOrNull() ?: continue
            val link = try { Os.readlink("/proc/self/fd/$fd") } catch (_: Exception) { continue }
            if (!link.startsWith("socket:")) continue
            walked = true
            var pfd: ParcelFileDescriptor? = null
            try {
                pfd = ParcelFileDescriptor.fromFd(fd)
                val local = Os.getsockname(pfd.fileDescriptor) as? InetSocketAddress ?: continue
                if (local.port != client.port || local.address != client.address) continue
                val peer = Os.getpeername(pfd.fileDescriptor) as? InetSocketAddress ?: continue
                if (peer.port == listener.port && peer.address == listener.address) return true
            } catch (_: Exception) {
                // not an inet socket / closed meanwhile
            } finally {
                try { pfd?.close() } catch (_: Exception) {}
            }
        }
        return if (walked) false else null
    }

    fun ownerUid(context: Context, local: InetSocketAddress, remote: InetSocketAddress): Int? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        return try {
            val cm = context.getSystemService(ConnectivityManager::class.java) ?: return null
            cm.getConnectionOwnerUid(6 /* IPPROTO_TCP */, local, remote)
        } catch (t: Throwable) {
            Log.w(TAG, "getConnectionOwnerUid failed: ${t.javaClass.simpleName}: ${t.message}")
            null
        }
    }

    fun evidence(context: Context, s: Socket): Evidence {
        val client = InetSocketAddress(s.inetAddress, s.port)
        val listener = InetSocketAddress(s.localAddress, s.localPort)
        return Evidence(
            ownProcess = try { ownProcessSocket(client, listener) } catch (_: Throwable) { null },
            uidClientView = ownerUid(context, client, listener),
            uidServerView = ownerUid(context, listener, client),
            ownUid = Process.myUid(),
        )
    }

    /// Whether this process can read /proc/net/tcp (it can not on Android
    /// 10+ for apps targeting 29+; recorded as evidence, never relied upon).
    fun procNetReadable(): Boolean = try { File("/proc/net/tcp").readText().isNotEmpty() } catch (_: Throwable) { false }

    /// Ports guarded by a live [GuardedListener] in this process (status:
    /// a guarded listener is not an exposure).
    val guardedPorts: MutableSet<Int> = java.util.concurrent.ConcurrentHashMap.newKeySet()

    /// A loopback TCP listener whose every accepted connection passes the
    /// gate before [handler] sees it. Rejected clients get an RST.
    class GuardedListener(
        private val context: Context,
        val port: Int,
        private val onVerdict: (Evidence, Verdict, InetSocketAddress) -> Unit,
        private val handler: (Socket) -> Unit,
    ) {
        private val running = AtomicBoolean(false)
        private var server: ServerSocket? = null

        fun start(): GuardedListener {
            val ss = ServerSocket()
            ss.reuseAddress = true
            ss.bind(InetSocketAddress(InetAddress.getByName("127.0.0.1"), port), 64)
            server = ss
            running.set(true)
            guardedPorts += port
            Thread({
                while (running.get()) {
                    val s = try { ss.accept() } catch (_: Exception) { break }
                    Thread({ gate(s) }, "aethone-guard-$port").apply { isDaemon = true }.start()
                }
            }, "aethone-guard-accept-$port").apply { isDaemon = true }.start()
            return this
        }

        private fun gate(s: Socket) {
            val e = try { evidence(context, s) } catch (_: Throwable) { Evidence(null, null, null, Process.myUid()) }
            val v = decide(e)
            try { onVerdict(e, v, InetSocketAddress(s.inetAddress, s.port)) } catch (_: Throwable) {}
            if (!v.allowed) {
                try { s.setSoLinger(true, 0) } catch (_: Exception) {}
                try { s.close() } catch (_: Exception) {}
                return
            }
            try { handler(s) } catch (_: Throwable) {} finally { try { s.close() } catch (_: Exception) {} }
        }

        fun stop() {
            running.set(false)
            guardedPorts -= port
            try { server?.close() } catch (_: Exception) {}
        }
    }
}
