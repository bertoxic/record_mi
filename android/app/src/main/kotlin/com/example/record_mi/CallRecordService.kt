package com.example.record_mi

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.media.AudioDeviceInfo
import android.media.AudioRecordingConfiguration
import android.media.AudioManager
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.core.app.NotificationCompat
import rikka.shizuku.Shizuku
import java.io.File

/**
 * Persistent Foreground Service that manages privileged audio capture via Shizuku (UID 2000).
 *
 * Runs continuously in the background as the single source of truth for:
 * - Call lifecycle (incoming, outgoing, connected, ended for cellular and VoIP)
 * - Privileged Shizuku UserService lifecycle and recording state
 * - Audio route management (speakerphone boost)
 */
class CallRecordService : Service() {

    companion object {
        private const val TAG = "CallRecordService"
        private const val NOTIFICATION_ID = 9901
        private const val CHANNEL_ID = "record_mi_foreground_channel"

        const val ACTION_START_SERVICE = "com.example.record_mi.START_SERVICE"
        const val ACTION_CALL_OUTGOING = "com.example.record_mi.CALL_OUTGOING"
        const val ACTION_CALL_RINGING = "com.example.record_mi.CALL_RINGING"
        const val ACTION_CALL_OFFHOOK = "com.example.record_mi.CALL_OFFHOOK"
        const val ACTION_CALL_IDLE = "com.example.record_mi.CALL_IDLE"
        const val ACTION_START_RECORD = "com.example.record_mi.START_RECORD"
        const val ACTION_STOP_RECORD = "com.example.record_mi.STOP_RECORD"
        const val ACTION_TOGGLE_SPEAKER = "com.example.record_mi.TOGGLE_SPEAKER"

        const val EXTRA_PHONE_NUMBER = "extra_phone_number"
        const val EXTRA_CALL_TYPE = "extra_call_type"
        const val EXTRA_FILE_NAME = "extra_file_name"
        const val EXTRA_AUDIO_SOURCE = "extra_audio_source"

        var instance: CallRecordService? = null
            private set
    }

    private var recorderService: ICallRecorderService? = null
    private var currentPfd: ParcelFileDescriptor? = null
    private var currentFilePath: String? = null
    private var isBound = false

    private val mainHandler = Handler(Looper.getMainLooper())
    var isAutoRecordEnabled: Boolean = true
    var isAutoSpeakerphone: Boolean = false
    var isVoipRecordingEnabled: Boolean = true
    var isVoipAutoSpeakerphone: Boolean = true
    var configuredAudioFormat: String = "m4a"
    var configuredAudioSource: Int = -1
    private var originalVoiceCallVolume: Int = -1
    private var isVoipCallActive = false
    private var isTelephonyCallActive = false
    private var isSpeakerActive = false
    private var currentPhoneNumber: String? = null
    private var currentCallType: String = "cellular"
    private var voipConnectRunnable: Runnable? = null
    private var audioRecordingCallback: AudioManager.AudioRecordingCallback? = null

    private val voipModeCheckerRunnable = object : Runnable {
        override fun run() {
            if (!isVoipCallActive) return
            val audioManager = getSystemService(AUDIO_SERVICE) as? AudioManager
            if (audioManager != null) {
                if (audioManager.mode != AudioManager.MODE_IN_COMMUNICATION) {
                    Log.i(TAG, "VoIP mode checker: mode is ${audioManager.mode} (no longer IN_COMMUNICATION). Ending call.")
                    onCallEnded()
                    return
                }
            }
            if (isVoipCallActive) {
                mainHandler.postDelayed(this, 1200)
            }
        }
    }

    private val binderReceivedListener = Shizuku.OnBinderReceivedListener {
        Log.i(TAG, "Shizuku server binder received in CallRecordService sticky listener.")
        checkAndBindService()
    }

    private val binderDeadListener = Shizuku.OnBinderDeadListener {
        Log.w(TAG, "Shizuku server binder died.")
        recorderService = null
        isBound = false
        MainActivity.instance?.onServiceStatusChanged(false)
    }

