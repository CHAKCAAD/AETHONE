package com.chakcaad.aethone

/// Stage 2 per-app routing (PoC, round 4) — the device-test entry point's
/// input contract, as a PURE Kotlin object so it can be unit-tested on the
/// JVM (no android.* imports; JSON via the same org.json the service uses).
///
/// The debug-only [PoCControlActivity] receives the adb extras, maps them to
/// nullable raw values (absent vs. present-but-wrong-typed is a distinction
/// the spec reports honestly) and validates them HERE before anything is
/// started:
///
///   adb shell am start \
///     -n com.chakcaad.aethone.da/com.chakcaad.aethone.PoCControlActivity \
///     --ei port 1819 \
///     --es poc_routes '{"routes":[{"id":"engine","kind":"socks5","server":"127.0.0.1:1819"},{"id":"direct","kind":"direct"}],"assignments":{"org.mozilla.firefox":"direct"}}' \
///     [--ez tcpOnly true] [--ez socksStrict true]
///
/// `port` defaults to the service's own default (1819) when absent;
/// `poc_routes` is REQUIRED — this entry point exists only for
/// route-instrumented test starts, a plain tunnel is what the app UI does.
/// The document itself is validated by the EXISTING [PoCRoutes.parse]
/// (the same authority the service's start path and the live-update
/// broadcast use — one parser, no second opinion to drift).
object PoCControlStartSpec {

    /// Extra keys — asserted equal to AethoneVpnService.EXTRA_* by the unit
    /// tests; the activity forwards under the SERVICE's constants, these are
    /// only what the spec reads from the launch intent.
    const val EXTRA_PORT = "port"
    const val EXTRA_POC_ROUTES = "poc_routes"
    const val EXTRA_TCP_ONLY = "tcpOnly"
    const val EXTRA_SOCKS_STRICT = "socksStrict"

    /// The service's own default when the extra is absent (mirrored here so
    /// the spec can normalize; the test pins the equality).
    const val DEFAULT_PORT = 1819

    /// The exact adb component the owner launches (DA debug package id, the
    /// activity's fully-qualified class — suffix-safe by construction).
    const val ADB_COMPONENT =
        "com.chakcaad.aethone.da/com.chakcaad.aethone.PoCControlActivity"

    sealed class Spec {
        data class Valid(
            val port: Int,
            val pocRoutesJson: String,
            val routeCount: Int,
            val assignmentCount: Int,
            val tcpOnly: Boolean,
            val socksStrict: Boolean,
        ) : Spec()

        data class Invalid(val reason: String) : Spec()
    }

    /// @param rawPort null = extra absent; a present-but-wrong-typed extra is
    ///        reported by the caller as an invalid value (am --ei is typed).
    /// @param rawPocRoutes null = extra absent (rejected: required).
    fun validate(
        rawPort: Int?,
        rawPocRoutes: String?,
        rawTcpOnly: Boolean?,
        rawSocksStrict: Boolean?,
    ): Spec {
        val port = rawPort ?: DEFAULT_PORT
        if (port !in 1..65535) {
            return Spec.Invalid("port must be 1..65535, got $port")
        }
        if (rawPocRoutes.isNullOrBlank()) {
            return Spec.Invalid(
                "poc_routes extra is required (the route-start document, " +
                    "e.g. {\"routes\":[{\"id\":\"engine\",\"kind\":\"socks5\",\"server\":\"127.0.0.1:1819\"}," +
                    "{\"id\":\"direct\",\"kind\":\"direct\"}],\"assignments\":{\"<package>\":\"engine\"}})",
            )
        }
        val routes = try {
            PoCRoutes.parse(rawPocRoutes)
        } catch (e: Exception) {
            return Spec.Invalid("poc_routes document rejected: ${e.message?.take(200)}")
        }
        return Spec.Valid(
            port = port,
            pocRoutesJson = rawPocRoutes,
            routeCount = routes.routes.size,
            assignmentCount = routes.assignments.size,
            tcpOnly = rawTcpOnly ?: false,
            socksStrict = rawSocksStrict ?: false,
        )
    }
}
