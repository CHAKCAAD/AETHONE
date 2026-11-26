package com.chakcaad.aethone.routing

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
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference

/// Hybrid per-tunnel routing — the Android half of the native routing
/// engine. zeptun (patched, see scripts/zeptun-hybrid-routing.patch) calls
/// [route] through JNI (`dev.zeptun.Zeptun.route`) once per new flow, on its
/// engine thread, BEFORE the upstream dial. This object:
///   * attributes the flow to an app: ConnectivityManager
///     .getConnectionOwnerUid(proto, local, remote) — the platform's own
///     socket-owner lookup, valid for the active VPN app (API 29+);
///   * asks [HybridPolicy] (app → exact domain → wildcard → CIDR → default);
///   * answers zeptun's route code: 0 = the protocol's default listener,
///     16+i = route server i, 3 = reject (fail-closed; never "direct").
///
/// Rules can be replaced while the tunnel runs ([update]): new flows use
/// the new policy at once, established flows keep the route they opened on.
object HybridRouter {
    private const val TAG = "AethoneHybrid"
    const val ROUTE_DEFAULT = 0
    const val ROUTE_BASE = 16
    const val ROUTE_REJECT = 3
    private const val PROTO_TCP = 6
    private const val PROTO_UDP = 17

    data class Config(
        val profile: String,
        /// Tunnel id → "127.0.0.1:port", default tunnel first.
        val endpoints: LinkedHashMap<String, String>,
        val rules: List<HybridPolicy.Rule>,
    ) {
        val defaultTunnel: String get() = endpoints.keys.first()

        /// The extra zeptun route servers, in route order (route 1..n).
        val routeServers: String get() = endpoints.values.drop(1).joinToString(",")
        val key: String get() = "$profile|${endpoints.entries.joinToString(";")}"
    }

    @Volatile private var appContext: Context? = null
    private val policy = AtomicReference<HybridPolicy?>(null)
    @Volatile private var uidPackages: Map<Int, List<String>> = emptyMap()
    @Volatile var live: Boolean = false
        private set
    @Volatile private var lastError: String? = null
    private val routed = ConcurrentHashMap<String, AtomicLong>()
    private val hits = ConcurrentHashMap<String, AtomicLong>()
    private val refused = AtomicLong()
    private val unattributed = AtomicLong()

    val appRoutingSupported: Boolean
        get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q

    fun parse(json: String?): Config? {
        if (json.isNullOrBlank()) return null
        return try {
            val o = JSONObject(json)
            val eps = LinkedHashMap<String, String>()
            val arr = o.getJSONArray("tunnels")
            for (i in 0 until arr.length()) {
                val t = arr.getJSONObject(i)
                eps[t.getString("id")] = t.getString("endpoint")
            }
            if (eps.size < 2) return null
            val rules = ArrayList<HybridPolicy.Rule>()
            val ra = o.optJSONArray("rules")
            if (ra != null) for (i in 0 until ra.length()) {
                val r = ra.getJSONObject(i)
                val kind = when (r.getString("kind")) {
                    "app" -> HybridPolicy.Kind.APP
                    "domain" -> HybridPolicy.Kind.DOMAIN
                    "wildcard" -> HybridPolicy.Kind.WILDCARD
                    "cidr" -> HybridPolicy.Kind.CIDR
                    else -> continue
                }
                rules += HybridPolicy.Rule(
                    id = r.getString("id"),
                    kind = kind,
                    value = r.getString("value"),
                    tunnel = r.getString("tunnel"),
                    enabled = r.optBoolean("enabled", true),
                )
            }
            Config(o.getString("profile"), eps, rules)
        } catch (e: Exception) {
            Log.w(TAG, "bad hybrid routing config", e)
            null
        }
    }

    /// Gives the router the context its owner-uid lookup needs, for routed
    /// starts without a hybrid policy (analytics / Family Shield only).
    fun attach(context: Context) {
        appContext = context.applicationContext
    }

    /// Installs [cfg] for the tunnel that is about to start (or is running).
    fun install(context: Context, cfg: Config) {
        appContext = context.applicationContext
        val p = HybridPolicy.build(cfg.profile, cfg.endpoints.keys.toList(), cfg.rules)
        uidPackages = mapPackages(context, p.appPackages)
        policy.set(p)
        lastError = null
        Log.i(
            TAG,
            "policy ${cfg.profile}: ${p.activeCount} active, ${p.rejected.size} rejected, " +
                "tunnels=${cfg.endpoints}",
        )
    }

    /// Live rule update while connected — same profile/tunnels only (a
    /// different profile means a different protocol, which restarts the
    /// tunnel through the normal start path).
    fun update(context: Context, cfg: Config): String? {
        val current = policy.get() ?: return "not-running"
        if (current.profile != cfg.profile || current.tunnels != cfg.endpoints.keys.toList()) {
            return "profile-mismatch"
        }
        install(context, cfg)
        return null
    }

    fun markLive(on: Boolean) {
        live = on
        if (!on) policy.set(null)
    }

    private fun mapPackages(context: Context, packages: Set<String>): Map<Int, List<String>> {
        val pm = context.packageManager
        val out = HashMap<Int, MutableList<String>>()
        for (pkg in packages) {
            try {
                val uid = pm.getApplicationInfo(pkg, 0).uid
                // appId: the same app in a work profile / another user
                out.getOrPut(uid % 100_000) { ArrayList() } += pkg
            } catch (_: PackageManager.NameNotFoundException) {
                Log.w(TAG, "app rule for $pkg: not installed")
            }
        }
        return out
    }

