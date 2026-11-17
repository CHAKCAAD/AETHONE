package com.chakcaad.aethone

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/**
 * v2.1.0 (the owner's decree, 2026-11-17: «برای بخش کنترل سنتر گوشی هم
 * ویجت اضافه کن … از آیکون و فایل های خود اپ استفاده کن») — THE HOME
 * SCREEN WIDGET.
 *
 * A compact 2×1 card in the app's own design language (the dark
 * card + the brand A-mark + the power glyph), showing the HONEST tunnel
 * state and carrying two taps:
 *
 *  * the CARD BODY opens the app (the single launch path);
 *  * the POWER BUTTON toggles like the quick-settings tile: LIVE → the
 *    service's own ACTION_DISCONNECT; IDLE → the app opens with the
 *    quick-connect flag.
 *
 * The state text mirrors the notification's own wording (connected ⇒
 * «متصل و ایمن», anything else ⇒ «غیرفعال») — never a fabricated value:
 * [AethoneVpnService.status] is the only source of truth, refreshed on
 * every widget update AND pushed by the service itself on start/stop.
 */
class AethoneWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        for (id in appWidgetIds) {
            appWidgetManager.updateAppWidget(id, build(context))
        }
    }

    companion object {
        /** Rebuilds + pushes the widget to every placed instance (the
         *  service's own start/stop notifications call this). */
        fun pushUpdate(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, AethoneWidgetProvider::class.java),
            )
            if (ids.isNotEmpty()) {
                manager.updateAppWidget(ids, build(context))
            }
        }

        private fun build(context: Context): RemoteViews {
            val running = AethoneVpnService.status()["running"] == true
            val views = RemoteViews(context.packageName, R.layout.aethone_widget)

            // The honest state.
            views.setTextViewText(
                R.id.widget_state,
                context.getString(
                    if (running) R.string.widget_state_connected
                    else R.string.widget_state_disconnected,
                ),
            )
            views.setTextColor(
                R.id.widget_state,
                context.getColor(
                    if (running) R.color.widgetAccent else R.color.widgetMuted,
                ),
            )
            views.setImageViewResource(
                R.id.widget_power,
                if (running) R.drawable.ic_widget_power else R.drawable.ic_widget_power_off,
            )

            // The card body → open the app.
            val open = PendingIntent.getActivity(
                context,
                0,
                Intent(context, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            views.setOnClickPendingIntent(R.id.widget_body, open)

            // The power button → the tile's own toggle path.
            val toggle = PendingIntent.getBroadcast(
                context,
                1,
                Intent(context, WidgetToggleReceiver::class.java)
                    .setAction(WidgetToggleReceiver.ACTION_TOGGLE),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            views.setOnClickPendingIntent(R.id.widget_power_slot, toggle)
            return views
        }
    }
}
