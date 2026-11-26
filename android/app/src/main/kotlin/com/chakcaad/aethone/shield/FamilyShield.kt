package com.chakcaad.aethone.shield

import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.os.Build
import android.util.Log
import dev.zeptun.Zeptun
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit

/// Family Shield — the Android runtime (VpnService process).
///
/// Independent policy layer evaluated BEFORE HybridPolicy and before any
/// SOCKS dial:
///   DNS query  → zeptun (native matcher) → NXDOMAIN, no fake IP, no upstream
///   new flow   → zeptun re-checks the fake-IP name / real address →
///                HybridRouter.route(…, shieldVerdict) → [decide] adds app
///                restrictions with the ONE owner-uid lookup → reject (RST /
///                ICMP) or continue to HybridPolicy → dial
///   rule change→ [applyLive] compiles a new snapshot → native validates and
///                swaps atomically → zeptun_revalidate_flows aborts the newly
///                blocked flows (native verdict + [revalidate] for apps)
///
/// The native side (SQLite here + the compiled snapshot) is the source of
/// truth; Flutter is only a view (phase 2).
object FamilyShield {
    private const val TAG = "AethoneShield"
    private const val FLOW_CACHE_MAX = 4096
    private const val FLOW_CACHE_TTL_MS = 30 * 60_000L

    /// What the VpnService has to do differently for a shielded start.
    data class StartPlan(
        val active: Boolean,
        /// route ::/0 and give the TUN an IPv6 address (bypass B)
        val captureIpv6: Boolean = false,
        /// answer every UDP/53 query with the shielded fake-IP resolver
        val hijackDns: Boolean = false,
        val error: String? = null,
    )

    private class Runtime(
        val profileId: String,
        val restrictedPackages: Set<String>,
        @Volatile var restrictedAppIds: Set<Int>,
        val generation: Int,
    )

    @Volatile private var store: ShieldRepository? = null
    @Volatile private var appContext: Context? = null
    @Volatile private var runtime: Runtime? = null
    @Volatile private var snapshotInstalled = false
    @Volatile private var lastError: String? = null
    @Volatile private var tunnelUp = false
    @Volatile private var ipv6Captured = true
    @Volatile private var perAppExclusions = false
    @Volatile private var tunnelPorts: List<Int> = emptyList()
    @Volatile private var privateDnsStrict = false
    @Volatile private var appMode: String = "all"
    @Volatile private var appList: List<String> = emptyList()
    @Volatile private var pinCore: ParentPin? = null

    /// wrap-safe 64-bit totals of zeptun's u32 event counters
    val counters = ShieldCounters()

    /// Self-test only (ShieldTestReceiver, debug property + root-only
    /// broadcast): extra app ids treated as restricted, so the CI emulator can
    /// exercise the uid path with the shell uid (2000), which has no package.
    val testRestrictedAppIds: MutableSet<Int> = java.util.concurrent.ConcurrentHashMap.newKeySet()

    val events = ShieldEvents()
    private val flowUids = ConcurrentHashMap<String, Long>() // key → (uid shl 32) | (minute stamp)
    private var flusher: ScheduledExecutorService? = null

    @Volatile var categoryDb: ShieldCompiler.CategoryDatabase = ShieldCompiler.CategoryDatabase()

    val appBlockingSupported: Boolean get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q

    fun repo(context: Context): ShieldRepository {
        store?.let { return it }
        synchronized(this) {
            store?.let { return it }
            appContext = context.applicationContext
            val s = ShieldStore(context.applicationContext)
            store = s
            return s
        }
    }

    /// The process-wide PIN core (admin sessions live in memory only).
    fun pin(context: Context): ParentPin {
        pinCore?.let { return it }
        synchronized(this) {
            pinCore?.let { return it }
            val p = ParentPin(repo(context), KeystorePepper())
            pinCore = p
            return p
        }
    }

    fun admin(context: Context): ShieldAdmin = ShieldAdmin(repo(context), pin(context))

    /// True while a shielded tunnel is running (a routed start is required).
    val active: Boolean get() = runtime != null

    /// Whether the flow callback must look up the owner uid (app restrictions
    /// exist, or may be added live and need the uid of open flows).
    val needsUid: Boolean get() = runtime != null && appBlockingSupported

