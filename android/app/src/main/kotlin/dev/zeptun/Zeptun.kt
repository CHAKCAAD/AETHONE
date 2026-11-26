package dev.zeptun

/// JNI bridge surface of the pinned zeptun engine (1.1.3 @ 08a1ab0).
/// `libzeptun-jni.so` registers these exact methods on THIS class
/// (`src/jni/zeptun_jni.c`, ZEPTUN_JNI_CLASS "dev/zeptun/Zeptun") — the
/// package/class names must stay verbatim or RegisterNatives silently
/// no-ops (the bridge returns JNI_VERSION_1_6 without the methods).
///
///  * [nativeStart] — adopts the VpnService descriptor (`--tun-fd` forces the
///    userspace stack), installs the protect callback that calls
///    `VpnService.protect(int)` for every upstream socket, and runs the
///    engine on its own thread. `config` is the TOML document (mobile
///    preset + socks5 handler + fake-IP DNS); null starts from the preset.
///  * [nativeStop] — stop + join + destroy (idempotent by bridge design).
///  * [meter] — per-flow byte reports for Traffic Analytics (routed starts).
///  * [nativeCounter] — raw ZeptunStats field by index (order:
///    0 rx_packets, 1 rx_bytes, 2 tx_packets, 3 tx_bytes, …; -1 when the
///    engine is not running).
///
/// One engine per process (upstream rule — matches the Aether discipline).
object Zeptun {
    init {
        System.loadLibrary("zeptun-jni")
    }

    external fun nativeStart(service: Any?, fd: Int, config: String?): Int

    /// AETHONE hybrid routing (scripts/zeptun-hybrid-routing.patch):
    /// [nativeStart] plus the extra SOCKS5 route servers ("host:port,…") and
    /// the per-flow route callback, which lands in [route].
    external fun nativeStartRouted(service: Any?, fd: Int, config: String?, servers: String): Int

    /// Called by libzeptun-jni on the engine thread for every new flow
    /// while a routed tunnel runs. Returns zeptun's route code.
    @JvmStatic
    fun route(proto: Int, family: Int, src: ByteArray, sport: Int, dst: ByteArray, dport: Int, name: String?): Int =
        com.chakcaad.aethone.routing.HybridRouter.route(proto, family, src, sport, dst, dport, name, 0, false)

    /// AETHONE Family Shield (scripts/zeptun-hybrid-routing.patch, shield
    /// part): the route callback with the native shield verdict of the flow
    /// (flow/shield.zig Verdict.encode). libzeptun-jni prefers this over
    /// [route] when present. Same R8 keep rule as [route].
    @JvmStatic
    fun routeShield(proto: Int, family: Int, src: ByteArray, sport: Int, dst: ByteArray, dport: Int, name: String?, shield: Int): Int =
        com.chakcaad.aethone.routing.HybridRouter.route(proto, family, src, sport, dst, dport, name, shield, true)

    /// AETHONE Family Shield: asked for every live flow after
    /// [nativeRevalidateFlows]; non-zero aborts the flow. Never throws.
    @JvmStatic
    fun revalidate(proto: Int, family: Int, src: ByteArray, sport: Int, dst: ByteArray, dport: Int, name: String?, shield: Int): Int =
        try {
            com.chakcaad.aethone.shield.FamilyShield.revalidate(proto, src, sport, dst, dport, name, shield)
        } catch (_: Throwable) {
            0
        }
    /// AETHONE traffic analytics (scripts/zeptun-hybrid-routing.patch, meter
    /// part): called by libzeptun-jni on the engine thread with a TCP flow's
    /// payload byte deltas (up = app → its SOCKS5 stream, down = stream →
    /// app) and the route it was really dialled on. Registered only for a
    /// routed start; must never throw.
    @JvmStatic
    fun meter(proto: Int, family: Int, src: ByteArray, sport: Int, dst: ByteArray, dport: Int, route: Int, up: Long, down: Long, closed: Boolean) {
        try {
            com.chakcaad.aethone.analytics.TrafficMeter.onMeter(proto, src, sport, dst, dport, route, up, down, closed)
        } catch (_: Throwable) {
        }
    }
    /// Family Shield: validates the snapshot; keeps it for the next start and
    /// swaps it into a running engine atomically. null clears it. Returns 0 or
    /// a zeptun error code (an invalid snapshot is refused, the previous stays).
    external fun nativeShieldSnapshot(snapshot: ByteArray?): Int
    external fun nativeShieldValidate(snapshot: ByteArray): Int
    /// Family Shield: re-check every open flow against the current policy.
    external fun nativeRevalidateFlows(): Int
    /// 0 dns_blocked, 1 flow_blocked, 2 flows_killed, 3 swaps, 4 rejected,
    /// 5 generation, 6 active; -1 when the engine is not running.
    external fun nativeShieldCounter(index: Int): Long
    external fun nativeStop()
    external fun nativeVersion(): String
    external fun nativeCounter(index: Int): Long
}
