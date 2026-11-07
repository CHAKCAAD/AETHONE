package com.chakcaad.aethone

import io.flutter.plugin.common.MethodChannel

/// Holds the `aethone/engine` MethodChannel so the VPN service (which can
/// outlive individual Flutter engine lifetimes) can push tunnel events to
/// Dart whenever an engine is attached. Everything runs on the main thread —
/// MethodChannel is not thread-safe.
object EngineBridge {
    @Volatile
    var channel: MethodChannel? = null

    fun emit(args: Map<String, Any?>) {
        channel?.invokeMethod("onTunnelEvent", args)
    }

    /// v4.41 (owner round 17, item 12) — a DIRECT method call on the
    /// engine channel (the notification's «قطع اتصال» action arrives as
    /// `onNotificationDisconnect`, exactly like the desktop tray's
    /// `onTrayToggleConnection`).
    fun invoke(method: String, args: Map<String, Any?>) {
        channel?.invokeMethod(method, args)
    }
}
