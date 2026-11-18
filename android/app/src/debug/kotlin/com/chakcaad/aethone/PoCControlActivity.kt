package com.chakcaad.aethone

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log

/// Stage 2 per-app routing (PoC, round 4) — the DEBUG-ONLY device-test entry
/// point. Lives in the `debug` source set and is declared ONLY in
/// `src/debug/AndroidManifest.xml`, so the release/profile (production)
/// variants neither contain the class nor any component that could start a
/// test tunnel.
///
/// WHY it exists: `AethoneVpnService` is (and stays) `exported=false` — an
/// external `adb shell am start-foreground-service` on it is a permission
/// denial, and `PoCRoutesReceiver` only drives LIVE updates/stats on an
/// already-running PoC tunnel. The device procedure therefore starts the PoC
/// session HERE, from the application's own UID:
///
///   adb shell am start -n \
///     com.chakcaad.aethone.da/com.chakcaad.aethone.PoCControlActivity \
///     --ei port 1819 --es poc_routes '<route-start document>' \
///     [--ez tcpOnly true] [--ez socksStrict true]
///
/// (optionally `am start -W …` — the activity sets its result: ok = start
/// delivered, canceled = rejected before any start, with the reason on
/// logcat tag `AethonePoC`).
///
/// Behavior contract (task round 4):
///  * validates `port` / `poc_routes` (+ optional `tcpOnly` / `socksStrict`)
///    via [PoCControlStartSpec] — the SAME [PoCRoutes.parse] authority the
///    service start path and the update broadcast use;
///  * refuses to start unless the VPN consent is ALREADY granted
///    (`VpnService.prepare` == null) — it never raises the consent dialog
///    itself; grant it once through the app UI, then test;
///  * starts `AethoneVpnService` with exactly the documented extras
///    (`port`, `tcpOnly`, `socksStrict`, `poc_routes`); no session stamp and
///    no per-app tunneling pick — an external start, precisely like the
///    old (broken) adb command intended;
///  * touches NO routing logic: the service's own start path decides
///    already-running/restart semantics as for any other start;
///  * logs the actual start result and the live PoC token under the
///    existing `AethonePoC` tag (the token read is in-process only —
///    [AethoneVpnService.currentPocToken], same process/UID, no IPC
///    surface; the receiver's token guard is untouched).
///
/// The activity is translucent and content-less: `am start` puts the process
/// in the foreground (an FGS start is legal), it reports, then finishes.
class PoCControlActivity : Activity() {