    /// Called by the VpnService before establishing the TUN. Compiles the
    /// active profile and hands the snapshot to libzeptun-jni, which applies
    /// it before the engine thread starts (no unfiltered window). On failure
    /// the start must be refused (fail-closed).
    fun prepareStart(context: Context, appMode: String, apps: List<String>, port: Int): StartPlan {
        val repo = repo(context)
        val cfg = try { repo.config() } catch (t: Throwable) {
            Log.e(TAG, "shield config unreadable", t)
            return StartPlan(active = false)
        }
        perAppExclusions = appMode == "allow" || (appMode == "disallow" && apps.isNotEmpty())
        this.appMode = appMode
        this.appList = apps
        tunnelPorts = listOf(port)
        if (!cfg.enabled) {
            clearNative()
            runtime = null
            return StartPlan(active = false)
        }
        val profile = cfg.activeProfileId?.let { repo.profile(it) }
            ?: return failStart("no-active-profile")
        return try {
            privateDnsStrict = profile.strict.enabled && profile.strict.blockDot && privateDnsStrictMode(context)
            val compiled = ShieldCompiler.compile(profile, repo.rules(profile.id), categoryDb, cfg.generation, suppressDot = privateDnsStrict)
            val rc = Zeptun.nativeShieldSnapshot(compiled.bytes)
            if (rc != 0) return failStart("snapshot-rejected:rc=$rc")
            snapshotInstalled = true
            events.logDomains = cfg.logDomains
            val pkgs = repo.appRestrictions(profile.id).map { it.packageName }.toSet()
            runtime = Runtime(profile.id, pkgs, appIds(context, pkgs), cfg.generation)
            lastError = null
            startFlusher()
            Log.i(TAG, "shield armed: profile=${profile.preset.key} gen=${cfg.generation} domains=${compiled.domains} cidrs=${compiled.cidrs} apps=${pkgs.size}")
            StartPlan(active = true, captureIpv6 = true, hijackDns = true)
        } catch (t: Throwable) {
            Log.e(TAG, "shield compile failed", t)
            failStart("compile-failed:${t.javaClass.simpleName}")
        }
    }

    private fun failStart(reason: String): StartPlan {
        lastError = reason
        runtime = null
        events.record("snapshot_rejected")
        return StartPlan(active = true, error = "shield-$reason")
    }

    fun onTunnelUp(ipv6: Boolean) {
        tunnelUp = true
        ipv6Captured = ipv6
    }

    /// Any tunnel (shielded or not) — lets the status say "reconnect
    /// required" when the shield was enabled while an unshielded tunnel runs.
    @Volatile var anyTunnelUp = false

    /// The runtime itself stays: a restart (port / protocol change) calls
    /// [prepareStart] again before the next engine runs, and the first flows
    /// of that engine must already see the app restrictions.
    fun onTunnelDown(reason: String) {
        tunnelUp = false
        if (reason == "revoked" && runtime != null) events.record("vpn_revoked")
        flowUids.clear()
        flush()
    }

    private fun clearNative() {
        if (!snapshotInstalled) return
        try {
            Zeptun.nativeShieldSnapshot(null)
        } catch (t: Throwable) {
            Log.w(TAG, "clearing the shield snapshot failed", t)
        }
        snapshotInstalled = false
    }

    /// Live rule change (admin op, PIN session checked by the caller): a new
    /// snapshot is validated and swapped; on refusal the previous one stays.
    /// Then every open flow is re-checked.
    fun applyLive(context: Context): String? {
        val repo = repo(context)
        val cfg = repo.config()
        val running = runtime != null && tunnelUp
        if (!cfg.enabled) {
            if (running) {
                // switching the shield off needs no restart of the tunnel: the
                // snapshot is cleared and nothing is enforced any more
                clearNative()
                runtime = null
            }
            return null
        }
        if (!running) return "not-running" // applied at the next tunnel start
        val profile = cfg.activeProfileId?.let { repo.profile(it) } ?: return "no-active-profile"
        return try {
            val compiled = ShieldCompiler.compile(profile, repo.rules(profile.id), categoryDb, cfg.generation, suppressDot = privateDnsStrict)
            val rc = Zeptun.nativeShieldSnapshot(compiled.bytes)
            if (rc != 0) {
                events.record("snapshot_rejected")
                return "snapshot-rejected:rc=$rc"
            }
            val pkgs = repo.appRestrictions(profile.id).map { it.packageName }.toSet()
            runtime = Runtime(profile.id, pkgs, appIds(context, pkgs), cfg.generation)
            events.logDomains = cfg.logDomains
            events.record("config_change")
            Zeptun.nativeRevalidateFlows()
            null
        } catch (t: Throwable) {
            Log.e(TAG, "live shield update failed", t)
            "compile-failed:${t.javaClass.simpleName}"
        }
    }

