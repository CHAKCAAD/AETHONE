package com.chakcaad.aethone

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat

/// v4.19 (owner device test #7: «وقتی از اپ خارج میشم اتصال پروکسی هم حتی
/// قطع میشه») — the PROXY-mode process hold.
///
/// The Aether core runs IN-PROCESS (dart:ffi, architecture B+), so in
/// proxy mode there was nothing keeping the process alive once the user
/// swiped the app away — Android reaped it and the connection died. This
/// tiny foreground service pins the process for the duration of a proxy
/// session (started by PlatformEngineAdapter right after the core job
/// starts, stopped on disconnect). It owns NOTHING about the core: if the
/// process dies anyway (OEM killer), the tunnel dies with it — the honest
/// failure discipline of the M2 layer is unchanged.
///
/// START_NOT_STICKY on purpose, same as AethoneVpnService: a sticky
/// restart would hold a process whose core no longer exists — a silent
/// lie. The FGS type is specialUse with subtype "core-holder" (the same
/// honest type discipline as the VPN service on Android 14+).
class CoreHoldService : Service() {

    companion object {
        private const val TAG = "AethoneCoreHold"
        private const val CHANNEL_ID = "aethone_core"
        private const val NOTIFICATION_ID = 2
        const val EXTRA_PORT = "port"

        @Volatile
        private var instance: CoreHoldService? = null
        @Volatile
        private var heldPort: Int = 1819

        fun status(): Map<String, Any?> {
            val svc = instance ?: return mapOf("running" to false, "port" to null)
            return mapOf("running" to true, "port" to svc.heldPort)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        heldPort = intent?.getIntExtra(EXTRA_PORT, 1819) ?: 1819
        startForegroundCompat()
        instance = this
        // The core lives in the app process — there is nothing to do here
        // beyond existing in the foreground.
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        instance = null
        super.onDestroy()
    }

    private fun startForegroundCompat() {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    getString(R.string.core_channel_name),
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
        }
        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(getString(R.string.core_notification_title))
            .setContentText(getString(R.string.core_notification_text))
            .setOngoing(true)
            .setContentIntent(contentIntent)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ServiceCompat.startForeground(
                this,
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }
}
