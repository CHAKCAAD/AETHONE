package com.chakcaad.aethone.shield

/// Family Shield — the honest protection state (pure JVM).
///
///  * OFF       — shield disabled, or no tunnel (proxy mode / disconnected:
///                there is no TUN to filter).
///  * PROTECTED — snapshot live in the engine and no known hole.
///  * DEGRADED  — running, but at least one bypass stays open; every reason
///                is listed (never hidden behind a green badge).
///  * FAILED    — the user enabled it but the engine refused the snapshot
///                (the tunnel was not started unfiltered).
object ShieldStatus {
    enum class State { OFF, PROTECTED, DEGRADED, FAILED }

    data class Inputs(
        val enabled: Boolean,
        val tunnelUp: Boolean,
        val snapshotLive: Boolean,
        val error: String? = null,
        val ipv6Captured: Boolean = true,
        /// per-app tunneling excluded apps from the TUN (allow / disallow lists)
        val perAppExclusions: Boolean = false,
        val unauthenticatedPorts: List<Int> = emptyList(),
        /// Android Private DNS in strict (hostname) mode while strict mode
        /// wanted to block 853 — the DoT block was dropped to keep DNS working
        val privateDnsStrict: Boolean = false,
        /// Android < 10: no owner uid, app restrictions can not apply
        val appBlockingSupported: Boolean = true,
        val hasAppRestrictions: Boolean = false,
    )

    data class Result(val state: State, val reasons: List<String>)

    fun compute(i: Inputs): Result {
        if (!i.enabled) return Result(State.OFF, emptyList())
        if (i.error != null) return Result(State.FAILED, listOf(i.error))
        if (!i.tunnelUp) return Result(State.OFF, listOf("no-tunnel"))
        if (!i.snapshotLive) return Result(State.FAILED, listOf("snapshot-not-live"))
        val r = ArrayList<String>()
        if (!i.ipv6Captured) r += "ipv6-not-captured"
        if (i.perAppExclusions) r += "per-app-exclusions"
        if (i.unauthenticatedPorts.isNotEmpty()) r += "local-socks-unauthenticated:" + i.unauthenticatedPorts.joinToString(",")
        if (i.privateDnsStrict) r += "private-dns-strict"
        if (!i.appBlockingSupported && i.hasAppRestrictions) r += "app-blocking-unsupported"
        return Result(if (r.isEmpty()) State.PROTECTED else State.DEGRADED, r)
    }
}
