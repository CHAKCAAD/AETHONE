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
        com.chakcaad.aethone.routing.HybridRouter.route(proto, family, src, sport, dst, dport, name)
    external fun nativeStop()
    external fun nativeVersion(): String
    external fun nativeCounter(index: Int): Long
}