    private fun appIds(context: Context, pkgs: Set<String>): Set<Int> {
        val pm = context.packageManager
        val out = HashSet<Int>()
        for (p in pkgs) {
            try {
                out += pm.getApplicationInfo(p, 0).uid % 100_000
            } catch (_: PackageManager.NameNotFoundException) {
                Log.w(TAG, "restricted app $p: not installed / not visible")
            }
        }
        return out
    }

    private fun flowKey(proto: Int, src: ByteArray, sport: Int, dst: ByteArray, dport: Int): String {
        val sb = StringBuilder(48).append(proto).append('|')
        for (b in src) sb.append(b.toInt() and 0xff).append('.')
        sb.append(':').append(sport).append('>')
        for (b in dst) sb.append(b.toInt() and 0xff).append('.')
        return sb.append(':').append(dport).toString()
    }

    /// From HybridRouter.route (engine thread). [uid] is the flow's single
    /// owner lookup (null when not needed / unsupported). Never throws.
    fun decide(
        proto: Int, src: ByteArray, sport: Int, dst: ByteArray, dport: Int,
        name: String?, uid: Int?, nativeVerdict: Int, shieldAware: Boolean,
    ): ShieldDecision.Decision? {
        val rt = runtime ?: return null
        val verdict = if (shieldAware) ShieldSnapshot.Verdict.decode(nativeVerdict) else ShieldSnapshot.Verdict.INACTIVE
        val d = ShieldDecision.decide(verdict, uid, if (testRestrictedAppIds.isEmpty()) rt.restrictedAppIds else rt.restrictedAppIds + testRestrictedAppIds)
        if (d is ShieldDecision.Decision.Block) {
            events.record("flow_block", d.level, d.category, appLabel(uid), name)
        } else if (uid != null && uid >= 0) {
            rememberFlow(flowKey(proto, src, sport, dst, dport), uid)
        }
        return d
    }

    private fun rememberFlow(key: String, uid: Int) {
        val now = System.currentTimeMillis()
        if (flowUids.size >= FLOW_CACHE_MAX) {
            val cutoff = now - FLOW_CACHE_TTL_MS
            flowUids.entries.removeIf { (it.value and 0xffffffffL) * 1000L < cutoff }
            if (flowUids.size >= FLOW_CACHE_MAX) flowUids.clear()
        }
        flowUids[key] = (uid.toLong() shl 32) or ((now / 1000L) and 0xffffffffL)
    }

    /// From zeptun_revalidate_flows (engine thread): 1 = abort the flow. The
    /// native verdict was already enforced natively; this adds app
    /// restrictions using the uid recorded when the flow opened (no new
    /// lookup). Unknown flows are kept.
    fun revalidate(proto: Int, src: ByteArray, sport: Int, dst: ByteArray, dport: Int, name: String?, nativeVerdict: Int): Int {
        val rt = runtime ?: return 0
        val v = flowUids[flowKey(proto, src, sport, dst, dport)] ?: return 0
        val uid = (v ushr 32).toInt()
        if ((uid % 100_000) in rt.restrictedAppIds || (uid % 100_000) in testRestrictedAppIds) {
            events.record("flow_killed", ShieldSnapshot.Level.APP, null, appLabel(uid), name)
            return 1
        }
        if (ShieldSnapshot.Verdict.decode(nativeVerdict).block) {
            events.record("flow_killed", ShieldSnapshot.Verdict.decode(nativeVerdict).level, null, appLabel(uid), name)
        }
        return 0
    }

    private fun appLabel(uid: Int?): String? {
        if (uid == null || uid < 0) return null
        val ctx = appContext ?: return "uid:$uid"
        return try {
            ctx.packageManager.getPackagesForUid(uid)?.firstOrNull() ?: "uid:$uid"
        } catch (_: Throwable) {
            "uid:$uid"
        }
    }

    private fun privateDnsStrictMode(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return false
        return try {
            val cm = context.getSystemService(ConnectivityManager::class.java) ?: return false
            val net = cm.activeNetwork ?: return false
            val lp = cm.getLinkProperties(net) ?: return false
            // strict (hostname) mode: a server name is set and in use
            lp.isPrivateDnsActive && lp.privateDnsServerName != null
        } catch (_: Throwable) {
            false
        }
    }

