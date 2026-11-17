package com.chakcaad.aethone

import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

/**
 * v2.1.0 (the owner's decree, 2026-11-17: «برای بخش کنترل سنتر گوشی هم
 * ویجت اضافه کن») — THE QUICK SETTINGS TILE.
 *
 * The tile carries the app's own brand mark (ic_stat_aethone — the
 * alpha-mask A-mark the status-bar notifications already use) and the
 * honest service state:
 *
 *  * STATE_ACTIVE (the brand green) while the VPN service is LIVE —
 *    read through [AethoneVpnService.status], never guessed;
 *  * STATE_INACTIVE while it is not.
 *
 * Tap behaviour (the engine walk lives on the Flutter side, so the tile
 * never pretends to drive it directly):
 *  * RUNNING → the service's own ACTION_DISCONNECT intent (the very
 *    action the disconnect notification uses — the stop is native and
 *    immediate, no UI needed);
 *  * NOT RUNNING → launch MainActivity with the EXTRA_QUICK_CONNECT
 *    flag: the app opens and the Flutter side starts the connect walk
 *    (the store's single connect path — the tile reuses it, never
 *    invents a second engine control channel).
 */
class AethoneTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        refresh()
    }

    override fun onClick() {
        super.onClick()
        val running = AethoneVpnService.status()["running"] == true
        if (running) {
            // The disconnect notification's own path: the running
            // foreground service receives its ACTION_DISCONNECT and tears
            // the tunnel down natively.
            val stop = Intent(this, AethoneVpnService::class.java)
                .setAction(AethoneVpnService.ACTION_DISCONNECT)
            runCatching { startService(stop) }
                .onFailure {
                    // The service died between the read and the tap —
                    // fall through to the launch path; the app will show
                    // its honest disconnected state.
                    launchApp()
                }
            refresh()
        } else {
            launchApp()
        }
    }

    private fun launchApp() {
        val launch = Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            .putExtra(MainActivity.EXTRA_QUICK_CONNECT, true)
        if (Build.VERSION.SDK_INT >= 34) {
            startActivityAndCollapse(
                android.app.PendingIntent.getActivity(
                    this,
                    0,
                    launch,
                    android.app.PendingIntent.FLAG_IMMUTABLE,
                ),
            )
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(launch)
        }
    }

    private fun refresh() {
        val tile = qsTile ?: return
        val running = AethoneVpnService.status()["running"] == true
        tile.state = if (running) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.subtitle = getString(
            if (running) R.string.tile_state_connected else R.string.tile_state_disconnected,
        )
        tile.updateTile()
    }
}
