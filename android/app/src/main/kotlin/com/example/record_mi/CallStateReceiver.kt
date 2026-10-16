package com.example.record_mi

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.CallLog
import android.telephony.TelephonyManager
import android.util.Log

/**
 * Native BroadcastReceiver for telephony state events:
 * - android.intent.action.PHONE_STATE (RINGING, OFFHOOK, IDLE)
 * - android.intent.action.NEW_OUTGOING_CALL (Outgoing call initialization)
 *
 * Forwards all events to the persistent CallRecordService which coordinates
 * privileged audio capture, UI notification updates, and Flutter callbacks.
 */
class CallStateReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "CallStateReceiver"
        private var lastState = TelephonyManager.EXTRA_STATE_IDLE
        private var isOutgoing = false
        private var currentNumber: String? = null

        fun resolveContactNumber(context: Context, rawNumber: String?): String {
            if (!rawNumber.isNullOrBlank() && rawNumber != "Call" && rawNumber != "unknown" && rawNumber != "Conference/Call") {
                return rawNumber
            }
            // On Android 9+, EXTRA_INCOMING_NUMBER may be stripped for privacy.
            // Only read from CallLog if there is a recent call created within the last 20 seconds!
            try {
                if (context.checkSelfPermission(android.Manifest.permission.READ_CALL_LOG) == PackageManager.PERMISSION_GRANTED) {
                    val cursor = context.contentResolver.query(
                        CallLog.Calls.CONTENT_URI,
                        arrayOf(CallLog.Calls.NUMBER, CallLog.Calls.CACHED_NAME, CallLog.Calls.DATE),
                        null,
                        null,
                        "${CallLog.Calls.DATE} DESC"
                    )
                    cursor?.use {
                        if (it.moveToFirst()) {
                            val dateIdx = it.getColumnIndex(CallLog.Calls.DATE)
                            val callDate = if (dateIdx != -1) it.getLong(dateIdx) else 0L
                            val now = System.currentTimeMillis()
                            // If the call log entry is older than 20 seconds, DO NOT use it! (Prevents stale contact names like Bezap)
                            if (now - callDate < 20000L) {
                                val numIdx = it.getColumnIndex(CallLog.Calls.NUMBER)
                                val nameIdx = it.getColumnIndex(CallLog.Calls.CACHED_NAME)
                                val num = if (numIdx != -1) it.getString(numIdx) else null
                                val name = if (nameIdx != -1) it.getString(nameIdx) else null
                                if (!name.isNullOrBlank() && !num.isNullOrBlank()) {
                                    return "$name ($num)"
                                }
                                if (!num.isNullOrBlank()) {
                                    return num
                                }
                            } else {
                                Log.d(TAG, "Most recent CallLog entry is ${now - callDate}ms old; ignoring stale contact info.")
                            }
                        }
                    }
                }
            } catch (e: Throwable) {
                Log.w(TAG, "Could not resolve contact from CallLog: ${e.message}")
            }
            return rawNumber ?: "Call"
        }
    }

    private fun sendToService(context: Context, action: String, number: String? = null, callType: String? = null) {
        try {
            val intent = Intent(context, CallRecordService::class.java).apply {
                this.action = action
                if (number != null) putExtra(CallRecordService.EXTRA_PHONE_NUMBER, number)
                if (callType != null) putExtra(CallRecordService.EXTRA_CALL_TYPE, callType)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        } catch (e: Throwable) {
            Log.e(TAG, "Failed sending $action to CallRecordService: ${e.message}")
        }
    }

    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return

        // 1. Detect outgoing call initialization
        if (action == Intent.ACTION_NEW_OUTGOING_CALL || action == "android.intent.action.NEW_OUTGOING_CALL") {
            val outNumber = intent.getStringExtra(Intent.EXTRA_PHONE_NUMBER)
                ?: intent.getStringExtra("android.intent.extra.PHONE_NUMBER")
            val resolvedNum = resolveContactNumber(context, outNumber)
            Log.i(TAG, "Outgoing call initiated to: $resolvedNum")
            isOutgoing = true
            currentNumber = resolvedNum
            sendToService(context, CallRecordService.ACTION_CALL_OUTGOING, resolvedNum, "outgoing")
            return
        }

        if (action != TelephonyManager.ACTION_PHONE_STATE_CHANGED) return

        val state = intent.getStringExtra(TelephonyManager.EXTRA_STATE) ?: return
        val incomingRaw = intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER)
            ?: intent.getStringExtra("incoming_number")
        val incomingNumber = resolveContactNumber(context, incomingRaw)
        Log.i(TAG, "PhoneState broadcast: state=$state, incomingNum=$incomingNumber, isOutgoing=$isOutgoing")

        if (state == lastState) return
        val prevState = lastState
        lastState = state

        when (state) {
            TelephonyManager.EXTRA_STATE_RINGING -> {
                // Incoming call ringing
                isOutgoing = false
                currentNumber = incomingNumber
                Log.i(TAG, "Incoming call ringing from: $incomingNumber")
                sendToService(context, CallRecordService.ACTION_CALL_RINGING, incomingNumber, "incoming")
            }

            TelephonyManager.EXTRA_STATE_OFFHOOK -> {
                // Call answered or outgoing call active/dialing
                if (prevState == TelephonyManager.EXTRA_STATE_IDLE) {
                    isOutgoing = true
                }

                val num = currentNumber ?: incomingNumber
                val resolvedNum = resolveContactNumber(context, num)
                val callType = if (isOutgoing) "outgoing" else "incoming"
                Log.i(TAG, "Call answered / connected ($callType) with: $resolvedNum. Starting recording immediately!")
                sendToService(context, CallRecordService.ACTION_CALL_OFFHOOK, resolvedNum, callType)
            }

            TelephonyManager.EXTRA_STATE_IDLE -> {
                // Call terminated
                Log.i(TAG, "Call ended. Resetting state.")
                isOutgoing = false
                currentNumber = null
                sendToService(context, CallRecordService.ACTION_CALL_IDLE)
            }
        }
    }
}