    @Synchronized private fun startFlusher() {
        if (flusher != null) return
        flusher = Executors.newSingleThreadScheduledExecutor { r -> Thread(r, "aethone-shield-events").apply { isDaemon = true } }
            .also { it.scheduleWithFixedDelay({ flush() }, 15, 15, TimeUnit.SECONDS) }
    }

    fun flush() {
        val repo = store ?: return
        try {
            events.flush { rows -> repo.addEvents(rows) }
            val days = repo.config().retentionDays.coerceIn(1, 365)
            repo.pruneEvents(System.currentTimeMillis() - days * 86_400_000L)
        } catch (t: Throwable) {
            Log.w(TAG, "event flush failed (kept for the next batch)", t)
        }
    }

    /// The engine reports the snapshot active (zeptun shield counter 6).
    fun engineHookInstalled(): Boolean = try { Zeptun.nativeShieldCounter(6) == 1L } catch (_: Throwable) { false }

    fun exclusionAudit(context: Context): ExclusionAudit.Report {
        val pm = context.packageManager
        return ExclusionAudit.audit(appMode, appList, context.packageName) { p ->
            try { pm.getApplicationInfo(p, 0); true } catch (_: Exception) { false }
        }
    }

    /// Live probe of the four local SOCKS ports (127.0.0.1:1819–1822): a
    /// port that accepts a TCP connection is a listener; it counts as
    /// guarded only when a LoopbackGuard listener of this process owns it.
    /// Blocking I/O (≤ 4 × 150 ms) — never call on the main thread.
    fun probeListeners(): List<ShieldStatus.Listener> = SocksAuth.Listener.entries.map { l ->
        val listening = try {
            java.net.Socket().use { s ->
                s.connect(java.net.InetSocketAddress(java.net.InetAddress.getByName("127.0.0.1"), l.port), 150)
                true
            }
        } catch (_: Exception) { false }
        ShieldStatus.Listener(l.port, listening, guarded = listening && l.port in LoopbackGuard.guardedPorts)
    }

    /// Status derived from real system state only (call off the main thread:
    /// it probes the local listeners).
    fun status(context: Context): Map<String, Any?> {
        val cfg = try { repo(context).config() } catch (_: Throwable) { ShieldConfig() }
        val rt = runtime
        val hook = tunnelUp && engineHookInstalled()
        val listeners = if (tunnelUp) probeListeners() else emptyList()
        val audit = exclusionAudit(context)
        fun raw(i: Int): Long = try { Zeptun.nativeShieldCounter(i) } catch (_: Throwable) { -1L }
        val totals = (0..7).associateWith { i -> if (i == 5 || i == 6) raw(i) else counters.observe(i, raw(i)) }
        val v6Engine = raw(7) >= 0
        val res = ShieldStatus.compute(
            ShieldStatus.Inputs(
                enabled = cfg.enabled,
                tunnelUp = tunnelUp,
                snapshotLive = rt != null && snapshotInstalled,
                error = lastError?.let { "shield-$it" },
                engineHookInstalled = hook,
                ipv6Captured = ipv6Captured && v6Engine,
                perAppExclusions = if (audit.degrading) audit.reasons() else emptyList(),
                listeners = listeners,
                privateDnsStrict = privateDnsStrict,
                appBlockingSupported = appBlockingSupported,
                hasAppRestrictions = (rt?.restrictedPackages?.isNotEmpty() == true),
                unshieldedTunnel = anyTunnelUp && !tunnelUp,
            ),
        )
        return mapOf(
            "state" to res.state.wire,
            "reasons" to res.reasons,
            "enabled" to cfg.enabled,
            "tunnelUp" to tunnelUp,
            "engineHook" to hook,
            "profile" to rt?.profileId,
            "generation" to rt?.generation,
            "dnsBlocked" to totals[0],
            "flowBlocked" to totals[1],
            "flowsKilled" to totals[2],
            "snapshotSwaps" to totals[3],
            "snapshotRejected" to totals[4],
            "ipv6Packets" to totals[7],
            "ipv6Route" to ipv6Captured,
            "appBlockingSupported" to appBlockingSupported,
            "listeners" to listeners.map { mapOf("port" to it.port, "listening" to it.listening, "guarded" to it.guarded) },
            "exclusions" to mapOf(
                "mode" to audit.mode,
                "othersExcluded" to audit.othersExcluded,
                "apps" to audit.entries.map { mapOf("package" to it.packageName, "state" to it.state.wire) },
            ),
            "pendingEvents" to events.pendingCount(),
        )
    }
}
