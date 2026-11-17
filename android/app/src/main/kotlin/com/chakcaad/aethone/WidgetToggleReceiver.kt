package com.chakcaad.aethone

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * v2.1.0 — the widget power button's toggle path (the quick-settings
 * tile's own behaviour, one place for both): LIVE → the service's own
 * ACTION_DISCONNECT; IDLE → launch the app with the quick-connect flag.
 */
class WidgetToggleReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_TOGGLE) return
        val running = AethoneVpnService.status()["running"] == true
        if (running) {
            val stop = Intent(context, AethoneVpnService::class.java)
                .setAction(AethoneVpnService.ACTION_DISCONNECT)
            runCatching { context.startService(stop) }
            AethoneWidgetProvider.pushUpdate(context)
        } else {
            context.startActivity(
                Intent(context, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    .putExtra(MainActivity.EXTRA_QUICK_CONNECT, true),
            )
        }
    }

    companion object {
        const val ACTION_TOGGLE = "com.chakcaad.aethone.WIDGET_TOGGLE"
    }
}
