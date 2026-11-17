package com.chakcaad.aethone

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/// Stage 2 per-app routing (PoC) — the adb instrumentation receiver.
///
/// Test-only surface for driving live route updates and reading diagnostics
/// without touching the Flutter UI (Stage 3 owns the product surface):
///
///   adb shell am broadcast \
///     -a com.chakcaad.aethone.POC_UPDATE_ROUTES \
///     --es token <token> --es routes '<json>'
///   adb shell am broadcast \
///     -a com.chakcaad.aethone.POC_ROUTES_STATS --es token <token>
///
/// The `<token>` is generated per service instance and printed to logcat
/// (tag AethonePoC) when the tunnel starts with PoC routes — a
/// non-token-holder (any other app on the device) cannot change routes on a
/// debug PoC build. The receiver never starts anything by itself and only
/// acts while the tunnel is up with the flow callback installed.
class PoCRoutesReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_UPDATE = "com.chakcaad.aethone.POC_UPDATE_ROUTES"
        const val ACTION_STATS = "com.chakcaad.aethone.POC_ROUTES_STATS"
        const val EXTRA_ROUTES = "routes"
        const val EXTRA_TOKEN = "token"
        private const val TAG = "AethonePoC"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val result = when (intent.action) {
            ACTION_UPDATE -> AethoneVpnService.applyPocRoutesLive(
                intent.getStringExtra(EXTRA_ROUTES) ?: "",
                intent.getStringExtra(EXTRA_TOKEN) ?: "",
            )
            ACTION_STATS -> AethoneVpnService.dumpPocStats(intent.getStringExtra(EXTRA_TOKEN) ?: "")
            else -> "ignored unknown action ${intent.action}"
        }
        Log.i(TAG, "poc receiver: $result")
    }
}
