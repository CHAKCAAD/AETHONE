package com.chakcaad.aethone

import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.os.Build
import android.os.Process
import android.system.OsConstants
import android.util.Log
import java.net.InetAddress
import java.net.InetSocketAddress
import java.util.concurrent.Callable
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

/// Stage 2 per-app routing (PoC) — the flow-owner resolver.
///
/// Zeptun calls [resolve] on its engine thread at the first packet of every
/// new flow, passing the ORIGINAL connection tuple exactly as Android's
/// connection-owner API needs it. The resolver answers with the packed
/// decision `(routeNumber << 2) | action`; route 0 (the answer for every
/// unknown/unattributable flow) is the DEFAULT route — the active engine
/// mode — never another app's assignment (fail-open only to default).
///
/// Lifecycle contract (task §3.2):
///  * API < 29: `getConnectionOwnerUid` does not exist — every flow gets the
///    default route and the limitation is counted, never queried.
///  * The framework query runs on a SINGLE bounded executor thread with a
///    strict timeout ([QUERY_TIMEOUT_MS]). On timeout the flow gets the
///    default route and the late result is DROPPED — it can never corrupt a
///    newer flow: each query is stateless, and this method's return value is
///    the only writer of the decision. A timed-out query may still run to
///    completion on the executor thread; its future is simply never read.
///  * The zeptun engine thread is never blocked beyond the timeout.
///  * Shared UIDs (multiple packages behind one uid) resolve
///    deterministically: only when EVERY package of the uid carries the SAME
///    assignment is that route used; otherwise the default route (never an
///    arbitrary pick).
///  * [close] shuts the executor down; the service calls it on tunnel
///    teardown so no callback can outlive the VPN.
///
/// Metrics (task §4) are plain counters + a cumulative latency measure,
/// dumped through [stats]. No package names in the metrics themselves
/// (privacy rule); the per-package attribution line is emitted at most once
/// per package, bounded to 64, and only while assignments exist (an
/// adb-driven PoC start — never a production path).
class PerAppRouteResolver(
    context: Context,
    routeCount: Int,
) {
    companion object {
        private const val TAG = "AethonePoC"
        private const val QUERY_TIMEOUT_MS = 50L

        /// ZeptunStats tail indices (see dev.zeptun.Zeptun docs).
        const val STATS_ROUTE_ASKED = 38
        const val STATS_ROUTE_ASSIGNED = 39
        const val STATS_ROUTE_FALLBACK = 40
        const val STATS_ROUTE_DIRECT_FAKE = 41
    }

    /// package name -> route number (1..N; zeptun route 0 = default and is
    /// never stored). Replaced atomically by [swapAssignments] alongside the
    /// native table update.
    @Volatile
    private var assignments: Map<String, Int> = emptyMap()

    @Volatile
    private var routeCount: Int = routeCount

    private val connectivity: ConnectivityManager? =
        context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager

    private val packageManager: PackageManager = context.packageManager

    /// Single-threaded on purpose: the framework query is serialized, each
    /// caller holds its future for at most QUERY_TIMEOUT_MS, and no
    /// unbounded thread creation is possible.
    private val executor: ExecutorService = Executors.newSingleThreadExecutor { r ->
        Thread(r, "aethone-route-resolver").apply { isDaemon = true }
    }

    private val calls = AtomicLong()
    private val apiSkips = AtomicLong()
    private val invalidUids = AtomicLong()
    private val timeouts = AtomicLong()
    private val errors = AtomicLong()
    private val unattributed = AtomicLong()
    private val sharedUidMixed = AtomicLong()
    private val assigned = AtomicLong()
    private val defaultRoute = AtomicLong()
    private val totalLatencyNs = AtomicLong()
    private val maxLatencyNs = AtomicLong()
    private val loggedPackages = HashSet<String>()

    /** Swap the package -> route map (called together with the native table update). */
    fun swapAssignments(map: Map<String, Int>, newRouteCount: Int) {
        assignments = map
        routeCount = newRouteCount
    }

    fun assignmentsSnapshot(): Map<String, Int> = assignments

    fun routeCountSnapshot(): Int = routeCount

    /**
     * The flow-owner callback (invoked from JNI on the zeptun engine thread;
     * MUST return within the bounded timeout). `source`/`destination` are
     * 16-byte addresses (v4 in the first 4 bytes — exactly what zeptun's
     * ZeptunFlow carries); `family` is 4 or 6; `protocol` 6 (TCP) or 17
     * (UDP). Orientation: source = the app's (local) endpoint, destination =
     * the remote — never reversed.
     */
    fun resolve(
        protocol: Int,
        family: Int,
        source: ByteArray,
        sourcePort: Int,
        destination: ByteArray,
        destinationPort: Int,
    ): Int {
        calls.incrementAndGet()
        val map = assignments
        if (map.isEmpty()) return 0 // no assignments -> default, no query at all
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            apiSkips.incrementAndGet()
            return 0
        }
        val cm = connectivity ?: run {
            errors.incrementAndGet()
            return 0
        }
        val started = System.nanoTime()
        try {
            val addrLen = if (family == 6) 16 else 4
            val local = InetSocketAddress(InetAddress.getByAddress(source.copyOf(addrLen)), sourcePort)
            val remote = InetSocketAddress(InetAddress.getByAddress(destination.copyOf(addrLen)), destinationPort)
            val proto = when (protocol) {
                6 -> OsConstants.IPPROTO_TCP
                17 -> OsConstants.IPPROTO_UDP
                else -> return 0
            }
            val future: Future<Int> = executor.submit(
                Callable { cm.getConnectionOwnerUid(proto, local, remote) },
            )
            val uid = try {
                future.get(QUERY_TIMEOUT_MS, TimeUnit.MILLISECONDS)
            } catch (e: java.util.concurrent.TimeoutException) {
                timeouts.incrementAndGet()
                return 0 // default route; the late result is dropped, never applied
            } catch (e: java.util.concurrent.ExecutionException) {
                errors.incrementAndGet()
                return 0
            }
            val latency = System.nanoTime() - started
            totalLatencyNs.addAndGet(latency)
            maxLatencyNs.accumulateAndGet(latency) { a, b -> a.coerceAtLeast(b) }
            if (uid == Process.INVALID_UID) {
                invalidUids.incrementAndGet()
                return 0
            }
            val packages = packageManager.getPackagesForUid(uid) ?: run {
                unattributed.incrementAndGet()
                return 0
            }
            if (packages.isEmpty()) {
                unattributed.incrementAndGet()
                return 0
            }
            // Deterministic shared-UID policy: every package of the uid must
            // carry the SAME assigned route, else default (never arbitrary).
            var agreed = 0
            for (pkg in packages) {
                val r = map[pkg] ?: 0
                if (r !in 1..routeCount) {
                    if (packages.size > 1) sharedUidMixed.incrementAndGet()
                    defaultRoute.incrementAndGet()
                    return 0
                }
                if (agreed == 0) {
                    agreed = r
                } else if (agreed != r) {
                    sharedUidMixed.incrementAndGet()
                    defaultRoute.incrementAndGet()
                    return 0
                }
            }
            if (agreed == 0) {
                defaultRoute.incrementAndGet()
                return 0
            }
            assigned.incrementAndGet()
            // Bounded per-package logging (adb-driven PoC starts only): one
            // line per NEW package name, 64 total, names never printed.
            synchronized(loggedPackages) {
                for (name in packages) {
                    if (loggedPackages.size >= 64) break
                    if (loggedPackages.add(name)) {
                        Log.i(TAG, "poc attribution: package logged, route=$agreed uid=$uid")
                    }
                }
            }
            return agreed shl 2 // action .proxy
        } catch (t: Throwable) {
            errors.incrementAndGet()
            return 0
        }
    }

    /** One-line metrics dump (logcat, tag AethonePoC). */
    fun stats(): String {
        val n = calls.get().coerceAtLeast(1)
        val avgMs = totalLatencyNs.get() / n / 1_000_000.0
        return "resolver calls=${calls.get()} assigned=${assigned.get()} default=${defaultRoute.get()} " +
            "invalidUid=${invalidUids.get()} unattributed=${unattributed.get()} timeouts=${timeouts.get()} " +
            "errors=${errors.get()} apiSkip=${apiSkips.get()} sharedUidMixed=${sharedUidMixed.get()} " +
            "avgLatencyMs=%.3f maxLatencyMs=%.3f".format(avgMs, maxLatencyNs.get() / 1_000_000.0)
    }

    fun close() {
        executor.shutdownNow()
    }
}
