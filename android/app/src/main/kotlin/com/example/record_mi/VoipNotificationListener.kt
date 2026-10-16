package com.example.record_mi

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log

/**
 * NotificationListenerService that intercepts WhatsApp and VoIP incoming/active call notifications
 * to extract the real contact/caller name and pass it to CallRecordService.
 */
class VoipNotificationListener : NotificationListenerService() {

    companion object {
        private const val TAG = "VoipNotifListener"
        var lastCallerName: String? = null
            private set
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        Log.i(TAG, "VoipNotificationListener connected successfully")
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        val pkg = sbn.packageName ?: return

        val isWhatsApp = pkg.contains("whatsapp", ignoreCase = true)
        val isTelegram = pkg.contains("telegram", ignoreCase = true)

        if (!isWhatsApp && !isTelegram) return

        val notification = sbn.notification ?: return
        val category = notification.category
        val isCallCategory = category == Notification.CATEGORY_CALL

        val hasCallActions = notification.actions?.any { action ->
            val title = action.title?.toString()?.lowercase() ?: ""
            title.contains("decline") || title.contains("answer") || title.contains("end") || title.contains("mute")
        } == true

        if (isCallCategory || hasCallActions) {
            val extras = notification.extras
            val title = extras?.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim()

            if (!title.isNullOrEmpty() &&
                !title.equals("WhatsApp", ignoreCase = true) &&
                !title.equals("WhatsApp Call", ignoreCase = true) &&
                !title.equals("Incoming call", ignoreCase = true) &&
                !title.equals("Ongoing call", ignoreCase = true)
            ) {
                Log.i(TAG, "Detected VoIP caller from notification: '$title' (pkg=$pkg)")
                lastCallerName = title
                CallRecordService.instance?.updateVoipCallerName(title)
            }
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        // Ignored
    }
}
