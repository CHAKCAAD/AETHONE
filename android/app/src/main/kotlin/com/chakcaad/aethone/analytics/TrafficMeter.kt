package com.chakcaad.aethone.analytics

import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.os.Build
import android.os.Process
import android.util.Log
import org.json.JSONObject
import java.net.InetAddress
import java.net.InetSocketAddress
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit

/// Traffic Analytics — the Android half of the native traffic meter
/// (docs/traffic-analytics.md). Fed by two zeptun JNI callbacks on engine
/// threads, never by its own capture:
///
///  * [onFlowOpen] — from HybridRouter.route (dev.zeptun.Zeptun.route), once
///    per new flow, BEFORE the dial: the app (ConnectivityManager
///    .getConnectionOwnerUid — the same lookup app rules use), the fake-IP
///    domain, and the route zeptun was told to use.
///  * [onMeter] — from dev.zeptun.Zeptun.meter: payload byte DELTAS per TCP
///    flow, measured where zeptun writes to / reads from the flow's SOCKS5
///    stream, with the route the flow was REALLY dialled on.
///
/// Engine threads only touch lock-free maps and a small synchronized
/// accumulator; a single background thread samples the engine's global
/// counters every second (live speed, unmeasured remainder) and writes one
/// batched transaction every [FLUSH_S] seconds. Nothing per packet, nothing
/// per flow ever reaches the database.
object TrafficMeter {
    private const val TAG = "AethoneMeter"
    private const val PROTO_TCP = 6
    private const val FLUSH_S = 15L
    private const val LIVE_POINTS = 60
    private const val HIST_S = 30
    private const val LAG_MS = 10_000L
    /// Flows whose last report never came (engine stopped hard) are dropped
    /// from the open-flow table after this long without a report.
    private const val STALE_FLOW_MS = 30 * 60_000L

    private val prefsName = "aethone_traffic_analytics"

    @Volatile private var appContext: Context? = null
    @Volatile var enabled: Boolean = true
        private set
    @Volatile var recordDomains: Boolean = true
        private set
    @Volatile var retentionDays: Int = 90
        private set

    // --- the running tunnel ------------------------------------------------
    @Volatile private var running = false
    @Volatile private var profile: String = ""
    /// Route index (0 = default) → route id; single-tunnel = [profile].
    @Volatile private var routeIds: List<String> = emptyList()
    @Volatile private var sessionRow: Long = 0
    @Volatile private var startedAt: Long = 0
    private var counterReader: ((Int) -> Long)? = null

    private class FlowInfo(val app: String, val domain: String?, val opened: Long) {
        @Volatile var lastSeen: Long = opened
        /// Whether this flow was already counted in `flows` (first report).
        var counted = false
    }
    private val flows = ConcurrentHashMap<String, FlowInfo>()

    // --- the accumulator (guarded by `lock`) --------------------------------
    private val lock = Any()
    private var usage = HashMap<TrafficStore.UsageKey, TrafficStore.Usage>()
    private var domains = HashMap<TrafficStore.DomainKey, TrafficStore.Usage>()
    private var rates = HashMap<TrafficStore.RateKey, TrafficStore.Rate>()
    /// Bytes per route / app since the last 2-second window.
    private var winRoute = HashMap<String, LongArray>()
    private var winApp = HashMap<String, LongArray>()
    private var winTotal = LongArray(2)
    private var meteredUp = 0L
    private var meteredDown = 0L
    private var sessUp = 0L
    private var sessDown = 0L

    // --- live (sampler thread only, read under liveLock) ----------------------
    private val liveLock = Any()
    private val liveDown = ArrayDeque<Long>()
    private val liveUp = ArrayDeque<Long>()
    private var lastRx = -1L
    private var lastTx = -1L
    /// (time, upstream rx, upstream tx) — the engine's absolute counters,
    /// one per second, last [HIST_S] seconds.
    private val globalHist = ArrayDeque<LongArray>()
    private var bookedUp = 0L
    private var bookedDown = 0L
    private var liveRoutes: Map<String, LongArray> = emptyMap()
    private var liveApps: Map<String, LongArray> = emptyMap()