    /// The JNI entry (via dev.zeptun.Zeptun.route / routeShield). Never throws.
    /// Also the flow-open event of Traffic Analytics: a metered single-tunnel
    /// start runs with no policy (every flow → the default route) only so
    /// this callback sees each flow.
    ///
    /// Order (Family Shield, docs/family-shield-architecture.md):
    ///   1. the owner uid is looked up ONCE when any layer needs it and is
    ///      shared by the shield, the hybrid policy and the meter;
    ///   2. Family Shield decides first — a blocked flow is rejected (TCP RST
    ///      / ICMP unreachable) before the hybrid policy and before any
    ///      SOCKS dial, and it is never handed to the traffic meter;
    ///   3. the hybrid policy routes what passed (unchanged);
    ///   4. the meter observes the flows that were not rejected.
    /// [shield] is zeptun's native shield verdict; [shieldAware] = false for
    /// the legacy callback (the shield then fails closed if it is active).
    fun route(
        proto: Int, family: Int, src: ByteArray, sport: Int, dst: ByteArray, dport: Int,
        name: String?, shield: Int = 0, shieldAware: Boolean = false,
    ): Int {
        return try {
            val p = policy.get()
            val metering = com.chakcaad.aethone.analytics.TrafficMeter.active
            val shieldOn = com.chakcaad.aethone.shield.FamilyShield.active
            val needUid = com.chakcaad.aethone.shield.RouteGate.needsUid(
                shieldOn && com.chakcaad.aethone.shield.FamilyShield.needsUid,
                p?.hasAppRules == true,
                metering,
            )
            // no context yet (should not happen on a routed start): leave the
            // lookup to the meter's own fallback instead of booking INVALID
            val uid = if (needUid && appContext != null) ownerUid(proto, src, sport, dst, dport) else null
            val sd = if (shieldOn) {
                com.chakcaad.aethone.shield.FamilyShield.decide(proto, src, sport, dst, dport, name, uid, shield, shieldAware)
            } else {
                null
            }
            val out = com.chakcaad.aethone.shield.RouteGate.combine(sd, metering) {
                if (p == null) ROUTE_DEFAULT else hybridAnswer(p, uid, name, dst)
            }
            if (out.observe) observe(proto, src, sport, dst, dport, name, uid, out.answer)
            out.answer
        } catch (t: Throwable) {
            // Fail-closed: an engine error refuses the flow (the app retries);
            // it never sends the flow somewhere the user did not choose.
            lastError = t.javaClass.simpleName + ": " + (t.message ?: "")
            refused.incrementAndGet()
            ROUTE_REJECT
        }
    }

    private fun hybridAnswer(p: HybridPolicy, uid: Int?, name: String?, dst: ByteArray): Int {
        val owners = if (p.hasAppRules && uid != null) packagesOf(uid) else emptyList()
        return when (val d = p.decide(owners, name, if (name == null) dst else null)) {
            is HybridPolicy.Decision.Refuse -> {
                refused.incrementAndGet()
                hits.getOrPut(d.ruleId) { AtomicLong() }.incrementAndGet()
                ROUTE_REJECT
            }
            is HybridPolicy.Decision.Route -> {
                routed.getOrPut(p.tunnels[d.tunnel]) { AtomicLong() }.incrementAndGet()
                d.ruleId?.let { hits.getOrPut(it) { AtomicLong() }.incrementAndGet() }
                if (d.tunnel == 0) ROUTE_DEFAULT else ROUTE_BASE + d.tunnel - 1
            }
        }
    }

    private fun observe(proto: Int, src: ByteArray, sport: Int, dst: ByteArray, dport: Int, name: String?, uid: Int?, answer: Int) {
        try {
            com.chakcaad.aethone.analytics.TrafficMeter.onFlowOpen(proto, src, sport, dst, dport, name, uid)
        } catch (_: Throwable) {
            // analytics never affects routing
        }
    }

    /// The platform's socket-owner lookup (API 29+); INVALID_UID when it
    /// cannot name one.
    private fun ownerUid(proto: Int, src: ByteArray, sport: Int, dst: ByteArray, dport: Int): Int {
        if (!appRoutingSupported) return Process.INVALID_UID
        val ctx = appContext ?: return Process.INVALID_UID
        if (proto != PROTO_TCP && proto != PROTO_UDP) return Process.INVALID_UID
        val cm = ctx.getSystemService(ConnectivityManager::class.java) ?: return Process.INVALID_UID
        val uid = try {
            cm.getConnectionOwnerUid(
                proto,
                InetSocketAddress(InetAddress.getByAddress(src), sport),
                InetSocketAddress(InetAddress.getByAddress(dst), dport),
            )
        } catch (_: Exception) {
            Process.INVALID_UID
        }
        if (uid == Process.INVALID_UID || uid < 0) unattributed.incrementAndGet()
        return uid
    }

    private fun packagesOf(uid: Int): List<String> =
        if (uid == Process.INVALID_UID || uid < 0) emptyList() else uidPackages[uid % 100_000] ?: emptyList()

    /// The honest applied state for the UI.
    fun status(): Map<String, Any?> {
        val p = policy.get()
        return mapOf(
            "live" to (live && p != null),
            "profile" to p?.profile,
            "tunnels" to p?.tunnels,
            "activeRules" to (p?.activeCount ?: 0),
            "rejected" to (p?.rejected?.map { mapOf("id" to it.first.id, "reason" to it.second) } ?: emptyList<Any>()),
            "routed" to routed.mapValues { it.value.get() },
            "hits" to hits.mapValues { it.value.get() },
            "refused" to refused.get(),
            "unattributed" to unattributed.get(),
            "appRoutingSupported" to appRoutingSupported,
            "error" to lastError,
        )
    }

    fun resetCounters() {
        routed.clear(); hits.clear(); refused.set(0); unattributed.set(0)
    }
}
