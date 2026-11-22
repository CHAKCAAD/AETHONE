package com.chakcaad.aethone

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/// v1.0.1 — the PHONE HOME-SCREEN widget (owner decree: «ویجت صفحه اصلی» —
/// the launcher, not the in-app home page). A brand-dark 4x2 card with the
/// A-mark, a live status line and one big action:
///  * idle      → «اتصال» taps launch the app's quick-connect flow (the
///                whole engine walk — core spawn, endpoint scan, TUN —
///                lives in the Flutter process, so the tap OPENS the app
///                and connects, exactly like pressing the in-app button);
///  * connected → «قطع اتصال» taps the SAME battle-tested path as the
///                connection notification's action (ACTION_DISCONNECT on
///                the live holder service, with its own no-engine
///                fallback);
///  * connecting — shown while the Dart walk runs (pushed over the
///                aethone/engine channel's `widgetState`).
///
/// State truth: the holder services push on their lifecycle (up/down/
/// destroy) and Dart pushes the transient phases; the tile keeps its own
/// live read. All pushes funnel through [pushNamed] so the last honest
/// writer wins.
class AethoneHomeWidget : AppWidgetProvider() {

    companion object {
        /// The named states the pushers agree on (MainActivity's channel
        /// passes the same strings from Dart; the services use the
        /// constants directly).
        const val STATE_IDLE = "idle"
        const val STATE_CONNECTING = "connecting"
        const val STATE_CONNECTED = "connected"

        /// The live holder truth (both modes) — used by [syncFromServices].
        private fun liveConnected(): Boolean =
            (AethoneVpnService.status()["running"] == true) ||
                (CoreHoldService.status()["running"] == true)

        /// Push a named state to every placed widget; a service-up push
        /// overrides a stale Dart phase and vice versa (last write wins).
        fun pushNamed(context: Context, state: String) {
            // The Quick-Settings tile rides the SAME push (it re-reads on
            // its own onStartListening; this covers the open-shade case).
            AethoneTileService.requestRefresh(context)
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, AethoneHomeWidget::class.java),
            )
            if (ids.isEmpty()) return
            manager.updateAppWidget(ids, build(context, state))
        }

        /// Reconcile with the LIVE services (app cold start, widget
        /// onUpdate): a process death while connected left the widget
        /// stale — this flips it back to the truth.
        fun syncFromServices(context: Context) {
            pushNamed(
                context,
                if (liveConnected()) STATE_CONNECTED else STATE_IDLE,
            )
        }

        private fun build(context: Context, state: String): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.aethone_home_widget)
            val res = context.resources

            // -- the status line + dot.
            val statusText: String
            val dotRes: Int
            when (state) {
                STATE_CONNECTED -> {
                    statusText = res.getString(R.string.widget_status_connected)
                    dotRes = R.drawable.widget_dot_on
                }
                STATE_CONNECTING -> {
                    statusText = res.getString(R.string.widget_status_connecting)
                    dotRes = R.drawable.widget_dot_connecting
                }
                else -> {
                    statusText = res.getString(R.string.widget_status_idle)
                    dotRes = R.drawable.widget_dot_off
                }
            }
            views.setTextViewText(R.id.widget_status, statusText)
            views.setImageViewResource(R.id.widget_dot, dotRes)

            // -- the action button: connect (launch + quick connect) or
            //    disconnect (the notification's proven path).
            val flags = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            if (state == STATE_CONNECTED) {
                views.setTextViewText(
                    R.id.widget_action,
                    res.getString(R.string.widget_action_disconnect),
                )
                views.setTextColor(R.id.widget_action, 0xFFEA2323.toInt())
                views.setInt(
                    R.id.widget_action,
                    "setBackgroundResource",
                    R.drawable.widget_btn_disconnect,
                )
                // The VPN holder wins when both somehow answer; proxy mode
                // has no TUN, only the core-hold service.
                val target = if (AethoneVpnService.status()["running"] == true) {
                    Intent(context, AethoneVpnService::class.java)
                        .setAction(AethoneVpnService.ACTION_DISCONNECT)
                } else {
                    Intent(context, CoreHoldService::class.java)
                        .setAction(AethoneVpnService.ACTION_DISCONNECT)
                }
                views.setOnClickPendingIntent(
                    R.id.widget_action,
                    PendingIntent.getService(context, 21, target, flags),
                )
            } else {
                views.setTextViewText(
                    R.id.widget_action,
                    res.getString(R.string.widget_action_connect),
                )
                views.setTextColor(R.id.widget_action, 0xFF04150E.toInt())
                views.setInt(
                    R.id.widget_action,
                    "setBackgroundResource",
                    R.drawable.widget_btn_connect,
                )
                views.setOnClickPendingIntent(
                    R.id.widget_action,
                    PendingIntent.getActivity(
                        context,
                        22,
                        Intent(context, MainActivity::class.java)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            .putExtra(MainActivity.EXTRA_QUICK_CONNECT, true),
                        flags,
                    ),
                )
            }

            // -- the whole card opens the app.
            views.setOnClickPendingIntent(
                R.id.widget_root,
                PendingIntent.getActivity(
                    context,
                    20,
                    Intent(context, MainActivity::class.java)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                ),
            )
            return views
        }
    }

    override fun onUpdate(
        context: Context,
        manager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        // A (re)placed widget renders the LIVE truth, not a stale phase.
        val views = build(context, if (liveConnected()) STATE_CONNECTED else STATE_IDLE)
        manager.updateAppWidget(appWidgetIds, views)
    }
}