    private var exec: ScheduledExecutorService? = null
    private var ticks = 0L

    fun init(context: Context) {
        val ctx = context.applicationContext
        appContext = ctx
        val p = ctx.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
        enabled = p.getBoolean("enabled", true)
        recordDomains = p.getBoolean("domains", true)
        retentionDays = p.getInt("retentionDays", 90)
    }

    fun configure(context: Context, enabled: Boolean?, domains: Boolean?, retention: Int?) {
        init(context)
        val e = context.applicationContext.getSharedPreferences(prefsName, Context.MODE_PRIVATE).edit()
        enabled?.let { this.enabled = it; e.putBoolean("enabled", it) }
        domains?.let { recordDomains = it; e.putBoolean("domains", it) }
        retention?.let { retentionDays = it.coerceIn(0, 3650); e.putInt("retentionDays", retentionDays) }
        e.apply()
    }

    fun config(): Map<String, Any?> = mapOf(
        "enabled" to enabled,
        "domains" to recordDomains,
        "retentionDays" to retentionDays,
        "appAttribution" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q),
    )

    // ------------------------------------------------------- lifecycle --

    /// The tunnel is about to start: [routes] index 0 is the default route.
    fun begin(context: Context, profileId: String, routes: List<String>, readCounter: (Int) -> Long) {
        init(context)
        val prev = exec
        end()
        try { prev?.awaitTermination(3, TimeUnit.SECONDS) } catch (_: InterruptedException) {}
        if (!enabled) return
        profile = profileId.ifEmpty { "unknown" }
        routeIds = routes.ifEmpty { listOf(profile) }
        counterReader = readCounter
        flows.clear()
        synchronized(lock) {
            usage.clear(); domains.clear(); rates.clear(); winRoute.clear(); winApp.clear()
            winTotal = LongArray(2); meteredUp = 0; meteredDown = 0; sessUp = 0; sessDown = 0
        }
        synchronized(liveLock) {
            liveDown.clear(); liveUp.clear(); lastRx = -1; lastTx = -1
            globalHist.clear(); bookedUp = 0; bookedDown = 0
            liveRoutes = emptyMap(); liveApps = emptyMap()
        }
        startedAt = System.currentTimeMillis()
        val store = TrafficStore.get(context)
        exec = Executors.newSingleThreadScheduledExecutor { r ->
            Thread(r, "aethone-meter").apply { isDaemon = true; priority = Thread.MIN_PRIORITY }
        }.also { ex ->
            ex.execute {
                runCatching {
                    store.closeOrphans(startedAt)
                    store.compact(startedAt, retentionDays)
                    sessionRow = store.openSession(profile, startedAt)
                }.onFailure { Log.w(TAG, "store open failed", it) }
            }
            ex.scheduleWithFixedDelay({ tick(store) }, 1, 1, TimeUnit.SECONDS)
        }
        running = true
        Log.i(TAG, "metering on: profile=$profile routes=$routeIds")
    }

    /// The tunnel stopped: call AFTER zeptun's nativeStop returned (its
    /// shutdown delivers the open flows' last reports through [onMeter]).
    /// Last flush + session end. Idempotent.
    fun end() {
        val ex = exec ?: return
        exec = null
        running = false
        val ctx = appContext
        ex.execute {
            if (ctx != null) runCatching {
                val store = TrafficStore.get(ctx)
                flush(store, final = true)
                store.closeSession(sessionRow, System.currentTimeMillis())
            }.onFailure { Log.w(TAG, "final flush failed", it) }
            sessionRow = 0
        }
        ex.shutdown()
        counterReader = null
        flows.clear()
        synchronized(liveLock) { liveRoutes = emptyMap(); liveApps = emptyMap() }
    }

    val active: Boolean get() = running && enabled

    // ------------------------------------------------- engine callbacks --

    private fun key(proto: Int, src: ByteArray, sport: Int, dst: ByteArray, dport: Int): String {
        val sb = StringBuilder(48).append(proto).append('|')
        for (b in src) sb.append(b.toInt() and 0xff).append('.')
        sb.append(':').append(sport).append('>')
        for (b in dst) sb.append(b.toInt() and 0xff).append('.')
        return sb.append(':').append(dport).toString()
    }

    /// From HybridRouter.route on the engine thread. [uid] is the owner the
    /// router already resolved (or null when it did not look it up).
    fun onFlowOpen(proto: Int, src: ByteArray, sport: Int, dst: ByteArray, dport: Int, name: String?, uid: Int?) {
        if (!active || proto != PROTO_TCP) return
        val owner = uid ?: ownerUid(proto, src, sport, dst, dport)
        val app = appKey(owner)
        val now = System.currentTimeMillis()
        flows[key(proto, src, sport, dst, dport)] = FlowInfo(app, name?.lowercase()?.trimEnd('.'), now)
    }

    /// From dev.zeptun.Zeptun.meter on the engine thread.
    fun onMeter(proto: Int, src: ByteArray, sport: Int, dst: ByteArray, dport: Int, route: Int, up: Long, down: Long, closed: Boolean) {
        if (!active) return
        val k = key(proto, src, sport, dst, dport)
        val info = if (closed) flows.remove(k) else flows[k]
        if (up <= 0 && down <= 0) return
        val now = System.currentTimeMillis()
        info?.lastSeen = now
        val app = info?.app ?: TrafficStore.APP_UNATTRIBUTED
        val ids = routeIds
        val routeId = ids.getOrNull(route) ?: "route$route"
        val hour = now / TrafficStore.HOUR_MS
        synchronized(lock) {
            val u = usage.getOrPut(TrafficStore.UsageKey(hour, profile, routeId, app)) { TrafficStore.Usage() }
            u.up += up; u.down += down
            // one flow counted once, on its first report with bytes
            if (info != null && !info.counted) { u.flows += 1; info.counted = true }
            else if (info == null && closed) u.flows += 1
            val dom = info?.domain
            if (dom != null && recordDomains) {
                val day = dayStart(now)
                val d = domains.getOrPut(TrafficStore.DomainKey(day, profile, routeId, app, dom)) { TrafficStore.Usage() }
                d.up += up; d.down += down
            }
            winRoute.getOrPut(routeId) { LongArray(2) }.let { it[0] += up; it[1] += down }
            winApp.getOrPut(app) { LongArray(2) }.let { it[0] += up; it[1] += down }
            winTotal[0] += up; winTotal[1] += down
            meteredUp += up; meteredDown += down
            sessUp += up; sessDown += down
        }
    }

    // ---------------------------------------------------- the sampler --

    private fun tick(store: TrafficStore) {
        try {
            ticks++
            sampleCounters()
            if (ticks % 2 == 0L) closeWindow()
            if (ticks % FLUSH_S == 0L) {
                flush(store)
                val now = System.currentTimeMillis()
                flows.entries.removeIf { now - it.value.lastSeen > STALE_FLOW_MS }
            }
        } catch (t: Throwable) {
            Log.w(TAG, "meter tick failed", t)
        }
    }

    /// Live speed from the engine's own global counters (index 28/29 =
    /// upstream_rx/tx_bytes: every byte zeptun moved on a SOCKS5 stream, TCP
    /// and UDP). Also kept as history for the unmeasured remainder.
    private fun sampleCounters() {
        val read = counterReader ?: return
        val rx = read(STATS_UPSTREAM_RX)
        val tx = read(STATS_UPSTREAM_TX)
        if (rx < 0 || tx < 0) return
        synchronized(liveLock) {
            if (lastRx >= 0) {
                liveDown.addLast((rx - lastRx).coerceAtLeast(0))
                liveUp.addLast((tx - lastTx).coerceAtLeast(0))
                while (liveDown.size > LIVE_POINTS) liveDown.removeFirst()
                while (liveUp.size > LIVE_POINTS) liveUp.removeFirst()
            }
            lastRx = rx; lastTx = tx
            globalHist.addLast(longArrayOf(System.currentTimeMillis(), rx, tx))
            while (globalHist.size > HIST_S) globalHist.removeFirst()
        }
    }

    /// The unmeasured remainder to book now: bytes the engine's global
    /// counter had moved [LAG_MS] ago that no flow report has carried since.
    /// Per-flow reports lag the counter by at most ~2 meter intervals (live
    /// flows every 2 s, idle flows by the sweep), so comparing the counter
    /// as of [LAG_MS] ago with the reports as of now never books a byte that
    /// a flow report is still about to bring. Booked amounts only grow.
    private fun takeUnmeasured(metUp: Long, metDown: Long, final: Boolean): Pair<Long, Long> = synchronized(liveLock) {
        // the session's last flush (engine stopped, every report is in)
        // compares against the newest sample.
        val cut = if (final) Long.MAX_VALUE else System.currentTimeMillis() - LAG_MS
        val ref = globalHist.lastOrNull { it[0] <= cut } ?: return@synchronized 0L to 0L
        val targetDown = (ref[1] - metDown).coerceAtLeast(0)
        val targetUp = (ref[2] - metUp).coerceAtLeast(0)
        val dd = (targetDown - bookedDown).coerceAtLeast(0)
        val du = (targetUp - bookedUp).coerceAtLeast(0)
        bookedDown += dd; bookedUp += du
        du to dd
    }

    private fun closeWindow() {
        val now = System.currentTimeMillis()
        val hour = now / TrafficStore.HOUR_MS
        synchronized(lock) {
            fun rate(kind: String, k: String, v: LongArray) {
                if (v[0] == 0L && v[1] == 0L) return
                val r = rates.getOrPut(TrafficStore.RateKey(hour, profile, kind, k)) { TrafficStore.Rate() }
                r.peakUp = maxOf(r.peakUp, v[0] / 2)
                r.peakDown = maxOf(r.peakDown, v[1] / 2)
                r.activeS += 2
            }
            rate("total", "", winTotal)
            for ((k, v) in winRoute) rate("route", k, v)
            for ((k, v) in winApp) rate("app", k, v)
            synchronized(liveLock) {
                liveRoutes = winRoute.mapValues { it.value.copyOf() }
                liveApps = winApp.mapValues { it.value.copyOf() }
            }
            winRoute = HashMap(); winApp = HashMap(); winTotal = LongArray(2)
        }
    }

    private fun flush(store: TrafficStore, final: Boolean = false) {
        val u: HashMap<TrafficStore.UsageKey, TrafficStore.Usage>
        val d: HashMap<TrafficStore.DomainKey, TrafficStore.Usage>
        val r: HashMap<TrafficStore.RateKey, TrafficStore.Rate>
        val su: Long
        val sd: Long
        synchronized(lock) {
            u = usage; d = domains; r = rates; su = sessUp; sd = sessDown
            usage = HashMap(); domains = HashMap(); rates = HashMap(); sessUp = 0; sessDown = 0
        }
        val (mu, md) = synchronized(lock) { meteredUp to meteredDown }
        val (uu, ud) = takeUnmeasured(mu, md, final)
        if (uu > 0 || ud > 0) {
            val k = TrafficStore.UsageKey(System.currentTimeMillis() / TrafficStore.HOUR_MS, profile, "", TrafficStore.APP_UNMEASURED)
            val x = u.getOrPut(k) { TrafficStore.Usage() }
            x.up += uu; x.down += ud
        }
        store.apply(u, r, d, sessionRow, su, sd, uu + ud)
    }

    // -------------------------------------------------------- live read --

    /// The Live Traffic contract: last [LIVE_POINTS] one-second samples of
    /// the engine counters, the last 2-second window per route / app.
    fun live(): Map<String, Any?> {
        if (!active) return mapOf("running" to false, "enabled" to enabled)
        synchronized(liveLock) {
            return mapOf(
                "running" to true,
                "enabled" to enabled,
                "profile" to profile,
                "routes" to routeIds,
                "startedAt" to startedAt,
                "down" to liveDown.toList(),
                "up" to liveUp.toList(),
                "routeRates" to liveRoutes.mapValues { listOf(it.value[0] / 2, it.value[1] / 2) },
                "appRates" to liveApps.mapValues { listOf(it.value[0] / 2, it.value[1] / 2) },
                "openFlows" to flows.size,
            )
        }
    }

    // ------------------------------------------------------ attribution --

    private fun ownerUid(proto: Int, src: ByteArray, sport: Int, dst: ByteArray, dport: Int): Int {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return Process.INVALID_UID
        val ctx = appContext ?: return Process.INVALID_UID
        val cm = ctx.getSystemService(ConnectivityManager::class.java) ?: return Process.INVALID_UID
        return try {
            cm.getConnectionOwnerUid(
                proto,
                InetSocketAddress(InetAddress.getByAddress(src), sport),
                InetSocketAddress(InetAddress.getByAddress(dst), dport),
            )
        } catch (_: Exception) {
            Process.INVALID_UID
        }
    }

    private val uidApps = ConcurrentHashMap<Int, String>()

    /// uid → the app key: the (first) package of that uid, "uid:N" for a uid
    /// without one, [TrafficStore.APP_UNATTRIBUTED] when unknown.
    fun appKey(uid: Int): String {
        if (uid == Process.INVALID_UID || uid < 0) return TrafficStore.APP_UNATTRIBUTED
        uidApps[uid]?.let { return it }
        val pm: PackageManager? = appContext?.packageManager
        val pkgs = try { pm?.getPackagesForUid(uid) } catch (_: Exception) { null }
        val k = pkgs?.minOrNull() ?: "uid:${uid % 100_000}"
        uidApps[uid] = k
        return k
    }

    private fun dayStart(now: Long): Long {
        val off = java.util.TimeZone.getDefault().getOffset(now).toLong()
        return ((now + off) / TrafficStore.DAY_MS) * TrafficStore.DAY_MS - off
    }

    /// zeptun stats.zig Counter order: upstream_rx_bytes = 28, upstream_tx_bytes = 29.
    const val STATS_UPSTREAM_RX = 28
    const val STATS_UPSTREAM_TX = 29

    // ------------------------------------------------- flutter queries --

    fun query(context: Context, json: String): String {
        val q = JSONObject(json)
        val store = TrafficStore.get(context)
        flushNowBlocking(store)
        val out = store.query(q)
        q.optJSONObject("compareWith")?.let { prev ->
            out.put("compare", store.query(prev.put("profile", q.optString("profile"))))
            out.put("appChanges", store.appChanges(q, prev))
        }
        if (q.optBoolean("sessions")) out.put("sessions", store.sessions())
        return out.toString()
    }

    /// Queries read what is on disk: the accumulator is flushed first, on
    /// the meter thread (no write races), when a tunnel is running.
    private fun flushNowBlocking(store: TrafficStore) {
        val ex = exec ?: return
        try {
            ex.submit { flush(store) }.get(3, TimeUnit.SECONDS)
        } catch (_: Exception) {}
    }

    fun clear(context: Context) {
        val store = TrafficStore.get(context)
        val ex = exec
        if (ex != null) {
            try { ex.submit { synchronized(lock) { usage.clear(); domains.clear(); rates.clear() }; store.clearAll() }.get(5, TimeUnit.SECONDS) } catch (_: Exception) {}
        } else {
            store.clearAll()
        }
    }

    fun export(context: Context, format: String): String {
        val store = TrafficStore.get(context)
        flushNowBlocking(store)
        return store.export(if (format == "csv") "csv" else "json")
    }

    fun labels(context: Context, apps: List<String>): Map<String, String> {
        val pm = context.packageManager
        val out = HashMap<String, String>()
        for (a in apps) {
            if (a.startsWith("~") || a.startsWith("uid:")) continue
            try {
                out[a] = pm.getApplicationLabel(pm.getApplicationInfo(a, 0)).toString()
            } catch (_: Exception) {}
        }
        return out
    }
}
