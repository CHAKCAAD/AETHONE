package com.chakcaad.aethone.shield

/// Family Shield — the honest protection state (pure JVM), phase 2.
///
/// Derived ONLY from real system state gathered by FamilyShield.status
/// (engine counters, the VpnService's actual Builder result, a live probe
/// of the local SOCKS ports, the per-app exclusion lists the TUN was built
/// with). Never from what the configuration *intends*.
///
///  * PROTECTED          — snapshot live in the engine, engine hook installed,
///                         and no known hole (empty reasons list).
///  * DEGRADED           — running and filtering, but at least one bypass is
///                         open; every reason is listed.
///  * INACTIVE           — shield disabled, or no tunnel to filter (proxy
///                         mode / disconnected).
///  * VALIDATION_FAILED  — the user enabled it but it is not enforced: the
///                         snapshot was refused / is not live, the engine
///                         hook is missing, or a start was refused
///                         fail-closed.
///
/// Rule (owner, phase 2): never PROTECTED while any local SOCKS listener is
/// reachable by other uids, IPv6 is not captured, a per-app exclusion is
/// active, the snapshot is invalid, or the engine hook is not installed.
object ShieldStatus {
    enum class State(val wire: String) {
        PROTECTED("protected"),
        DEGRADED("degraded"),
        INACTIVE("inactive"),
        VALIDATION_FAILED("validation_failed"),
    }

    /// One local SOCKS listener as observed on the device right now.
    data class Listener(
        val port: Int,
        /// something accepted a TCP connection on 127.0.0.1:port
        val listening: Boolean,
        /// phase 2.1: true only from runtime evidence — a guard is in force
        /// for this listener ([guard]) AND a probe from another process was
        /// refused ([probe]); see LoopbackSession.guarded
        val guarded: Boolean,
        /// what guards it at runtime: own-process / own-process+secret /
        /// secret / null (nothing — exposed)
        val guard: String? = null,
        /// the foreign-process probe result (LoopbackSession.Probe.wire)
        val probe: String? = null,
        /// which core / listener this is (Aether's declaration, or the port's tunnel)
        val kind: String? = null,
    )

    data class Inputs(
        val enabled: Boolean,
        val tunnelUp: Boolean,
        val snapshotLive: Boolean,
        val error: String? = null,
        /// the engine reports the shield snapshot active (zeptun counter 6)
        val engineHookInstalled: Boolean = snapshotLive,
        /// the Builder accepted ::/0 + a v6 address and the engine is v6-capable
        val ipv6Captured: Boolean = true,
        /// packages / modes that keep traffic out of the TUN
        val perAppExclusions: List<String> = emptyList(),
        val listeners: List<Listener> = emptyList(),
        /// Android Private DNS in strict (hostname) mode while strict mode
        /// wanted to block 853 — the DoT block was dropped to keep DNS working
        val privateDnsStrict: Boolean = false,
        /// Android < 10: no owner uid, app restrictions can not apply
        val appBlockingSupported: Boolean = true,
        val hasAppRestrictions: Boolean = false,
        /// a tunnel is running but was started before the shield was
        /// enabled (no snapshot, no IPv6 capture): it must be reconnected
        val unshieldedTunnel: Boolean = false,
    )

    data class Result(val state: State, val reasons: List<String>)

    fun compute(i: Inputs): Result {
        if (!i.enabled) return Result(State.INACTIVE, listOf("shield-disabled"))
        if (i.error != null) return Result(State.VALIDATION_FAILED, listOf(i.error))
        if (!i.tunnelUp) return Result(State.INACTIVE, listOf(if (i.unshieldedTunnel) "reconnect-required" else "no-tunnel"))
        val fatal = ArrayList<String>()
        if (!i.snapshotLive) fatal += "snapshot-invalid"
        if (!i.engineHookInstalled) fatal += "engine-hook-not-installed"
        if (fatal.isNotEmpty()) return Result(State.VALIDATION_FAILED, fatal)
        val r = ArrayList<String>()
        if (!i.ipv6Captured) r += "ipv6-not-captured"
        if (i.perAppExclusions.isNotEmpty()) r += "per-app-exclusions:" + i.perAppExclusions.size
        val exposed = i.listeners.filter { it.listening && !it.guarded }.map { it.port }.distinct().sorted()
        if (exposed.isNotEmpty()) r += "local-socks-exposed:" + exposed.joinToString(",")
        if (i.privateDnsStrict) r += "private-dns-strict"
        if (!i.appBlockingSupported && i.hasAppRestrictions) r += "app-blocking-unsupported"
        return Result(if (r.isEmpty()) State.PROTECTED else State.DEGRADED, r)
    }
}

