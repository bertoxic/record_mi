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

        @Volatile
        var lastCallerName: String? = null
            private set

        @Volatile
        var lastCallerTimestamp: Long = 0L
            private set

        /**
         * Returns the cached caller name if extracted within the last 30 seconds, or null.
         */
        fun getValidCallerName(): String? {
            val name = lastCallerName ?: return null
            if (System.currentTimeMillis() - lastCallerTimestamp > 30_000L) {
                lastCallerName = null
                return null
            }
            return name
        }

        fun clearCallerName() {
            lastCallerName = null
            lastCallerTimestamp = 0L
        }
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

        // Explicitly reject chat message notifications
        if (category == Notification.CATEGORY_MESSAGE) {
            return
        }

        // If any action has a RemoteInput (text reply box), it is a chat message, NOT a call
        val hasReplyAction = notification.actions?.any { action ->
            action.remoteInputs != null && action.remoteInputs.isNotEmpty()
        } == true
        if (hasReplyAction) {
            return
        }

        val isCallCategory = (category == Notification.CATEGORY_CALL)
        val hasCallActions = notification.actions?.any { action ->
            val title = action.title?.toString()?.lowercase() ?: ""
            title.contains("decline") || title.contains("answer") || title.contains("end call") || title.contains("hang up")
        } == true

        if (isCallCategory || hasCallActions) {
            val extras = notification.extras
            var title = extras?.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim()

            // Strip out common group/message prefixes if any leaked
            if (title != null && title.contains("messages):", ignoreCase = true)) {
                return
            }

            // Extract first line if multiple lines
            if (title != null && title.contains("\n")) {
                title = title.substringBefore("\n").trim()
            }

            if (!title.isNullOrEmpty() &&
                !title.equals("WhatsApp", ignoreCase = true) &&
                !title.equals("WhatsApp Call", ignoreCase = true) &&
                !title.equals("Incoming call", ignoreCase = true) &&
                !title.equals("Ongoing call", ignoreCase = true) &&
                !title.equals("Calling...", ignoreCase = true)
            ) {
                Log.i(TAG, "Detected VoIP call notification from: '$title' (pkg=$pkg)")
                lastCallerName = title
                lastCallerTimestamp = System.currentTimeMillis()
                CallRecordService.instance?.updateVoipCallerName(title)
            }
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        if (sbn == null) return
        val pkg = sbn.packageName ?: return
        if (pkg.contains("whatsapp", ignoreCase = true) || pkg.contains("telegram", ignoreCase = true)) {
            val notification = sbn.notification
            if (notification?.category == Notification.CATEGORY_CALL) {
                Log.d(TAG, "VoIP call notification removed. Clearing cached caller name.")
                clearCallerName()
            }
        }
    }
}