    companion object {
        private const val TAG = "AethonePoC"

        /// Token poll: the service issues the token in onCreate — a short
        /// bounded wait (150 ms × 20 = 3 s max) covers process start; the
        /// service's own `AethonePoC` line carries it regardless.
        private const val TOKEN_POLL_MS = 150L
        private const val TOKEN_POLL_MAX = 20
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // 1. Validate the launch document BEFORE anything else (the honest
        //    failure: the tunnel never comes up half-configured).
        val spec = PoCControlStartSpec.validate(
            rawPort = intExtraOrAbsent(PoCControlStartSpec.EXTRA_PORT),
            rawPocRoutes = stringExtraOrAbsent(PoCControlStartSpec.EXTRA_POC_ROUTES),
            rawTcpOnly = boolExtraOrAbsent(PoCControlStartSpec.EXTRA_TCP_ONLY),
            rawSocksStrict = boolExtraOrAbsent(PoCControlStartSpec.EXTRA_SOCKS_STRICT),
        )
        val valid = when (spec) {
            is PoCControlStartSpec.Spec.Invalid -> {
                Log.e(
                    TAG,
                    "poc-control: REJECTED — ${spec.reason} | usage: adb shell am start -n " +
                        "${PoCControlStartSpec.ADB_COMPONENT} --ei port 1819 " +
                        "--es poc_routes '<json>' [--ez tcpOnly true] [--ez socksStrict true]",
                )
                setResult(RESULT_CANCELED)
                finish()
                return
            }
            is PoCControlStartSpec.Spec.Valid -> spec
        }

        // 2. VPN consent must ALREADY be granted (the app UI's own connect
        //    flow granted it; this entry point never shows the dialog — a
        //    headless adb start must not depend on a UI race).
        val consentIntent = VpnService.prepare(this)
        if (consentIntent != null) {
            Log.e(
                TAG,
                "poc-control: REJECTED — VPN consent NOT granted yet: open the AETHONE DA " +
                    "app once, connect and accept the VPN dialog, then re-run this adb start. " +
                    "Service NOT started.",
            )
            setResult(RESULT_CANCELED)
            finish()
            return
        }

        // 3. Start the service from the application's own UID, forwarding
        //    exactly the documented extras (session/appMode/apps stay absent
        //    — an external start, like the adb command this replaces).
        val start = Intent(this, AethoneVpnService::class.java)
            .putExtra(AethoneVpnService.EXTRA_PORT, valid.port)
            .putExtra(AethoneVpnService.EXTRA_TCP_ONLY, valid.tcpOnly)
            .putExtra(AethoneVpnService.EXTRA_SOCKS_STRICT, valid.socksStrict)
            .putExtra(AethoneVpnService.EXTRA_POC_ROUTES, valid.pocRoutesJson)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(start)
            } else {
                startService(start)
            }
        } catch (t: Throwable) {
            Log.e(TAG, "poc-control: service start FAILED — ${t.javaClass.simpleName}: ${t.message}")
            setResult(RESULT_CANCELED)
            finish()
            return
        }
        Log.i(
            TAG,
            "poc-control: start delivered to AethoneVpnService (port=${valid.port} " +
                "tcpOnly=${valid.tcpOnly} socksStrict=${valid.socksStrict} " +
                "poc_routes=${valid.routeCount} route(s)/${valid.assignmentCount} assignment(s)) " +
                "— awaiting the service's own start result on this tag",
        )
        setResult(RESULT_OK)

        // 4. Report the live PoC token under this tag (the owner's next
        //    step — POC_UPDATE_ROUTES / POC_ROUTES_STATS — needs it).
        pollTokenAndFinish(0)
    }

    /// null = extra absent; a present-but-wrong-typed extra surfaces as the
    /// type reader's sentry (am's --ei/--es/--ez are typed, so this only
    /// fires on a hand-built intent).
    private fun intExtraOrAbsent(key: String): Int? =
        if (intent.hasExtra(key)) intent.getIntExtra(key, -1) else null

    private fun stringExtraOrAbsent(key: String): String? =
        if (intent.hasExtra(key)) intent.getStringExtra(key) else null

    private fun boolExtraOrAbsent(key: String): Boolean? =
        if (intent.hasExtra(key)) intent.getBooleanExtra(key, false) else null

    private fun pollTokenAndFinish(attempt: Int) {
        Handler(Looper.getMainLooper()).postDelayed(
            {
                val token = AethoneVpnService.currentPocToken()
                if (token.isNotEmpty()) {
                    val status = AethoneVpnService.status()
                    Log.i(
                        TAG,
                        "poc-control: PoC tunnel session armed — token=$token " +
                            "(service running=${status["running"]} port=${status["port"]}) | " +
                            "live update: adb shell am broadcast -a " +
                            "com.chakcaad.aethone.POC_UPDATE_ROUTES --es token $token " +
                            "--es routes '<json>' | stats: adb shell am broadcast -a " +
                            "com.chakcaad.aethone.POC_ROUTES_STATS --es token $token",
                    )
                    finish()
                } else if (attempt >= TOKEN_POLL_MAX) {
                    Log.w(
                        TAG,
                        "poc-control: token not issued within ${TOKEN_POLL_MAX * TOKEN_POLL_MS} ms " +
                            "(service still starting or start refused — the service's own " +
                            "AethonePoC/AethoneVpn lines carry the verdict)",
                    )
                    finish()
                } else {
                    pollTokenAndFinish(attempt + 1)
                }
            },
            TOKEN_POLL_MS,
        )
    }
}
