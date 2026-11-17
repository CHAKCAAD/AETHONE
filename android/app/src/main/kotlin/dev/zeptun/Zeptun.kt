package dev.zeptun

/// JNI bridge surface of the pinned zeptun engine (1.1.3 @ 08a1ab0 +
/// AETHONE Stage-2 per-app routing patch — see docs/features/per_app_routing).
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
///    `flowCallback` (Stage 2 per-app routing) additionally installs the
///    flow-owner callback: zeptun then invokes
///    `flowRoute(protocol, family, source, sourcePort, destination,
///    destinationPort)` on the SERVICE OBJECT at the first packet of every
///    new TCP connection / UDP flow (DNS queries included) and expects the
///    packed decision `(routeNumber << 2) | action` back (0 = default route,
///    action proxy). Keep it FALSE for every non-PoC start: the callback
///    must only exist when a route table is actually configured.
///  * [nativeStop] — stop + join + destroy (idempotent by bridge design).
///  * [nativeCounter] — raw ZeptunStats field by index (order:
///    0 rx_packets, 1 rx_bytes, 2 tx_packets, 3 tx_bytes, …; -1 when the
///    engine is not running). The Stage-2 route counters live at the tail:
///    38 route_asked, 39 route_assigned, 40 route_fallback,
///    41 route_direct_fake (append-only — existing indices stay valid).
///  * [nativeUpdateRoutes] — Stage 2 live route-table replacement on the
///    RUNNING engine (TUN untouched): `config` is a TOML/JSON document whose
///    `[routes]` section is parsed and validated exactly like at create
///    time; other sections are ignored. Returns 0 on success, -16
///    (ZEPTUN_ERR_CONFIG) for a malformed/rejected document — an invalid
///    update never partially replaces the active table. Existing flows keep
///    their handlers; new flows re-resolve.
///
/// One engine per process (upstream rule — matches the Aether discipline).
object Zeptun {
    init {
        System.loadLibrary("zeptun-jni")
    }

    external fun nativeStart(
        service: Any?,
        fd: Int,
        config: String?,
        flowCallback: Boolean,
    ): Int

    external fun nativeStop()

    external fun nativeVersion(): String

    external fun nativeCounter(index: Int): Long

    external fun nativeUpdateRoutes(config: String): Int
}
