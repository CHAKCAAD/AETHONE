package com.chakcaad.aethone

import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.util.Log

/// v1.0.1 — the CONTROL-CENTER (Quick Settings) tile (owner decree:
/// «ویجت کنترل سنتر گوشی»). One honest toggle:
///  * INACTIVE → tap opens the app on its quick-connect flow (the whole
///    engine walk — core spawn, endpoint scan, TUN establish — lives in
///    the Flutter process, so the tile delegates to the app exactly like
///    the home-screen widget; the app comes to the front and connects).
///  * ACTIVE   → tap fires the SAME ACTION_DISCONNECT the connection
///    notification's «قطع اتصال» uses (startService on the LIVE holder
///    service — legal from the tile because the foreground service keeps
///    this very process above background priority), which forwards to
///    Dart when an engine answers and tears the tunnel down itself when
///    none does (the notification's 600 ms grace fallback).
///
/// State is read LIVE from the holder services whenever the shade opens
/// (onStartListening) — no cached lies after a process death — and the
/// services poke [requestRefresh] on their up/down transitions so an open
/// shade flips the tile the moment the tunnel does.
class AethoneTileService : TileService() {

    companion object {
        private const val TAG = "AethoneTile"

        private fun liveConnected(): Boolean =
            (AethoneVpnService.status()["running"] == true) ||
                (CoreHoldService.status()["running"] == true)

        /// Ask the system to re-deliver onStartListening to the tile (the
        /// documented cross-component refresh path) — called by the widget
        /// push and the services' transitions.
        fun requestRefresh(context: Context) {
            try {
                TileService.requestListeningState(
                    context,
                    ComponentName(context, AethoneTileService::class.java),
                )
            } catch (t: Throwable) {
                // Refresh only — never take a transition down with it.
                Log.w(TAG, "tile refresh request failed", t)
            }
        }
    }

    override fun onStartListening() {
        super.onStartListening()
        refresh()
    }

    override fun onClick(isLocked: Boolean) {
        super.onClick(isLocked)
        // A connect from the lock screen would open the app behind the
        // lock — and the first connect may need the VPN-consent dialog.
        // Honest no-op; unlock and tap again.
        if (isLocked) return

        if (liveConnected()) {
            disconnectNow()
        } else {
            launchQuickConnect()
        }
        refresh()
    }

    /// The notification's proven disconnect path: ACTION_DISCONNECT on the
    /// live holder (VPN first — proxy mode has no TUN to tear down).
    private fun disconnectNow() {
        val intent = if (AethoneVpnService.status()["running"] == true) {
            Intent(this, AethoneVpnService::class.java)
                .setAction(AethoneVpnService.ACTION_DISCONNECT)
        } else {
            Intent(this, CoreHoldService::class.java)
                .setAction(AethoneVpnService.ACTION_DISCONNECT)
        }
        try {
            startService(intent)
        } catch (t: Throwable) {
            Log.w(TAG, "tile disconnect startService failed", t)
        }
    }

    /// Open the app on the quick-connect flow (startActivityAndCollapse is
    /// the documented tile→activity handoff; the PendingIntent form is the
    /// Android 14+ requirement).
    private fun launchQuickConnect() {
        val intent = Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            .putExtra(MainActivity.EXTRA_QUICK_CONNECT, true)
        try {
            if (Build.VERSION.SDK_INT >= 34) {
                val pi = PendingIntent.getActivity(
                    this,
                    31,
                    intent,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                )
                startActivityAndCollapse(pi)
            } else {
                @Suppress("DEPRECATION")
                startActivityAndCollapse(intent)
            }
        } catch (t: Throwable) {
            Log.w(TAG, "tile quick-connect launch failed", t)
        }
    }

    private fun refresh() {
        val tile = qsTile ?: return
        val up = liveConnected()
        tile.state = if (up) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.subtitle = getString(
            if (up) R.string.tile_state_connected else R.string.tile_state_idle,
        )
        tile.updateTile()
    }
}