    private val userServiceArgs by lazy {
        val isDebug = (applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0
        val vCode = try {
            val pInfo = packageManager.getPackageInfo(packageName, 0)
            (pInfo.lastUpdateTime and 0x7FFFFFFF).toInt()
        } catch (e: Throwable) {
            10
        }
        Shizuku.UserServiceArgs(ComponentName(packageName, CallRecorderUserService::class.java.name))
            .daemon(true)
            .processNameSuffix("call_recorder_service")
            .debuggable(isDebug)
            .version(vCode)
    }

    private val deathRecipient = IBinder.DeathRecipient {
        Log.w(TAG, "Privileged CallRecorderUserService binder died. Auto-reconnecting in 1s...")
        recorderService = null
        isBound = false
        mainHandler.postDelayed({ checkAndBindService() }, 1000)
    }

    private val serviceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
            Log.i(TAG, "Privileged CallRecorderUserService connected successfully in CallRecordService")
            if (binder != null && binder.pingBinder()) {
                recorderService = ICallRecorderService.Stub.asInterface(binder)
                isBound = true
                try {
                    binder.linkToDeath(deathRecipient, 0)
                } catch (e: Exception) {
                    Log.w(TAG, "Failed linking death recipient: ${e.message}")
                }

                // If daemon was left in recording state from an unclosed session, reset it to idle!
                if (currentFilePath == null && try { recorderService?.isRecording == true } catch (e: Throwable) { false }) {
                    Log.w(TAG, "Shizuku daemon was recording with no active local session. Resetting daemon to idle.")
                    try { recorderService?.stopRecording() } catch (ignored: Throwable) {}
                }

                MainActivity.instance?.onServiceStatusChanged(true)
            }
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            Log.w(TAG, "Privileged CallRecorderUserService disconnected. Reconnecting...")
            recorderService = null
            isBound = false
            MainActivity.instance?.onServiceStatusChanged(false)
            mainHandler.postDelayed({ checkAndBindService() }, 1000)
        }
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        Log.i(TAG, "CallRecordService onCreate")
        createNotificationChannel()
        startForegroundNotification("Call monitoring active")
        setupVoipCallDetection()

        try {
            Shizuku.addBinderReceivedListenerSticky(binderReceivedListener)
            Shizuku.addBinderDeadListener(binderDeadListener)
        } catch (e: Throwable) {
            Log.w(TAG, "Could not add Shizuku binder listener: ${e.message}")
        }

