package com.example.record_mi

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import rikka.shizuku.Shizuku
import java.io.File

class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "MainActivity"
        private const val SHIZUKU_REQ_CODE = 1001
        private const val PRIMARY_CHANNEL = "com.example.record_mi/shizuku"
        private const val LEGACY_CHANNEL = "com.example.callrec/shizuku"

        var instance: MainActivity? = null
            private set
    }

    private var pendingPermissionResult: MethodChannel.Result? = null
    private var flutterMethodChannel: MethodChannel? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    private val binderReceivedListener = Shizuku.OnBinderReceivedListener {
        Log.i(TAG, "Shizuku server binder received in MainActivity sticky listener")
        try {
            if (Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED) {
                CallRecordService.instance?.checkAndBindService()
            }
        } catch (ignored: Throwable) {}
    }

    private val binderDeadListener = Shizuku.OnBinderDeadListener {
        Log.w(TAG, "Shizuku server binder died in MainActivity")
        onServiceStatusChanged(false)
    }

    private val permissionListener = Shizuku.OnRequestPermissionResultListener { requestCode, grantResult ->
        val granted = (grantResult == PackageManager.PERMISSION_GRANTED)
        Log.i(TAG, "Shizuku permission callback: code=$requestCode, granted=$granted")
        if (requestCode == SHIZUKU_REQ_CODE) {
            if (granted) {
                CallRecordService.instance?.checkAndBindService()
            }
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
        }
    }

    private val testReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val action = intent?.action ?: return
            Log.i(TAG, "testReceiver received action: $action")
            when (action) {
                "com.example.record_mi.TEST_RECORD" -> {
                    val duration = intent.getIntExtra("duration", 5)
                    val callType = intent.getStringExtra("callType") ?: "cellular"
                    val source = intent.getIntExtra("source", -1)
                    val testName = "test_${System.currentTimeMillis()}.m4a"
                    Log.i(TAG, "TEST_RECORD: starting $testName for ${duration}s...")
                    val ok = CallRecordService.instance?.startRecording(testName, callType, source) ?: false
                    Log.i(TAG, "TEST_RECORD: start result = $ok")
                    mainHandler.postDelayed({
                        Log.i(TAG, "TEST_RECORD: stopping recording...")
                        val path = CallRecordService.instance?.stopRecording()
                        Log.i(TAG, "TEST_RECORD: stop result = $path")
                    }, duration * 1000L)
                }
                "com.example.record_mi.TEST_CALL_START" -> {
                    val number = intent.getStringExtra("number") ?: "+1234567890"
                    val type = intent.getStringExtra("type") ?: "incoming"
                    CallRecordService.instance?.onCallConnected(number, type)
                }
                "com.example.record_mi.TEST_CALL_END" -> {
                    CallRecordService.instance?.onCallEnded()
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        instance = this

        ensureCallRecordServiceRunning()

        try {
            Shizuku.addBinderReceivedListenerSticky(binderReceivedListener)
            Shizuku.addBinderDeadListener(binderDeadListener)
        } catch (e: Throwable) {
            Log.w(TAG, "Could not add Shizuku binder listener: ${e.message}")
        }

        val filter = IntentFilter().apply {
            addAction("com.example.record_mi.TEST_RECORD")
            addAction("com.example.record_mi.TEST_CALL_START")
            addAction("com.example.record_mi.TEST_CALL_END")
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(testReceiver, filter, RECEIVER_EXPORTED)
        } else {
            registerReceiver(testReceiver, filter)
        }
        prewarmOverlayEngine()
    }

    private fun ensureCallRecordServiceRunning() {
        try {
            val serviceIntent = Intent(this, CallRecordService::class.java).apply {
                action = CallRecordService.ACTION_START_SERVICE
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(serviceIntent)
            } else {
                startService(serviceIntent)
            }
        } catch (e: Throwable) {
            Log.w(TAG, "Could not start CallRecordService: ${e.message}")
        }
    }

    override fun onResume() {
        super.onResume()
        instance = this
        ensureCallRecordServiceRunning()
        CallRecordService.instance?.checkAndBindService()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        try {
            Shizuku.addRequestPermissionResultListener(permissionListener)
        } catch (e: Throwable) {
            Log.w(TAG, "Could not add Shizuku permission listener: ${e.message}")
        }

        flutterMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PRIMARY_CHANNEL)

        val handler: (MethodCall, MethodChannel.Result) -> Unit = { call, result ->
            handleMethodCall(call, result)
        }

        flutterMethodChannel?.setMethodCallHandler(handler)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LEGACY_CHANNEL)
            .setMethodCallHandler(handler)

        OverlayControlChannel.register(flutterEngine)

        CallRecordService.instance?.checkAndBindService()
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pingShizuku", "isShizukuRunning" -> {
                result.success(isShizukuAlive())
            }

            "initShizuku" -> {
                try {
                    if (!isShizukuAlive()) {
                        result.error("SHIZUKU_DEAD", "Shizuku is not running on this device", null)
                        return
                    }
                    if (Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED) {
                        CallRecordService.instance?.checkAndBindService()
                        result.success(true)
                    } else {
                        pendingPermissionResult = result
                        Shizuku.requestPermission(SHIZUKU_REQ_CODE)
                    }
                } catch (e: Throwable) {
                    result.error("SHIZUKU_ERROR", e.localizedMessage, null)
                }
            }

            "checkPermission" -> {
                val granted = try {
                    isShizukuAlive() && Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
                } catch (e: Throwable) {
                    false
                }
                result.success(granted)
            }

            "requestPermission" -> {
                try {
                    if (!isShizukuAlive()) {
                        result.error("SHIZUKU_DEAD", "Shizuku daemon not responding", null)
                        return
                    }
                    pendingPermissionResult = result
                    Shizuku.requestPermission(SHIZUKU_REQ_CODE)
                } catch (e: Throwable) {
                    result.error("SHIZUKU_ERROR", e.localizedMessage, null)
                }
            }

            "bindUserService" -> {
                val success = CallRecordService.instance?.checkAndBindService() ?: false
                result.success(success)
            }

            "isServiceBound" -> {
                val bound = CallRecordService.instance?.isServiceBound() ?: false
                if (!bound && isShizukuAlive()) {
                    try {
                        if (Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED) {
                            CallRecordService.instance?.checkAndBindService()
                        }
                    } catch (ignored: Throwable) {}
                }
                result.success(bound)
            }

            "startRecord" -> {
                val requestedName = call.argument<String>("fileName")
                    ?: "call_${System.currentTimeMillis()}.m4a"
                val callType = call.argument<String>("callType") ?: "manual"
                val audioSource = call.argument<Int>("audioSource") ?: -1
                val started = CallRecordService.instance?.startRecording(requestedName, callType, audioSource) ?: false
                result.success(started)
            }

            "stopRecord" -> {
                val path = CallRecordService.instance?.stopRecording()
                result.success(path ?: true)
            }

            "isRecording" -> {
                val recording = CallRecordService.instance?.isRecording() ?: false
                result.success(recording)
            }

            "toggleSpeakerphone" -> {
                val state = CallRecordService.instance?.toggleSpeakerphone() ?: false
                result.success(state)
            }

            "isSpeakerphoneOn" -> {
                val state = CallRecordService.instance?.isSpeakerphoneActive() ?: false
                result.success(state)
            }

            "updateAppSettings" -> {
                val autoRecord = call.argument<Boolean>("autoRecord") ?: true
                val autoSpeaker = call.argument<Boolean>("autoSpeakerphone") ?: false
                val recordVoip = call.argument<Boolean>("recordVoipCalls") ?: false
                val voipSpeaker = call.argument<Boolean>("voipAutoSpeakerphone") ?: true
                val format = call.argument<String>("audioFormat") ?: "m4a"
                val source = call.argument<Int>("audioSource") ?: -1

                CallRecordService.instance?.let { service ->
                    service.isAutoRecordEnabled = autoRecord
                    service.isAutoSpeakerphone = autoSpeaker
                    service.isVoipRecordingEnabled = recordVoip
                    service.isVoipAutoSpeakerphone = voipSpeaker
                    service.configuredAudioFormat = format
                    service.configuredAudioSource = source
                }
                Log.i(TAG, "App settings updated: autoRecord=$autoRecord, autoSpeaker=$autoSpeaker, recordVoip=$recordVoip, voipSpeaker=$voipSpeaker, format=$format, source=$source")
                result.success(true)
            }

            "updateVoipSettings" -> {
                val recordVoip = call.argument<Boolean>("recordVoip") ?: false
                val autoSpeaker = call.argument<Boolean>("autoSpeakerphone") ?: true
                CallRecordService.instance?.let { service ->
                    service.isVoipRecordingEnabled = recordVoip
                    service.isVoipAutoSpeakerphone = autoSpeaker
                }
                Log.i(TAG, "VoIP settings updated: recordVoip=$recordVoip, autoSpeaker=$autoSpeaker")
                result.success(true)
            }

            "getRecordings" -> {
                val list = mutableListOf<Map<String, Any>>()
                val dir = getRecordingsDirectory()
                // Automatically delete any empty 0-byte remnant files so they never pollute the UI
                val allFiles = dir.listFiles { f -> f.isFile } ?: emptyArray()
                for (f in allFiles) {
                    if (f.length() == 0L) {
                        try { f.delete() } catch (ignored: Throwable) {}
                    }
                }
                val files = dir.listFiles { f ->
                    f.isFile && (f.extension == "m4a" || f.extension == "aac" || f.extension == "3gp" || f.extension == "amr" || f.extension == "wav") && f.length() > 0L
                } ?: emptyArray()

                val validFiles = files.sortedByDescending { it.lastModified() }

                for (f in validFiles) {
                    val parts = f.nameWithoutExtension.split("_")
                    var type = "Call"
                    var contact = "Unknown"
                    if (parts.size >= 4) {
                        type = parts[1].replaceFirstChar { it.uppercase() }
                        contact = parts.subList(2, parts.size - 1).joinToString(" ").replace("_", " ").trim()
                    } else if (parts.size == 3) {
                        type = parts[1].replaceFirstChar { it.uppercase() }
                        contact = parts[2].replace("_", " ").trim()
                    } else if (f.name.startsWith("test_")) {
                        type = "Test"
                        contact = "Test Recording"
                    }
                    if (type.equals("Voip", ignoreCase = true) || f.name.contains("voip", ignoreCase = true)) {
                        type = "WhatsApp"
                        if (contact.equals("WhatsApp", ignoreCase = true) || contact.isEmpty() || contact.equals("Unknown", ignoreCase = true)) {
                            contact = "WhatsApp Call"
                        }
                    }
                    list.add(
                        mapOf(
                            "name" to f.name,
                            "path" to f.absolutePath,
                            "size" to f.length(),
                            "lastModified" to f.lastModified(),
                            "callType" to type,
                            "contactNumber" to contact
                        )
                    )
                }
                result.success(list)
            }

            "deleteRecording" -> {
                val path = call.argument<String>("path")
                if (path != null) {
                    val f = File(path)
                    val deleted = f.delete()
                    result.success(deleted)
                } else {
                    result.success(false)
                }
            }

            "shareRecording" -> {
                val path = call.argument<String>("path")
                if (path != null) {
                    try {
                        val file = File(path)
                        val uri = androidx.core.content.FileProvider.getUriForFile(
                            this,
                            "${packageName}.fileprovider",
                            file
                        )
                        val shareIntent = Intent(Intent.ACTION_SEND).apply {
                            type = "audio/*"
                            putExtra(Intent.EXTRA_STREAM, uri)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                        startActivity(Intent.createChooser(shareIntent, "Share Call Recording"))
                        result.success(true)
                    } catch (e: Throwable) {
                        Log.e(TAG, "Share recording failed: ${e.message}")
                        result.error("SHARE_ERROR", e.localizedMessage, null)
                    }
                } else {
                    result.success(false)
                }
            }

            "openShizukuPlayStore" -> {
                try {
                    val marketIntent = Intent(Intent.ACTION_VIEW, android.net.Uri.parse("market://details?id=moe.shizuku.privileged.api")).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    startActivity(marketIntent)
                    result.success(true)
                } catch (e: Exception) {
                    try {
                        val webIntent = Intent(Intent.ACTION_VIEW, android.net.Uri.parse("https://play.google.com/store/apps/details?id=moe.shizuku.privileged.api")).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(webIntent)
                        result.success(true)
                    } catch (err: Exception) {
                        result.error("PLAY_STORE_ERROR", err.localizedMessage, null)
                    }
                }
            }

            "isShizukuInstalled" -> {
                val installed = try {
                    packageManager.getPackageInfo("moe.shizuku.privileged.api", 0)
                    true
                } catch (e: PackageManager.NameNotFoundException) {
                    false
                }
                result.success(installed)
            }

            else -> result.notImplemented()
        }
    }

    private fun prewarmOverlayEngine() {
        try {
            val cache = io.flutter.embedding.engine.FlutterEngineCache.getInstance()
            var engine = cache.get("myCachedEngine")
            if (engine == null) {
                val enn = io.flutter.embedding.engine.FlutterEngineGroup(applicationContext)
                val dEntry = io.flutter.embedding.engine.dart.DartExecutor.DartEntrypoint(
                    io.flutter.FlutterInjector.instance().flutterLoader().findAppBundlePath(),
                    "overlayMain"
                )
                engine = enn.createAndRunEngine(applicationContext, dEntry)
                cache.put("myCachedEngine", engine)
                Log.i(TAG, "Pre-warmed overlay FlutterEngine successfully.")
            }
            if (engine != null) {
                OverlayControlChannel.register(engine)
            }
        } catch (e: Throwable) {
            Log.w(TAG, "Prewarming overlay engine: ${e.message}")
        }
    }

    private fun isShizukuAlive(): Boolean {
        return try {
            Shizuku.pingBinder()
        } catch (e: Throwable) {
            false
        }
    }

    // Callbacks from CallRecordService
    fun onNativeCallOutgoing(number: String?) {
        mainHandler.post {
            flutterMethodChannel?.invokeMethod(
                "onCallOutgoing",
                mapOf("number" to (number ?: "Outgoing Call"))
            )
        }
    }

    fun onNativeCallRinging(number: String?, callType: String = "incoming") {
        mainHandler.post {
            flutterMethodChannel?.invokeMethod(
                "onCallRinging",
                mapOf("number" to (number ?: "Incoming Call"), "callType" to callType)
            )
        }
    }

    fun onNativeCallConnected(number: String?, callType: String) {
        mainHandler.post {
            flutterMethodChannel?.invokeMethod(
                "onCallConnected",
                mapOf("number" to (number ?: "Call"), "callType" to callType)
            )
        }
    }

    fun onNativeCallStarted(number: String?, callType: String, fileName: String, recording: Boolean) {
        mainHandler.post {
            flutterMethodChannel?.invokeMethod(
                "onCallStarted",
                mapOf(
                    "number" to (number ?: "unknown"),
                    "fileName" to fileName,
                    "recording" to recording,
                    "callType" to callType
                )
            )
        }
    }

    fun onNativeCallEnded(path: String? = null) {
        mainHandler.post {
            Log.i(TAG, "Native auto-record trigger: call ended, path=$path")
            flutterMethodChannel?.invokeMethod("onCallEnded", mapOf("path" to (path ?: "")))
        }
    }

    fun onServiceStatusChanged(bound: Boolean) {
        mainHandler.post {
            flutterMethodChannel?.invokeMethod("onServiceStatusChanged", mapOf("bound" to bound))
        }
    }

    fun onRecordingStatusChanged(recording: Boolean) {
        mainHandler.post {
            flutterMethodChannel?.invokeMethod("onRecordingStatusChanged", mapOf("recording" to recording))
        }
    }

    private fun getRecordingsDirectory(): File {
        val base = getExternalFilesDir(null) ?: filesDir
        val recordingsDir = File(base, "recordings")
        if (!recordingsDir.exists()) {
            recordingsDir.mkdirs()
        }
        return recordingsDir
    }

    override fun onDestroy() {
        super.onDestroy()
        if (instance == this) {
            instance = null
        }
        try {
            unregisterReceiver(testReceiver)
        } catch (ignored: Throwable) {}

        try {
            Shizuku.removeBinderReceivedListener(binderReceivedListener)
            Shizuku.removeBinderDeadListener(binderDeadListener)
            Shizuku.removeRequestPermissionResultListener(permissionListener)
        } catch (ignored: Throwable) {}
    }
}
