package com.notia.os.notia

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * Lê as notificações dos outros apps para o Notia resumir, filtrar e disparar rotinas.
 * Nada é gravado em disco: ficam só as últimas 100 na memória.
 */
class NotiaNotificationListener : NotificationListenerService() {

    companion object {
        val recent = ArrayList<Map<String, Any?>>()

        fun snapshot(limit: Int): List<Map<String, Any?>> = synchronized(recent) {
            recent.takeLast(limit)
        }

        fun clear() = synchronized(recent) { recent.clear() }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        if (sbn.packageName == packageName) return
        if (sbn.isOngoing) return
        val n = sbn.notification ?: return
        if (n.flags and Notification.FLAG_GROUP_SUMMARY != 0) return
        val ex = n.extras
        val title = ex.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val text = (ex.getCharSequence(Notification.EXTRA_BIG_TEXT)
            ?: ex.getCharSequence(Notification.EXTRA_TEXT))?.toString() ?: ""
        if (title.isBlank() && text.isBlank()) return
        val app = try {
            packageManager.getApplicationLabel(
                packageManager.getApplicationInfo(sbn.packageName, 0)
            ).toString()
        } catch (_: Exception) {
            sbn.packageName
        }
        val m = mapOf(
            "type" to "notif",
            "key" to sbn.key,
            "pkg" to sbn.packageName,
            "app" to app,
            "title" to title.take(120),
            "text" to text.take(300),
            "time" to sbn.postTime
        )
        synchronized(recent) {
            recent.add(m)
            while (recent.size > 100) recent.removeAt(0)
        }
        NotiaBridge.emit(m)
    }
}