        checkAndBindService()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Call Recorder Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Background call monitoring and audio capture"
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }
    }

    private fun startForegroundNotification(statusText: String) {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = if (launchIntent != null) {
            PendingIntent.getActivity(
                this,
                0,
                launchIntent,
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
            )
        } else null

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("RecordMi Call Recorder")
            .setContentText(statusText)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            try {
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
            } catch (e: Throwable) {
                Log.w(TAG, "startForeground with SPECIAL_USE failed: ${e.message}, falling back")
                startForeground(NOTIFICATION_ID, notification)
            }
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    fun updateNotificationText(text: String) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = if (launchIntent != null) {
            PendingIntent.getActivity(
                this,
                0,
                launchIntent,
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
            )
        } else null

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("RecordMi Call Recorder")
            .setContentText(text)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

        manager?.notify(NOTIFICATION_ID, notification)
    }

    private fun setupVoipCallDetection() {
        try {
            val audioManager = getSystemService(AUDIO_SERVICE) as? AudioManager ?: return

            // 1. AudioRecordingCallback: Secondary trigger for VoIP capture start (never used for disconnect)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                try {
                    audioRecordingCallback = object : AudioManager.AudioRecordingCallback() {
                        override fun onRecordingConfigChanged(configs: List<AudioRecordingConfiguration>?) {
                            super.onRecordingConfigChanged(configs)
                            // Crucial safeguard: NEVER trigger VoIP recording if a cellular call is active or ringing!
                            if (isTelephonyCallActive) {
                                return
                            }

                            val hasVoiceComm = configs?.any { cfg ->
                                cfg.clientAudioSource == MediaRecorder.AudioSource.VOICE_COMMUNICATION
                            } ?: false

                            if (hasVoiceComm && !isRecording() && isVoipRecordingEnabled) {
                                val currentMode = audioManager.mode
                                if (currentMode == AudioManager.MODE_IN_COMMUNICATION) {
                                    Log.i(TAG, "VoIP microphone capture detected (WhatsApp) while IN_COMMUNICATION. Starting recording.")
                                    val caller = VoipNotificationListener.getValidCallerName() ?: "WhatsApp Call"
                                    currentPhoneNumber = caller
                                    currentCallType = "voip"
                                    if (isVoipAutoSpeakerphone) {
                                        setSpeakerphone(true)
                                    }
                                    mainHandler.removeCallbacks(voipModeCheckerRunnable)
                                    mainHandler.postDelayed(voipModeCheckerRunnable, 2000)
                                    onCallConnected(caller, "voip")
                                }
                            }
                        }
                    }
                    audioManager.registerAudioRecordingCallback(audioRecordingCallback!!, mainHandler)
                } catch (e: Throwable) {
                    Log.w(TAG, "Failed registering AudioRecordingCallback: ${e.message}")
                }
            }

            // 2. OnModeChangedListener: Primary authoritative detector for VoIP call lifecycle
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                audioManager.addOnModeChangedListener(
                    mainExecutor,
                    AudioManager.OnModeChangedListener { mode ->
                        Log.i(TAG, "AudioManager mode changed: $mode (telephonyActive=$isTelephonyCallActive, voipActive=$isVoipCallActive)")
                        if (mode == AudioManager.MODE_IN_COMMUNICATION) {
                            if (isTelephonyCallActive) {
                                Log.d(TAG, "Mode is IN_COMMUNICATION but telephony call is active. Skipping VoIP handling.")
                                return@OnModeChangedListener
                            }
                            if (!isVoipRecordingEnabled) {
                                Log.i(TAG, "VoIP call detected but VoIP recording is disabled in settings. Skipping recording.")
                                return@OnModeChangedListener
                            }
                            if (!isVoipCallActive) {
                                isVoipCallActive = true
                                val caller = VoipNotificationListener.getValidCallerName() ?: "WhatsApp Call"
                                currentPhoneNumber = caller
                                currentCallType = "voip"
                                Log.i(TAG, "VoIP call connected ($caller). Starting recording...")
                                if (isVoipAutoSpeakerphone) {
                                    setSpeakerphone(true)
                                }
                                onCallConnected(caller, "voip")

                                mainHandler.removeCallbacks(voipModeCheckerRunnable)
                                mainHandler.postDelayed(voipModeCheckerRunnable, 2000)
                            }
                        } else {
                            // Any mode transition away from MODE_IN_COMMUNICATION indicates the VoIP call ended!
                            if (isVoipCallActive) {
                                Log.i(TAG, "VoIP call ended (mode changed from IN_COMMUNICATION to $mode). Stopping recording!")
                                isVoipCallActive = false
                                mainHandler.removeCallbacks(voipModeCheckerRunnable)
                                onCallEnded()
                            }
                        }
                    }
                )
            }
        } catch (e: Throwable) {
            Log.w(TAG, "Error setting up VoIP call detection: ${e.message}")
        }
    }

    fun checkAndBindService(): Boolean {
        return try {
            if (!Shizuku.pingBinder()) {
                Log.w(TAG, "Shizuku pingBinder failed")
                return false
            }
            if (Shizuku.checkSelfPermission() != PackageManager.PERMISSION_GRANTED) {
                Log.w(TAG, "Shizuku permission not granted")
                return false
            }
            if (isBound && recorderService != null && try { recorderService?.asBinder()?.isBinderAlive == true } catch (e: Throwable) { false }) {
                return true
            }
            Log.i(TAG, "Binding Shizuku UserService in CallRecordService...")
            Shizuku.bindUserService(userServiceArgs, serviceConnection)
            true
        } catch (e: Throwable) {
            Log.e(TAG, "checkAndBindService error: ${e.message}")
            false
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: ACTION_START_SERVICE
        Log.i(TAG, "onStartCommand: action=$action")

        when (action) {
            ACTION_START_SERVICE -> {
                checkAndBindService()
            }
            ACTION_CALL_OUTGOING -> {
                val number = intent?.getStringExtra(EXTRA_PHONE_NUMBER) ?: "Outgoing Call"
                onCallOutgoing(number)
            }
            ACTION_CALL_RINGING -> {
                val number = intent?.getStringExtra(EXTRA_PHONE_NUMBER) ?: "Incoming Call"
                val type = intent?.getStringExtra(EXTRA_CALL_TYPE) ?: "incoming"
                onCallRinging(number, type)
            }
            ACTION_CALL_OFFHOOK -> {
                val number = intent?.getStringExtra(EXTRA_PHONE_NUMBER) ?: "Call"
                val type = intent?.getStringExtra(EXTRA_CALL_TYPE) ?: "cellular"
                onCallConnected(number, type)
            }
            ACTION_CALL_IDLE -> {
                onCallEnded()
            }
            ACTION_START_RECORD -> {
                val fileName = intent?.getStringExtra(EXTRA_FILE_NAME) ?: "call_${System.currentTimeMillis()}.m4a"
                val callType = intent?.getStringExtra(EXTRA_CALL_TYPE) ?: "manual"
                val source = intent?.getIntExtra(EXTRA_AUDIO_SOURCE, -1) ?: -1
                startRecording(fileName, callType, source)
            }
            ACTION_STOP_RECORD -> {
                stopRecording()
            }
            ACTION_TOGGLE_SPEAKER -> {
                toggleSpeakerphone()
            }
        }

        return START_STICKY
    }

    fun onCallOutgoing(number: String) {
        currentPhoneNumber = number
        currentCallType = "outgoing"
        isTelephonyCallActive = true
        updateNotificationText("Calling: $number")
        MainActivity.instance?.onNativeCallOutgoing(number)
    }

    fun onCallRinging(number: String, callType: String = "incoming") {
        currentPhoneNumber = number
        currentCallType = callType
        if (callType != "voip") {
            isTelephonyCallActive = true
        }
        updateNotificationText("Ringing: $number")
        MainActivity.instance?.onNativeCallRinging(number, callType)
    }

    fun onCallConnected(number: String, callType: String) {
        currentPhoneNumber = number
        currentCallType = callType

        // Safety guarantee: If a previous recording was still lingering or never closed, finalize it first!
        if (isRecording() || currentFilePath != null) {
            Log.w(TAG, "onCallConnected: previous session still active (${currentFilePath}). Finalizing it before starting new recording.")
            stopRecording()
            try { Thread.sleep(150) } catch (ignored: Throwable) {}
        }

        if (callType != "voip") {
            isTelephonyCallActive = true
            if (isAutoSpeakerphone) {
                setSpeakerphone(true)
            }
        } else {
            isVoipCallActive = true
            if (isVoipAutoSpeakerphone) {
                setSpeakerphone(true)
                // Schedule re-assertions in case WhatsApp resets the communication route upon call connect
                for (delay in listOf(200L, 600L, 1200L, 2500L)) {
                    mainHandler.postDelayed({
                        if (isVoipCallActive && isVoipAutoSpeakerphone) {
                            Log.d(TAG, "Re-asserting speakerphone for VoIP call (delay: ${delay}ms)")
                            setSpeakerphone(true)
                        }
                    }, delay)
                }
            }
        }

        // If user disabled autoRecord in settings and this isn't a manual trigger, skip auto recording
        if (!isAutoRecordEnabled && callType != "manual") {
            Log.i(TAG, "Call connected ($callType) with $number, but autoRecord is disabled in settings. Skipping auto-start.")
            updateNotificationText("Call connected: $number")
            MainActivity.instance?.onNativeCallStarted(number, callType, "", false)
            return
        }

        val safeNumber = number.replace(Regex("[^a-zA-Z0-9+]"), "_")
        // For VoIP calls (WhatsApp), force WAV (raw PCM with real-time dynamic auto-gain)
        // to bypass Qualcomm AAC hardware noise gating and amplify the remote caller (+10 dB)!
        val ext = if (callType == "voip") {
            "wav"
        } else {
            when (configuredAudioFormat.lowercase()) {
                "wav" -> "wav"
                "3gp" -> "3gp"
                else -> "m4a"
            }
        }
        val fileName = "call_${callType}_${safeNumber}_${System.currentTimeMillis()}.$ext"
        Log.i(TAG, "Call connected ($callType) with $number. Starting recording to: $fileName (source=$configuredAudioSource)")
        updateNotificationText("Recording: $number")

        val started = startRecording(fileName, "$callType:$ext", configuredAudioSource)
        MainActivity.instance?.onNativeCallStarted(number, callType, fileName, started)
    }

    fun updateVoipCallerName(name: String) {
        if (!isVoipCallActive) {
            Log.d(TAG, "updateVoipCallerName called with '$name' but VoIP call is not active. Ignored.")
            return
        }
        if (name.isBlank() || name.equals("WhatsApp", ignoreCase = true) || name.equals("WhatsApp Call", ignoreCase = true)) return
        Log.i(TAG, "updateVoipCallerName: caller name updated to '$name'")
        currentPhoneNumber = name
        updateNotificationText("WhatsApp: $name")

        // Rename recording file if currently recording with generic WhatsApp_Call name
        try {
            val curPath = currentFilePath
            if (curPath != null && isRecording()) {
                val curFile = File(curPath)
                if (curFile.exists() && curFile.name.contains("WhatsApp_Call")) {
                    val safeName = name.replace(Regex("[^a-zA-Z0-9+]"), "_")
                    val newName = curFile.name.replace("WhatsApp_Call", safeName)
                    val newFile = File(curFile.parentFile, newName)
                    if (curFile.renameTo(newFile)) {
                        currentFilePath = newFile.absolutePath
                        Log.i(TAG, "Renamed active VoIP recording file to: ${newFile.name}")
                    }
                }
            }
        } catch (e: Throwable) {
            Log.w(TAG, "Failed renaming active VoIP recording: ${e.message}")
        }

        MainActivity.instance?.onNativeCallStarted(name, "voip", currentFilePath ?: "", isRecording())
    }

    fun onCallEnded() {
        Log.i(TAG, "Call ended. Stopping recording.")
        val callerName = currentPhoneNumber
        VoipNotificationListener.clearCallerName()
        isTelephonyCallActive = false
        isVoipCallActive = false
        isSpeakerActive = false
        currentPhoneNumber = null
        currentCallType = "cellular"
        voipConnectRunnable?.let { mainHandler.removeCallbacks(it) }
        voipConnectRunnable = null
        mainHandler.removeCallbacks(voipModeCheckerRunnable)
        updateNotificationText("Call monitoring active")

        if (isVoipAutoSpeakerphone || isAutoSpeakerphone) {
            setSpeakerphone(false)
        }

        val path = stopRecording()
        if (path != null && !callerName.isNullOrEmpty() && !callerName.equals("WhatsApp Call", ignoreCase = true) && path.contains("WhatsApp_Call")) {
            try {
                val origFile = File(path)
                val safe = callerName.replace(Regex("[^a-zA-Z0-9+]"), "_")
                val newName = origFile.name.replace("WhatsApp_Call", safe)
                val destFile = File(origFile.parentFile, newName)
                if (origFile.renameTo(destFile)) {
                    Log.i(TAG, "Renamed VoIP recording with contact name: ${destFile.absolutePath}")
                    MainActivity.instance?.onNativeCallEnded(destFile.absolutePath)
                    return
                }
            } catch (e: Throwable) {
                Log.w(TAG, "Could not rename VoIP file: ${e.message}")
            }
        }
        MainActivity.instance?.onNativeCallEnded(path)
    }

    fun getActiveRecorderService(): ICallRecorderService? {
        if (recorderService != null && try { recorderService?.asBinder()?.isBinderAlive == true } catch (e: Throwable) { false }) {
            return recorderService
        }
        return null
    }

    fun startRecording(fileName: String, callType: String = "cellular", preferredSource: Int = -1): Boolean {
        try {
            // If already recording or previous session was never finalized, stop it first!
            if (isRecording() || currentFilePath != null) {
                Log.w(TAG, "startRecording: already recording (${currentFilePath}). Forcibly stopping previous session before starting new one.")
                stopRecording()
                try { Thread.sleep(150) } catch (ignored: InterruptedException) {}
            }

            val service = getActiveRecorderService()
            if (service == null) {
                Log.w(TAG, "startRecording: Shizuku service not connected. Triggering bind...")
                checkAndBindService()
                return false
            }

            try { currentPfd?.close() } catch (ignored: Throwable) {}
            currentPfd = null

            val recordingsDir = getRecordingsDirectory()
            val outFile = File(recordingsDir, fileName)
            if (outFile.exists()) {
                outFile.delete()
            }
            outFile.createNewFile()
            outFile.setReadable(true, false)
            outFile.setWritable(true, false)

            currentFilePath = outFile.absolutePath
            currentPfd = ParcelFileDescriptor.open(
                outFile,
                ParcelFileDescriptor.MODE_CREATE or ParcelFileDescriptor.MODE_READ_WRITE
            )

            val started = service.startRecordingWithOptions(currentPfd, callType, preferredSource)

            if (!started) {
                Log.e(TAG, "recorderService.startRecordingWithOptions failed")
                try { currentPfd?.close() } catch (ignored: Throwable) {}
                currentPfd = null
                currentFilePath = null
                if (outFile.exists() && outFile.length() == 0L) {
                    outFile.delete()
                }
                MainActivity.instance?.onRecordingStatusChanged(false)
                return false
            }

            Log.i(TAG, "Recording started successfully to: ${outFile.absolutePath}")
            MainActivity.instance?.onRecordingStatusChanged(true)
            return true
        } catch (e: Throwable) {
            Log.e(TAG, "Failed startRecording: ${e.message}", e)
            try { currentPfd?.close() } catch (ignored: Throwable) {}
            currentPfd = null
            currentFilePath = null
            MainActivity.instance?.onRecordingStatusChanged(false)
            return false
        }
    }

    fun stopRecording(): String? {
        val path = currentFilePath
        Log.i(TAG, "stopRecording called. currentFilePath=$path, isRecording=${isRecording()}")

        try {
            // ALWAYS instruct Shizuku daemon to stop recording unconditionally!
            getActiveRecorderService()?.stopRecording()
        } catch (e: Throwable) {
            Log.w(TAG, "Error instructing Shizuku to stopRecording: ${e.message}")
        }

        try { Thread.sleep(200) } catch (ignored: InterruptedException) {}

        try { currentPfd?.close() } catch (ignored: Throwable) {}
        currentPfd = null
        currentFilePath = null

        MainActivity.instance?.onRecordingStatusChanged(false)

        if (path == null) {
            Log.d(TAG, "stopRecording: no local file path was tracked, Shizuku stopped.")
            return null
        }

        try {
            val f = File(path)
            f.setReadable(true, false)
            val fileLen = f.length()
            Log.i(TAG, "Recording stopped. File size: $fileLen bytes ($path)")

            if (f.exists() && fileLen == 0L) {
                Log.w(TAG, "Deleting 0-byte unplayable recording: $path")
                try { f.delete() } catch (ignored: Throwable) {}
                return null
            }
            return path
        } catch (e: Throwable) {
            Log.e(TAG, "Error checking stopped file: ${e.message}")
            return null
        }
    }

    fun isRecording(): Boolean {
        return try {
            getActiveRecorderService()?.isRecording ?: false
        } catch (e: Throwable) {
            false
        }
    }

    fun isServiceBound(): Boolean {
        return getActiveRecorderService() != null
    }

    fun isSpeakerphoneActive(): Boolean {
        val audioManager = getSystemService(AUDIO_SERVICE) as? AudioManager ?: return isSpeakerActive
        val systemSpeaker = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val device = audioManager.communicationDevice
            device != null && device.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER
        } else {
            @Suppress("DEPRECATION")
            audioManager.isSpeakerphoneOn
        }
        return isSpeakerActive || systemSpeaker
    }

    fun setSpeakerphone(on: Boolean): Boolean {
        isSpeakerActive = on

        // 1. First trigger privileged speakerphone routing under Shizuku daemon (UID 2000)
        try {
            val service = getActiveRecorderService()
            if (service != null) {
                val privOk = service.setSpeakerphone(on)
                Log.i(TAG, "Privileged Shizuku setSpeakerphone($on) result: $privOk")
            }
        } catch (e: Throwable) {
            Log.w(TAG, "Failed to call privileged setSpeakerphone on Shizuku daemon: ${e.message}")
        }

        val audioManager = getSystemService(AUDIO_SERVICE) as? AudioManager ?: return isSpeakerActive
        try {
            Log.i(TAG, "setSpeakerphone($on) called. Current active: ${isSpeakerphoneActive()}")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                if (on) {
                    val speaker = audioManager.availableCommunicationDevices.firstOrNull {
                        it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER
                    }
                    if (speaker != null) {
                        val ok = audioManager.setCommunicationDevice(speaker)
                        Log.i(TAG, "setCommunicationDevice(TYPE_BUILTIN_SPEAKER) result: $ok")
                    } else {
                        Log.w(TAG, "No TYPE_BUILTIN_SPEAKER found in availableCommunicationDevices")
                    }
                } else {
                    audioManager.clearCommunicationDevice()
                    Log.i(TAG, "clearCommunicationDevice() called")
                }
            }
            @Suppress("DEPRECATION")
            try { audioManager.isSpeakerphoneOn = on } catch (ignored: Throwable) {}

            if (on) {
                // Boost call audio volume to 100% so the speakerphone captures the remote party loud and clear
                val maxVol = audioManager.getStreamMaxVolume(AudioManager.STREAM_VOICE_CALL)
                val curVol = audioManager.getStreamVolume(AudioManager.STREAM_VOICE_CALL)
                if (originalVoiceCallVolume == -1) {
                    originalVoiceCallVolume = curVol
                }
                audioManager.setStreamVolume(AudioManager.STREAM_VOICE_CALL, maxVol, 0)
                try {
                    val maxMusic = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                    audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, maxMusic, 0)
                } catch (ignored: Throwable) {}
            } else if (originalVoiceCallVolume != -1) {
                try {
                    audioManager.setStreamVolume(AudioManager.STREAM_VOICE_CALL, originalVoiceCallVolume, 0)
                } catch (ignored: Throwable) {}
                originalVoiceCallVolume = -1
            }

            val finalState = isSpeakerphoneActive()
            Log.i(TAG, "Speakerphone state is now: $finalState")
            return finalState
        } catch (e: Throwable) {
            Log.w(TAG, "Failed setSpeakerphone($on): ${e.message}")
            return isSpeakerActive
        }
    }

    fun toggleSpeakerphone(): Boolean {
        val newState = !isSpeakerphoneActive()
        return setSpeakerphone(newState)
    }

    fun getRecordingsDirectory(): File {
        val base = getExternalFilesDir(null) ?: filesDir
        val recordingsDir = File(base, "recordings")
        if (!recordingsDir.exists()) {
            recordingsDir.mkdirs()
        }
        return recordingsDir
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
        Log.i(TAG, "CallRecordService onDestroy")
        if (instance == this) {
            instance = null
        }
        voipConnectRunnable?.let { mainHandler.removeCallbacks(it) }
        voipConnectRunnable = null
        mainHandler.removeCallbacks(voipModeCheckerRunnable)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            try {
                val audioManager = getSystemService(AUDIO_SERVICE) as? AudioManager
                audioRecordingCallback?.let { audioManager?.unregisterAudioRecordingCallback(it) }
            } catch (ignored: Throwable) {}
        }
        try {
            Shizuku.removeBinderReceivedListener(binderReceivedListener)
            Shizuku.removeBinderDeadListener(binderDeadListener)
        } catch (ignored: Throwable) {}
        try { currentPfd?.close() } catch (ignored: Throwable) {}
    }
}
