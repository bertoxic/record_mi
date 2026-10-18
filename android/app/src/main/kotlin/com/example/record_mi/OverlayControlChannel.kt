package com.example.record_mi

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

object OverlayControlChannel {
    private const val TAG = "OverlayControlChannel"
    const val CHANNEL = "com.example.record_mi/overlay_control"

    private val activeChannels = mutableListOf<MethodChannel>()
    private val mainHandler = Handler(Looper.getMainLooper())

    fun register(engine: FlutterEngine) {
        mainHandler.post {
            try {
                val channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
                activeChannels.add(channel)

                channel.setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
                    Log.i(TAG, "Overlay method call: ${call.method}")
                    when (call.method) {
                        "stopRecording" -> {
                            val crs = CallRecordService.instance
                            val path = crs?.stopRecording()
                            notifyStateChanged()
                            result.success(path != null || crs?.isRecording() == false)
                        }
                        "startRecording" -> {
                            val crs = CallRecordService.instance
                            if (crs != null) {
                                val isVoip = crs.isVoipActive()
                                val callType = if (isVoip) "voip:wav" else crs.getCurrentCallType()
                                val ext = if (isVoip) "wav" else crs.configuredAudioFormat.lowercase()
                                val num = crs.getCurrentPhoneNumber() ?: if (isVoip) "WhatsApp" else "manual"
                                val safeNum = num.replace(Regex("[^a-zA-Z0-9+]"), "_")
                                val fileName = "call_${crs.getCurrentCallType()}_${safeNum}_${System.currentTimeMillis()}.$ext"
                                val ok = crs.startRecording(fileName, callType, crs.configuredAudioSource)
                                notifyStateChanged()
                                result.success(ok)
                            } else {
                                result.success(false)
                            }
                        }
                        "toggleSpeaker" -> {
                            val crs = CallRecordService.instance
                            val isOn = crs?.toggleSpeakerphone() ?: false
                            notifyStateChanged()
                            result.success(isOn)
                        }
                        "closeOverlay" -> {
                            val ctx = CallRecordService.instance ?: MainActivity.instance
                            if (ctx != null) {
                                try {
                                    val intent = Intent(ctx, flutter.overlay.window.flutter_overlay_window.OverlayService::class.java)
                                    ctx.stopService(intent)
                                } catch (e: Throwable) {
                                    Log.w(TAG, "Error stopping OverlayService: ${e.message}")
                                }
                            }
                            result.success(true)
                        }
                        "getCallState" -> {
                            val crs = CallRecordService.instance
                            val isRec = crs?.isRecording() ?: false
                            val data = mapOf(
                                "isRecording" to isRec,
                                "speakerOn" to (crs?.isSpeakerphoneActive() ?: false),
                                "number" to (crs?.getCurrentPhoneNumber() ?: ""),
                                "callType" to (crs?.getCurrentCallType() ?: "cellular"),
                                "callState" to (if (isRec) "active" else (crs?.getCurrentCallType() ?: "active")),
                                "recordingStartTime" to (if (isRec) crs?.getRecordingStartTime() else null)
                            )
                            result.success(data)
                        }
                        else -> result.notImplemented()
                    }
                }
                Log.i(TAG, "Registered OverlayControlChannel on FlutterEngine")
            } catch (e: Throwable) {
                Log.e(TAG, "Failed to register OverlayControlChannel: ${e.message}")
            }
        }
    }

    fun notifyStateChanged() {
        mainHandler.post {
            val crs = CallRecordService.instance ?: return@post
            val isRec = crs.isRecording()
            val data = mapOf(
                "isRecording" to isRec,
                "speakerOn" to crs.isSpeakerphoneActive(),
                "number" to (crs.getCurrentPhoneNumber() ?: ""),
                "callType" to crs.getCurrentCallType(),
                "callState" to (if (isRec) "active" else crs.getCurrentCallType()),
                "recordingStartTime" to (if (isRec) crs.getRecordingStartTime() else null)
            )
            for (channel in activeChannels) {
                try {
                    channel.invokeMethod("onStateChanged", data)
                } catch (ignored: Throwable) {}
            }
        }
    }
}