/// Per-app tunneling exclusions (phase 2 audit). The VpnService builds the
/// TUN from the user's per-app pick ("all" / "allow" / "disallow"); every
/// app outside the TUN reaches the network directly — the shield sees none
/// of its DNS or flows. This reports the precise state per app.
object ExclusionAudit {
    enum class AppState(val wire: String) {
        /// traffic enters the TUN: DNS + flows filtered
        FILTERED("filtered"),
        /// excluded by the disallow list: bypasses the shield completely
        EXCLUDED_DISALLOWED("excluded-disallow-list"),
        /// allow mode: only the listed apps enter the TUN — every other app
        /// on the device bypasses the shield
        EXCLUDED_NOT_ALLOWED("excluded-not-in-allow-list"),
        /// AETHONE itself (loop prevention); its own sockets are protect()ed
        SELF_EXCLUDED("self-excluded-loop-prevention"),
        /// listed but not installed / not visible: no effect
        NOT_INSTALLED("not-installed"),
    }

    data class Entry(val packageName: String, val state: AppState)

    data class Report(
        val mode: String,
        val entries: List<Entry>,
        /// true when apps other than AETHONE itself are outside the TUN
        val degrading: Boolean,
        /// allow mode: everything not listed is outside the TUN
        val othersExcluded: Boolean,
    ) {
        /// the per-app reasons fed into ShieldStatus
        fun reasons(): List<String> {
            val out = ArrayList<String>()
            if (othersExcluded) out += "allow-mode:all-unlisted-apps"
            entries.filter { it.state == AppState.EXCLUDED_DISALLOWED }.forEach { out += it.packageName }
            return out
        }
    }

    /// [installed] answers whether a package exists (PackageManager on the
    /// device). Mirrors AethoneVpnService.startTunnel exactly: an allow list
    /// with no installed entry falls back to the whole-device rule set.
    fun audit(mode: String, apps: List<String>, self: String, installed: (String) -> Boolean): Report {
        val listed = apps.filter { it.isNotBlank() && it != self }.distinct()
        val entries = ArrayList<Entry>()
        entries += Entry(self, AppState.SELF_EXCLUDED)
        when (mode) {
            "allow" -> {
                val valid = listed.filter(installed)
                if (valid.isEmpty()) {
                    // degenerate allow list -> whole-device TUN (as the Builder code does)
                    listed.forEach { entries += Entry(it, AppState.NOT_INSTALLED) }
                    return Report("all", entries, degrading = false, othersExcluded = false)
                }
                listed.forEach { entries += Entry(it, if (installed(it)) AppState.FILTERED else AppState.NOT_INSTALLED) }
                return Report(mode, entries, degrading = true, othersExcluded = true)
            }
            "disallow" -> {
                var any = false
                listed.forEach {
                    if (installed(it)) { entries += Entry(it, AppState.EXCLUDED_DISALLOWED); any = true }
                    else entries += Entry(it, AppState.NOT_INSTALLED)
                }
                return Report(mode, entries, degrading = any, othersExcluded = false)
            }
            else -> return Report("all", entries, degrading = false, othersExcluded = false)
        }
    }
}

/// Wrap-safe reading of zeptun's u32 shield counters (flow/shield.zig). All
/// of them count EVENTS, never bytes; they wrap modulo 2^32 because
/// armeabi-v7a has no 64-bit atomics. Kotlin keeps 64-bit accumulators fed
/// by wrap-safe deltas, so totals never go backwards.
class ShieldCounters(private val size: Int = 8) {
    private val last = LongArray(size) { -1L }
    private val total = LongArray(size)

    companion object {
        const val MASK = 0xffffffffL
        /// (now - before) mod 2^32 — correct across one wrap.
        fun delta(before: Long, now: Long): Long = (now - before) and MASK
    }

    /// Feeds one raw reading (0..2^32-1, or <0 = engine not running, which
    /// resets the baseline: a new engine starts at 0). Returns the total.
    @Synchronized fun observe(index: Int, raw: Long): Long {
        if (index !in 0 until size) return -1L
        if (raw < 0) { last[index] = -1L; return total[index] }
        val v = raw and MASK
        val prev = last[index]
        total[index] += if (prev < 0) v else delta(prev, v)
        last[index] = v
        return total[index]
    }

    @Synchronized fun total(index: Int): Long = if (index in 0 until size) total[index] else -1L
}
