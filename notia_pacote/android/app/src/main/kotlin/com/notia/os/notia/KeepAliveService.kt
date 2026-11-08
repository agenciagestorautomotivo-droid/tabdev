package com.notia.os.notia

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Serviço em primeiro plano: mantém o OpenEXE vivo para rotinas, agente de apps e escuta por
 * palavra de ativação. Mostra uma notificação fixa (o Android exige). O tipo "microfone" permite
 * usar o microfone mesmo com outro app aberto na frente.
 */
class KeepAliveService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(
                NotificationChannel("openexe_alive", "OpenEXE ativo", NotificationManager.IMPORTANCE_LOW)
            )
        }
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val b = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, "openexe_alive")
        else Notification.Builder(this)
        val n = b.setContentTitle("OpenEXE ativo")
            .setContentText("Rotinas, agente e voz funcionando em segundo plano")
            .setSmallIcon(applicationInfo.icon)
            .setContentIntent(open)
            .setOngoing(true)
            .build()
        try {
            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(1001, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
            } else {
                startForeground(1001, n)
            }
        } catch (_: Exception) {
            stopSelf()
        }
        return START_STICKY
    }
}
