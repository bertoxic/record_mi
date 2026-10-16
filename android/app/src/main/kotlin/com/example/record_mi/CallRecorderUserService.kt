package com.example.record_mi

import android.annotation.SuppressLint
import android.content.AttributionSource
import android.content.Context
import android.content.ContextWrapper
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.util.Log
import org.lsposed.hiddenapibypass.HiddenApiBypass
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

/**
 * Custom ContextWrapper that attributes audio capture to com.android.shell (UID 2000).
 * Overrides getPackageName, getOpPackageName, and getAttributionSource to prevent
 * JNI errors in native audio setup on Android 12+.
 */
class ShellContextWrapper(base: Context) : ContextWrapper(base) {
    override fun getPackageName(): String = "com.android.shell"
    override fun getOpPackageName(): String = "com.android.shell"

    override fun getAttributionSource(): AttributionSource {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            return AttributionSource.Builder(2000)
                .setPackageName("com.android.shell")
                .build()
        }
        return super.getAttributionSource()
    }
}

/**
 * Privileged UserService executing under UID 2000 (com.android.shell) via Shizuku.
 *
 * Runs as a persistent daemon. Features dual-engine capture:
 * 1. Primary Engine: MediaRecorder (AAC/MPEG-4 & AMR-WB) with VOICE_CALL & VOICE_COMMUNICATION.
 * 2. Failover Engine: AudioRecord direct PCM/WAV streamer with signature-level CAPTURE_AUDIO_OUTPUT.
 * 3. VoIP Dual-Stream Engine: AudioPolicy loopback sink (WhatsApp USAGE_VOICE_COMMUNICATION) + Mic mixer.
 *
 * Injects ActivityThread app binding to eliminate JNI 'java_string == null' crashes in MediaRecorder.
 */
class CallRecorderUserService(private var context: Context?) : ICallRecorderService.Stub() {

    // Fallback no-arg constructor required by some Shizuku runner versions
    constructor() : this(null)

    private var recorder: MediaRecorder? = null
    private var audioRecord: AudioRecord? = null
    private var audioRecordThread: Thread? = null
    @Volatile private var isAudioRecordRunning = false
    private var audioRecordBytesWritten = 0L

    // VoIP Dual-Stream privileged capture resources
    private var activeAudioPolicy: Any? = null
    private var downlinkRecord: AudioRecord? = null
    private var uplinkRecord: AudioRecord? = null
    private var downlinkThread: Thread? = null
    private var uplinkThread: Thread? = null
    private var mixerThread: Thread? = null

    private var activePfd: ParcelFileDescriptor? = null
    private var isCurrentlyRecording = false
    private var activeSource = -1
    private var activeSampleRate = 48000

    companion object {
        private const val TAG = "CallRecUserService"
        private const val SAMPLE_RATE = 48000
        private const val CHANNELS = 1 // Mono is standard and universal for telephony audio
        private const val BITS_PER_SAMPLE = 16
    }

    init {
        Log.i(TAG, "CallRecorderUserService instantiated (Process UID: ${android.os.Process.myUid()})")
        fixActivityThread()
        grantHiddenAppOps()
        initHiddenApiExemptions()
    }

    private fun initHiddenApiExemptions() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                HiddenApiBypass.addHiddenApiExemptions(
                    "Landroid/media/audiopolicy/",
                    "Landroid/media/"
                )
                Log.i(TAG, "HiddenApiBypass exemptions applied for android.media.audiopolicy")
            }
        } catch (e: Throwable) {
            Log.w(TAG, "HiddenApiBypass init warning: ${e.message}")
        }
    }

    private fun fixActivityThread() {
        try {
            val atClass = Class.forName("android.app.ActivityThread")
            var at: Any? = null
            try {
                at = atClass.getMethod("currentActivityThread").invoke(null)
            } catch (ignored: Throwable) {}

            if (at == null) {
                try {
                    at = atClass.getMethod("systemMain").invoke(null)
                } catch (ignored: Throwable) {}
            }

            if (at != null) {
                try {
                    val appBindDataClass = Class.forName("android.app.ActivityThread\$AppBindData")
                    val bindDataCtor = appBindDataClass.getDeclaredConstructor().apply { isAccessible = true }
                    val bindData = bindDataCtor.newInstance()

                    val appInfo = android.content.pm.ApplicationInfo().apply {
                        packageName = "com.android.shell"
                        processName = "com.android.shell"
                        uid = 2000
                    }

                    val appInfoField = appBindDataClass.getDeclaredField("appInfo").apply { isAccessible = true }
                    appInfoField.set(bindData, appInfo)

                    val processNameField = appBindDataClass.getDeclaredField("processName").apply { isAccessible = true }
                    processNameField.set(bindData, "com.android.shell")

                    val boundAppField = at.javaClass.getDeclaredField("mBoundApplication").apply { isAccessible = true }
                    boundAppField.set(at, bindData)
                    Log.i(TAG, "Successfully injected mBoundApplication into ActivityThread!")
                } catch (e: Throwable) {
                    Log.w(TAG, "Could not inject mBoundApplication: ${e.message}")
                }
            }

            val curPkg = try { atClass.getMethod("currentPackageName").invoke(null) } catch (e: Throwable) { null }
            Log.i(TAG, "ActivityThread.currentPackageName() is now: '$curPkg'")
        } catch (e: Throwable) {
            Log.w(TAG, "fixActivityThread failed: ${e.message}")
        }
    }

    private fun getEffectiveContext(): Context? {
        if (context != null) return context

        try {
            val atClass = Class.forName("android.app.ActivityThread")
            val catMethod = atClass.getMethod("currentActivityThread")
            val cat = catMethod.invoke(null)
            if (cat != null) {
                val getSysCtxMethod = atClass.getMethod("getSystemContext")
                val sysCtx = getSysCtxMethod.invoke(cat) as? Context
                if (sysCtx != null) {
                    context = sysCtx
                    return sysCtx
                }
            }
        } catch (ignored: Throwable) {}

        try {
            val atClass = Class.forName("android.app.ActivityThread")
            val currentAppMethod = atClass.getMethod("currentApplication")
            val app = currentAppMethod.invoke(null) as? Context
            if (app != null) {
                context = app
                return app
            }
        } catch (ignored: Throwable) {}

        return try {
            val activityThreadClass = Class.forName("android.app.ActivityThread")
            val systemMainMethod = activityThreadClass.getMethod("systemMain")
            val activityThread = systemMainMethod.invoke(null)
            val getSystemContextMethod = activityThreadClass.getMethod("getSystemContext")
            val sysCtx = getSystemContextMethod.invoke(activityThread) as Context
            context = sysCtx
            sysCtx
        } catch (e: Throwable) {
            Log.w(TAG, "Could not acquire system context: ${e.message}")
            null
        }
    }

    private fun grantHiddenAppOps() {
        val targets = listOf("com.android.shell", "2000", "com.example.record_mi")
        val appOps = listOf(
            "RECORD_AUDIO",
            "CAPTURE_AUDIO_OUTPUT",
            "PROJECT_MEDIA",
            "READ_PHONE_STATE",
            "READ_CALL_LOG",
            "SYSTEM_ALERT_WINDOW"
        )
        for (target in targets) {
            for (op in appOps) {
                try {
                    val proc = Runtime.getRuntime().exec(arrayOf("cmd", "appops", "set", target, op, "allow"))
                    proc.waitFor()
                } catch (ignored: Throwable) {}
            }
        }
        try {
            val proc = Runtime.getRuntime().exec(arrayOf("settings", "put", "global", "hidden_api_policy", "1"))
            proc.waitFor()
        } catch (ignored: Throwable) {}
        try {
            val proc = Runtime.getRuntime().exec(arrayOf("cmd", "notification", "allow_listener", "com.example.record_mi/.VoipNotificationListener"))
            proc.waitFor()
            Log.i(TAG, "VoipNotificationListener allowed via cmd notification")
        } catch (ignored: Throwable) {}
    }

    override fun startRecording(outputPfd: ParcelFileDescriptor?): Boolean {
        val token = android.os.Binder.clearCallingIdentity()
        try {
            return startRecordingWithOptions(outputPfd, "cellular", -1)
        } finally {
            android.os.Binder.restoreCallingIdentity(token)
        }
    }

    override fun startRecordingWithOptions(
        outputPfd: ParcelFileDescriptor?,
        callType: String?,
        preferredSource: Int
    ): Boolean {
        val token = android.os.Binder.clearCallingIdentity()
        try {
            return startRecordingWithOptionsInternal(outputPfd, callType, preferredSource)
        } finally {
            android.os.Binder.restoreCallingIdentity(token)
        }
    }

    private fun startRecordingWithOptionsInternal(
        outputPfd: ParcelFileDescriptor?,
        callType: String?,
        preferredSource: Int
    ): Boolean {
        if (outputPfd == null) {
            Log.e(TAG, "startRecording failed: outputPfd is null")
            return false
        }

        if (isCurrentlyRecording) {
            Log.w(TAG, "Already recording. Stopping previous session before starting new one.")
            stopRecording()
            try { Thread.sleep(100) } catch (ignored: Throwable) {}
        }

        fixActivityThread()
        activePfd = outputPfd
        audioRecordBytesWritten = 0L

        val isSamsung = Build.MANUFACTURER.contains("samsung", ignoreCase = true)
        val ctx = getEffectiveContext()
        val audioManager = ctx?.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        val isModeInComm = audioManager?.mode == AudioManager.MODE_IN_COMMUNICATION
        val isVoip = (callType?.contains("voip", ignoreCase = true) == true) || isModeInComm
        val isWav = callType?.contains("wav", ignoreCase = true) == true
        val is3gp = callType?.contains("3gp", ignoreCase = true) == true

        Log.i(TAG, "startRecordingWithOptions: callType='$callType', isVoip=$isVoip (modeInComm=$isModeInComm), isSamsung=$isSamsung, isWav=$isWav, is3gp=$is3gp")

        // 1. PRIORITY FOR VOIP (WhatsApp): Privileged Dual-Stream AudioPolicy capture (WhatsApp downlink + local mic mixer)
        if (isVoip) {
            if (startVoipMixRecording(outputPfd, preferredSource)) {
                isCurrentlyRecording = true
                activeSource = preferredSource
                Log.i(TAG, "VoIP dual-stream recording started successfully!")
                return true
            }
            Log.w(TAG, "startVoipMixRecording failed. Falling back to single-stream AudioRecord...")
        }

        val candidateSources = mutableListOf<Int>()
        if (preferredSource > 0) {
            candidateSources.add(preferredSource)
        }

        // For VoIP calls (WhatsApp, Telegram): NEVER use VOICE_COMMUNICATION (7).
        // Opening VOICE_COMMUNICATION while WhatsApp is active causes Android AudioPolicy
        // to assign exclusive communication capture to UID 2000, muting WhatsApp's microphone
        // so the other caller cannot hear the user.
        // Using CAMCORDER (5) and VOICE_RECOGNITION (6) allows concurrent capture without muting WhatsApp and
        // disables echo cancellation so the loudspeaker is captured along with local voice.
        if (isVoip) {
            if (!candidateSources.contains(MediaRecorder.AudioSource.CAMCORDER)) {
                candidateSources.add(MediaRecorder.AudioSource.CAMCORDER) // 5 (Omnidirectional, AEC-bypassed)
            }
            if (!candidateSources.contains(MediaRecorder.AudioSource.VOICE_RECOGNITION)) {
                candidateSources.add(MediaRecorder.AudioSource.VOICE_RECOGNITION) // 6
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && !candidateSources.contains(MediaRecorder.AudioSource.UNPROCESSED)) {
                candidateSources.add(MediaRecorder.AudioSource.UNPROCESSED) // 9
            }
            if (!candidateSources.contains(MediaRecorder.AudioSource.MIC)) {
                candidateSources.add(MediaRecorder.AudioSource.MIC) // 1
            }
            if (!candidateSources.contains(MediaRecorder.AudioSource.DEFAULT)) {
                candidateSources.add(MediaRecorder.AudioSource.DEFAULT) // 0
            }
        } else if (isSamsung) {
            // On Samsung One UI, VOICE_RECOGNITION (6) disables DSP echo cancellation
            // so both the caller (local mic) and receiver (earpiece/speaker) are captured clearly.
            if (!candidateSources.contains(MediaRecorder.AudioSource.VOICE_RECOGNITION)) {
                candidateSources.add(MediaRecorder.AudioSource.VOICE_RECOGNITION) // 6
            }
            if (!candidateSources.contains(MediaRecorder.AudioSource.VOICE_COMMUNICATION)) {
                candidateSources.add(MediaRecorder.AudioSource.VOICE_COMMUNICATION) // 7
            }
            if (!candidateSources.contains(MediaRecorder.AudioSource.MIC)) {
                candidateSources.add(MediaRecorder.AudioSource.MIC) // 1
            }
            if (!candidateSources.contains(MediaRecorder.AudioSource.VOICE_CALL)) {
                candidateSources.add(MediaRecorder.AudioSource.VOICE_CALL) // 4
            }
        } else {
            if (!candidateSources.contains(MediaRecorder.AudioSource.VOICE_CALL)) {
                candidateSources.add(MediaRecorder.AudioSource.VOICE_CALL)
            }
            if (!candidateSources.contains(MediaRecorder.AudioSource.VOICE_COMMUNICATION)) {
                candidateSources.add(MediaRecorder.AudioSource.VOICE_COMMUNICATION)
            }
            if (!candidateSources.contains(MediaRecorder.AudioSource.MIC)) {
                candidateSources.add(MediaRecorder.AudioSource.MIC)
            }
            if (!candidateSources.contains(MediaRecorder.AudioSource.VOICE_RECOGNITION)) {
                candidateSources.add(MediaRecorder.AudioSource.VOICE_RECOGNITION)
            }
        }

        Log.i(TAG, "startRecordingWithOptions: callType='$callType', isSamsung=$isSamsung, isWav=$isWav, is3gp=$is3gp, candidateSources=$candidateSources")

        // 1. If VoIP or WAV requested, prioritize AudioRecord PCM/WAV streamer with real-time dynamic auto-gain!
        if (isVoip || isWav) {
            for (source in candidateSources) {
                if (tryInitAudioRecordWithSource(outputPfd, source, isVoip)) {
                    isCurrentlyRecording = true
                    activeSource = source
                    Log.i(TAG, "Recording started successfully with AudioRecord (isVoip=$isVoip, AudioSource: $source)")
                    return true
                }
            }
        }

        // 2. Try MediaRecorder (hardware accelerated AAC/MPEG-4 or AMR-WB/3GP)
        for (source in candidateSources) {
            if (tryInitRecorderWithSource(outputPfd, source, is3gp)) {
                isCurrentlyRecording = true
                activeSource = source
                Log.i(TAG, "Recording started successfully with MediaRecorder (AudioSource: $source)")
                return true
            }
        }

        // 3. Fall back to AudioRecord (direct HAL PCM streamer)
        Log.w(TAG, "MediaRecorder failed for all candidates. Falling back to AudioRecord PCM/WAV streamer...")
        for (source in candidateSources) {
            if (tryInitAudioRecordWithSource(outputPfd, source)) {
                isCurrentlyRecording = true
                activeSource = source
                Log.i(TAG, "Recording started successfully with AudioRecord (AudioSource: $source)")
                return true
            }
        }

        Log.e(TAG, "Failed to start both MediaRecorder and AudioRecord across all candidate sources")
        try {
            activePfd?.close()
        } catch (ignored: Exception) {}
        activePfd = null
        return false
    }

    @SuppressLint("MissingPermission", "PrivateApi")
    private fun createWhatsappDownlinkRecorder(sampleRate: Int): Pair<Any, AudioRecord>? {
        val token = android.os.Binder.clearCallingIdentity()
        return try {
            val ctx = getEffectiveContext() ?: return null
            val shellContext = if (ctx is ShellContextWrapper) ctx else ShellContextWrapper(ctx)
            val audioManager = shellContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager

            // 1. Build AudioAttributes targeting USAGE_VOICE_COMMUNICATION (WhatsApp/VoIP playback)
            val attr = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                .build()

            // 2. Reflect into android.media.audiopolicy.AudioMixingRule$Builder
            val ruleBuilderClass = Class.forName("android.media.audiopolicy.AudioMixingRule\$Builder")
            val ruleBuilder = ruleBuilderClass.getDeclaredConstructor().newInstance()

            val addMixRule = ruleBuilderClass.methods.firstOrNull {
                it.name == "addMixRule" && it.parameterTypes.size == 2
            } ?: throw NoSuchMethodException("addMixRule not found")

            // RULE_MATCH_ATTRIBUTE_USAGE = 1
            addMixRule.invoke(ruleBuilder, 1, attr)

            // allowPrivilegedPlaybackCapture(true)
            val allowPriv = ruleBuilderClass.methods.firstOrNull {
                it.name == "allowPrivilegedPlaybackCapture" && it.parameterTypes.size == 1
            }
            try { allowPriv?.invoke(ruleBuilder, true) } catch (e: Throwable) { Log.w(TAG, "allowPrivilegedPlaybackCapture note: ${e.message}") }

            // voiceCommunicationCaptureAllowed(true)
            val allowVoiceComm = ruleBuilderClass.methods.firstOrNull {
                it.name == "voiceCommunicationCaptureAllowed" && it.parameterTypes.size == 1
            }
            try { allowVoiceComm?.invoke(ruleBuilder, true) } catch (e: Throwable) { Log.w(TAG, "voiceCommunicationCaptureAllowed note: ${e.message}") }

            val buildRule = ruleBuilderClass.getMethod("build")
            val mixingRule = buildRule.invoke(ruleBuilder)

            // 3. Build AudioMix with ROUTE_FLAG_LOOP_BACK_RENDER (3) so the user can still hear the call!
            val audioFormat = AudioFormat.Builder()
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setSampleRate(sampleRate)
                .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
                .build()

            val mixBuilderClass = Class.forName("android.media.audiopolicy.AudioMix\$Builder")
            val ruleClass = Class.forName("android.media.audiopolicy.AudioMixingRule")
            val mixBuilder = mixBuilderClass.getDeclaredConstructor(ruleClass).newInstance(mixingRule)

            mixBuilderClass.getMethod("setFormat", AudioFormat::class.java).invoke(mixBuilder, audioFormat)
            // ROUTE_FLAG_LOOP_BACK_RENDER = 0x1 | 0x2 = 3
            mixBuilderClass.getMethod("setRouteFlags", Int::class.javaPrimitiveType).invoke(mixBuilder, 3)
            val audioMix = mixBuilderClass.getMethod("build").invoke(mixBuilder)

            // 4. Register the AudioPolicy and extract the AudioRecord sink
            val policyBuilderClass = Class.forName("android.media.audiopolicy.AudioPolicy\$Builder")
            val mixClass = Class.forName("android.media.audiopolicy.AudioMix")
            val policyBuilder = policyBuilderClass.getDeclaredConstructor(Context::class.java).newInstance(shellContext)

            val mainLooper = Looper.getMainLooper() ?: Looper.myLooper()
            if (mainLooper != null) {
                try {
                    policyBuilderClass.methods.firstOrNull { it.name == "setLooper" }?.invoke(policyBuilder, mainLooper)
                } catch (ignored: Throwable) {}
            }

            policyBuilderClass.getMethod("addMix", mixClass).invoke(policyBuilder, audioMix)
            val audioPolicy = policyBuilderClass.getMethod("build").invoke(policyBuilder)

            val policyClass = Class.forName("android.media.audiopolicy.AudioPolicy")
            val regMethod = AudioManager::class.java.getMethod("registerAudioPolicy", policyClass)
            val regResult = regMethod.invoke(audioManager, audioPolicy) as Int

            Log.i(TAG, "createWhatsappDownlinkRecorder: registerAudioPolicy returned $regResult")
            if (regResult != 0) {
                Log.e(TAG, "createWhatsappDownlinkRecorder: registerAudioPolicy failed with code $regResult")
                return null
            }

            val downlinkSink = policyClass
                .getMethod("createAudioRecordSink", mixClass)
                .invoke(audioPolicy, audioMix) as? AudioRecord

            if (downlinkSink == null || downlinkSink.state != AudioRecord.STATE_INITIALIZED) {
                Log.e(TAG, "createWhatsappDownlinkRecorder: downlinkSink is null or not STATE_INITIALIZED (${downlinkSink?.state})")
                try {
                    val unreg = AudioManager::class.java.methods.firstOrNull {
                        it.name == "unregisterAudioPolicyAsync" || it.name == "unregisterAudioPolicy"
                    }
                    unreg?.invoke(audioManager, audioPolicy)
                } catch (ignored: Throwable) {}
                try { downlinkSink?.release() } catch (ignored: Throwable) {}
                return null
            }

            Log.i(TAG, "createWhatsappDownlinkRecorder: Downlink sink created and verified! (state=${downlinkSink.state})")
            Pair(audioPolicy, downlinkSink)
        } catch (e: Throwable) {
            Log.e(TAG, "createWhatsappDownlinkRecorder reflection failed: ${e.message}", e)
            null
        } finally {
            android.os.Binder.restoreCallingIdentity(token)
        }
    }

    @SuppressLint("MissingPermission")
    private fun startVoipMixRecording(outputPfd: ParcelFileDescriptor, preferredSource: Int = -1): Boolean {
        val sampleRate = 16000
        val minBuf = AudioRecord.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )
        if (minBuf <= 0) {
            Log.e(TAG, "startVoipMixRecording: getMinBufferSize returned $minBuf")
            return false
        }
        val bufferSize = maxOf(minBuf * 2, 4096)

        // 1. Open Downlink (The Other Person on WhatsApp via privileged AudioPolicy loopback sink)
        val downlinkPair = createWhatsappDownlinkRecorder(sampleRate)
        if (downlinkPair == null) {
            Log.w(TAG, "createWhatsappDownlinkRecorder failed, cannot start VoIP mix recording")
            return false
        }
        val policy = downlinkPair.first
        val downlink = downlinkPair.second

        // 2. Open Uplink (Local user's microphone)
        // Candidate sources: VOICE_RECOGNITION captures clear local voice without seizing exclusive communication capture
        val candidateUplinkSources = mutableListOf<Int>()
        if (preferredSource > 0) candidateUplinkSources.add(preferredSource)
        candidateUplinkSources.addAll(listOf(
            MediaRecorder.AudioSource.VOICE_RECOGNITION,
            MediaRecorder.AudioSource.MIC,
            MediaRecorder.AudioSource.CAMCORDER,
            MediaRecorder.AudioSource.VOICE_COMMUNICATION
        ))

        val ctx = getEffectiveContext()
        val shellContext = if (ctx is ShellContextWrapper) ctx else if (ctx != null) ShellContextWrapper(ctx) else null

        var uplink: AudioRecord? = null
        for (src in candidateUplinkSources) {
            try {
                val builder = AudioRecord.Builder()
                    .setAudioSource(src)
                    .setAudioFormat(
                        AudioFormat.Builder()
                            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                            .setSampleRate(sampleRate)
                            .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
                            .build()
                    )
                    .setBufferSizeInBytes(bufferSize)

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && shellContext != null) {
                    try {
                        val setCtxMethod = AudioRecord.Builder::class.java.methods.firstOrNull {
                            it.name == "setContext" && it.parameterTypes.size == 1
                        }
                        setCtxMethod?.invoke(builder, shellContext)
                    } catch (ignored: Throwable) {}
                }

                val rec = builder.build()

                if (rec.state == AudioRecord.STATE_INITIALIZED) {
                    rec.startRecording()
                    if (rec.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                        uplink = rec
                        Log.i(TAG, "VoIP Uplink AudioRecord recording initialized with source $src")
                        break
                    } else {
                        rec.release()
                    }
                } else {
                    rec.release()
                }
            } catch (e: Throwable) {
                Log.w(TAG, "VoIP Uplink source $src failed: ${e.message}")
            }
        }

        if (uplink == null) {
            Log.e(TAG, "All candidate sources failed for VoIP Uplink")
            try {
                val ctx = getEffectiveContext()
                val audioManager = ctx?.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                val unreg = AudioManager::class.java.methods.firstOrNull {
                    it.name == "unregisterAudioPolicyAsync" || it.name == "unregisterAudioPolicy"
                }
                unreg?.invoke(audioManager, policy)
            } catch (ignored: Throwable) {}
            try { downlink.release() } catch (ignored: Throwable) {}
            return false
        }

        // 3. Start Downlink recording sink
        try {
            downlink.startRecording()
            if (downlink.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
                Log.w(TAG, "downlink.recordingState is ${downlink.recordingState}")
            }
        } catch (e: Throwable) {
            Log.e(TAG, "Failed to start downlink sink: ${e.message}")
            try { uplink.stop(); uplink.release() } catch (ignored: Throwable) {}
            try {
                val ctx = getEffectiveContext()
                val audioManager = ctx?.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                val unreg = AudioManager::class.java.methods.firstOrNull {
                    it.name == "unregisterAudioPolicyAsync" || it.name == "unregisterAudioPolicy"
                }
                unreg?.invoke(audioManager, policy)
            } catch (ignored: Throwable) {}
            try { downlink.release() } catch (ignored: Throwable) {}
            return false
        }

        try {
            android.system.Os.lseek(outputPfd.fileDescriptor, 0, android.system.OsConstants.SEEK_SET)
        } catch (ignored: Throwable) {}

        activeSampleRate = sampleRate
        activeAudioPolicy = policy
        downlinkRecord = downlink
        uplinkRecord = uplink
        isAudioRecordRunning = true
        audioRecordBytesWritten = 0L

        val chunkSamples = 320 // 20ms at 16000 Hz
        val uplinkQueue = LinkedBlockingQueue<ShortArray>(50)
        val downlinkQueue = LinkedBlockingQueue<ShortArray>(50)

        val uThread = Thread({
            val buf = ShortArray(chunkSamples)
            try {
                while (isAudioRecordRunning) {
                    val read = uplink.read(buf, 0, buf.size)
                    if (read > 0) {
                        val copy = buf.copyOf(read)
                        while (!uplinkQueue.offer(copy, 10, TimeUnit.MILLISECONDS) && isAudioRecordRunning) {
                            uplinkQueue.poll()
                        }
                    } else if (read < 0) {
                        Log.w(TAG, "VoIP uplink.read returned: $read")
                        break
                    }
                }
            } catch (e: Throwable) {
                Log.e(TAG, "VoipUplinkReader error: ${e.message}")
            }
        }, "VoipUplinkReader")

        val dThread = Thread({
            val buf = ShortArray(chunkSamples)
            try {
                while (isAudioRecordRunning) {
                    val read = downlink.read(buf, 0, buf.size)
                    if (read > 0) {
                        val copy = buf.copyOf(read)
                        while (!downlinkQueue.offer(copy, 10, TimeUnit.MILLISECONDS) && isAudioRecordRunning) {
                            downlinkQueue.poll()
                        }
                    } else if (read < 0) {
                        Log.w(TAG, "VoIP downlink.read returned: $read")
                        break
                    }
                }
            } catch (e: Throwable) {
                Log.e(TAG, "VoipDownlinkReader error: ${e.message}")
            }
        }, "VoipDownlinkReader")

        val mThread = Thread({
            val fos = FileOutputStream(outputPfd.fileDescriptor)
            try {
                writeWavHeader(fos, 0, 0, activeSampleRate, CHANNELS, BITS_PER_SAMPLE)
                fos.flush()

                val mixedBytes = ByteArray(chunkSamples * 2)

                while (isAudioRecordRunning) {
                    val micChunk = uplinkQueue.poll(20, TimeUnit.MILLISECONDS)
                    val spkChunk = downlinkQueue.poll()

                    if (micChunk == null && spkChunk == null) {
                        continue
                    }

                    val samples = maxOf(micChunk?.size ?: 0, spkChunk?.size ?: 0)
                    if (samples == 0) continue

                    val outByteLen = samples * 2
                    val byteBuf = if (mixedBytes.size >= outByteLen) mixedBytes else ByteArray(outByteLen)

                    for (i in 0 until samples) {
                        val m = if (micChunk != null && i < micChunk.size) micChunk[i].toInt() else 0
                        val rawSpk = if (spkChunk != null && i < spkChunk.size) spkChunk[i].toInt() else 0
                        val s = (rawSpk * 1.35f).toInt()

                        val mixed = (m + s).coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort()
                        byteBuf[i * 2] = (mixed.toInt() and 0xFF).toByte()
                        byteBuf[i * 2 + 1] = ((mixed.toInt() shr 8) and 0xFF).toByte()
                    }

                    fos.write(byteBuf, 0, outByteLen)
                    audioRecordBytesWritten += outByteLen
                }

                // Drain remaining buffered samples upon stop
                while (true) {
                    val micChunk = uplinkQueue.poll()
                    val spkChunk = downlinkQueue.poll()
                    if (micChunk == null && spkChunk == null) break

                    val samples = maxOf(micChunk?.size ?: 0, spkChunk?.size ?: 0)
                    if (samples == 0) break
                    val outByteLen = samples * 2
                    val byteBuf = if (mixedBytes.size >= outByteLen) mixedBytes else ByteArray(outByteLen)

                    for (i in 0 until samples) {
                        val m = if (micChunk != null && i < micChunk.size) micChunk[i].toInt() else 0
                        val rawSpk = if (spkChunk != null && i < spkChunk.size) spkChunk[i].toInt() else 0
                        val s = (rawSpk * 1.35f).toInt()

                        val mixed = (m + s).coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort()
                        byteBuf[i * 2] = (mixed.toInt() and 0xFF).toByte()
                        byteBuf[i * 2 + 1] = ((mixed.toInt() shr 8) and 0xFF).toByte()
                    }

                    fos.write(byteBuf, 0, outByteLen)
                    audioRecordBytesWritten += outByteLen
                }

                fos.flush()
            } catch (e: Throwable) {
                Log.e(TAG, "VoipMixerWriter error: ${e.message}")
            }
        }, "VoipMixerWriter")

        uplinkThread = uThread
        downlinkThread = dThread
        mixerThread = mThread

        uThread.start()
        dThread.start()
        mThread.start()

        Log.i(TAG, "VoIP dual-stream mixer launched successfully with sampleRate=$sampleRate Mono")
        return true
    }

    private fun tryInitRecorderWithSource(pfd: ParcelFileDescriptor, source: Int, prefer3gp: Boolean = false): Boolean {
        try {
            android.system.Os.lseek(pfd.fileDescriptor, 0, android.system.OsConstants.SEEK_SET)
        } catch (ignored: Throwable) {}

        val runMpeg4 = {
            var rec: MediaRecorder? = null
            try {
                rec = createMediaRecorder()
                rec.apply {
                    setAudioSource(source)
                    setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                    setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                    try {
                        setAudioEncodingBitRate(128000)
                    } catch (ignored: Throwable) {}
                    setOutputFile(pfd.fileDescriptor)
                    prepare()
                    start()
                }
                recorder = rec
                true
            } catch (e: Throwable) {
                Log.w(TAG, "MediaRecorder MPEG-4/AAC with AudioSource $source failed: ${e.message}")
                try { rec?.reset() } catch (ignored: Throwable) {}
                try { rec?.release() } catch (ignored: Throwable) {}
                false
            }
        }

        val run3gp = {
            var rec: MediaRecorder? = null
            try {
                android.system.Os.lseek(pfd.fileDescriptor, 0, android.system.OsConstants.SEEK_SET)
            } catch (ignored: Throwable) {}

            try {
                rec = createMediaRecorder()
                rec.apply {
                    setAudioSource(source)
                    setOutputFormat(MediaRecorder.OutputFormat.THREE_GPP)
                    setAudioEncoder(MediaRecorder.AudioEncoder.AMR_WB)
                    setOutputFile(pfd.fileDescriptor)
                    prepare()
                    start()
                }
                recorder = rec
                true
            } catch (e: Throwable) {
                Log.w(TAG, "MediaRecorder THREE_GPP/AMR_WB with AudioSource $source failed: ${e.message}")
                try { rec?.reset() } catch (ignored: Throwable) {}
                try { rec?.release() } catch (ignored: Throwable) {}
                false
            }
        }

        return if (prefer3gp) {
            run3gp() || runMpeg4()
        } else {
            runMpeg4() || run3gp()
        }
    }

    private fun tryInitAudioRecordWithSource(
        pfd: ParcelFileDescriptor,
        source: Int,
        applyVoipBoost: Boolean = false
    ): Boolean {
        for (rate in listOf(48000, 16000, 44100)) {
            try {
                val minBuf = AudioRecord.getMinBufferSize(
                    rate,
                    AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT
                )
                if (minBuf <= 0) continue

                val bufSize = maxOf(minBuf * 2, 8192)

                val ctx = getEffectiveContext()
                val shellContext = if (ctx is ShellContextWrapper) ctx else if (ctx != null) ShellContextWrapper(ctx) else null

                val rec = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    val builder = AudioRecord.Builder()
                        .setAudioSource(source)
                        .setAudioFormat(
                            AudioFormat.Builder()
                                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                                .setSampleRate(rate)
                                .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
                                .build()
                        )
                        .setBufferSizeInBytes(bufSize)

                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && shellContext != null) {
                        try {
                            val setCtxMethod = AudioRecord.Builder::class.java.methods.firstOrNull {
                                it.name == "setContext" && it.parameterTypes.size == 1
                            }
                            setCtxMethod?.invoke(builder, shellContext)
                        } catch (ignored: Throwable) {}
                    }
                    builder.build()
                } else {
                    @Suppress("DEPRECATION")
                    AudioRecord(
                        source,
                        rate,
                        AudioFormat.CHANNEL_IN_MONO,
                        AudioFormat.ENCODING_PCM_16BIT,
                        bufSize
                    )
                }

                if (rec.state != AudioRecord.STATE_INITIALIZED) {
                    try { rec.release() } catch (ignored: Throwable) {}
                    continue
                }

                rec.startRecording()
                if (rec.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
                    Log.w(TAG, "AudioRecord failed transitioning to RECORDSTATE_RECORDING for source $source at $rate Hz")
                    try { rec.release() } catch (ignored: Throwable) {}
                    continue
                }

                try {
                    android.system.Os.lseek(pfd.fileDescriptor, 0, android.system.OsConstants.SEEK_SET)
                } catch (ignored: Throwable) {}

                val fos = FileOutputStream(pfd.fileDescriptor)
                activeSampleRate = rate
                writeWavHeader(fos, 0, 0, activeSampleRate, CHANNELS, BITS_PER_SAMPLE)
                fos.flush()

                audioRecord = rec
                isAudioRecordRunning = true
                audioRecordBytesWritten = 0L

                val thread = Thread({
                    val buffer = ByteArray(bufSize)
                    try {
                        while (isAudioRecordRunning) {
                            val readBytes = rec.read(buffer, 0, buffer.size)
                            if (readBytes > 0) {
                                if (applyVoipBoost) {
                                    applyDynamicVoipGain(buffer, readBytes)
                                }
                                fos.write(buffer, 0, readBytes)
                                audioRecordBytesWritten += readBytes
                            } else if (readBytes < 0) {
                                Log.w(TAG, "AudioRecord.read returned: $readBytes")
                                break
                            }
                        }
                        fos.flush()
                    } catch (e: Throwable) {
                        Log.e(TAG, "AudioRecord streaming thread error: ${e.message}")
                    }
                }, "AudioRecordCaptureThread")

                audioRecordThread = thread
                thread.start()

                Log.i(TAG, "AudioRecord capture started successfully with source $source at $rate Hz (applyVoipBoost=$applyVoipBoost)")
                return true
            } catch (e: Throwable) {
                Log.w(TAG, "AudioRecord setup failed for source $source at $rate Hz: ${e.message}")
            }
        }
        return false
    }

    /**
     * Real-time dynamic auto-gain with soft-knee limiter for VoIP call recordings.
     * Amplifies quiet remote audio (+10 dB) while softly limiting loud local microphone speech
     * so both callers are balanced and clearly heard in the final audio.
     */
    private fun applyDynamicVoipGain(buffer: ByteArray, length: Int) {
        var i = 0
        while (i < length - 1) {
            val sample = ((buffer[i + 1].toInt() shl 8) or (buffer[i].toInt() and 0xFF)).toShort()
            val absSample = kotlin.math.abs(sample.toInt())

            val boosted: Int = when {
                absSample < 2000 -> (sample * 4.2f).toInt()
                absSample < 6000 -> (sample * 3.0f).toInt()
                absSample < 14000 -> (sample * 1.8f).toInt()
                absSample < 22000 -> (sample * 1.2f).toInt()
                else -> {
                    val sign = if (sample >= 0) 1 else -1
                    val excess = absSample - 22000
                    val compressed = 22000 + (excess * 0.35f).toInt()
                    sign * minOf(compressed, 32767)
                }
            }

            val clamped = boosted.coerceIn(-32768, 32767).toShort()
            buffer[i] = (clamped.toInt() and 0xFF).toByte()
            buffer[i + 1] = ((clamped.toInt() shr 8) and 0xFF).toByte()
            i += 2
        }
    }

    private fun writeWavHeader(
        out: FileOutputStream,
        totalAudioLen: Long,
        totalDataLen: Long,
        longSampleRate: Int,
        channels: Int,
        bitsPerSample: Int
    ) {
        val byteRate = (longSampleRate * channels * bitsPerSample / 8).toLong()
        val header = ByteArray(44)
        val buf = ByteBuffer.wrap(header).order(ByteOrder.LITTLE_ENDIAN)

        // RIFF chunk descriptor
        buf.put('R'.code.toByte()).put('I'.code.toByte()).put('F'.code.toByte()).put('F'.code.toByte())
        buf.putInt((totalDataLen and 0xffffffffL).toInt())
        buf.put('W'.code.toByte()).put('A'.code.toByte()).put('V'.code.toByte()).put('E'.code.toByte())

        // "fmt " sub-chunk
        buf.put('f'.code.toByte()).put('m'.code.toByte()).put('t'.code.toByte()).put(' '.code.toByte())
        buf.putInt(16) // Subchunk1Size (16 for PCM)
        buf.putShort(1.toShort()) // AudioFormat (1 for PCM)
        buf.putShort(channels.toShort())
        buf.putInt(longSampleRate)
        buf.putInt((byteRate and 0xffffffffL).toInt())
        buf.putShort((channels * bitsPerSample / 8).toShort()) // block align
        buf.putShort(bitsPerSample.toShort())

        // "data" sub-chunk
        buf.put('d'.code.toByte()).put('a'.code.toByte()).put('t'.code.toByte()).put('a'.code.toByte())
        buf.putInt((totalAudioLen and 0xffffffffL).toInt())

        out.write(header, 0, 44)
    }

    private fun createMediaRecorder(): MediaRecorder {
        val ctx = getEffectiveContext()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (ctx != null) {
                try {
                    val wrapped = ShellContextWrapper(ctx)
                    Log.d(TAG, "Creating MediaRecorder with ShellContextWrapper (com.android.shell, UID 2000)")
                    return MediaRecorder(wrapped)
                } catch (e: Throwable) {
                    Log.w(TAG, "ShellContextWrapper failed: ${e.message}")
                }
            }
        }
        @Suppress("DEPRECATION")
        return MediaRecorder()
    }

    override fun stopRecording() {
        val token = android.os.Binder.clearCallingIdentity()
        try {
            stopRecordingInternal()
        } finally {
            android.os.Binder.restoreCallingIdentity(token)
        }
    }

    private fun stopRecordingInternal() {
        Log.i(TAG, "stopRecording called. isRecording=$isCurrentlyRecording")
        if (!isCurrentlyRecording && recorder == null && audioRecord == null && uplinkRecord == null && downlinkRecord == null && activeAudioPolicy == null) {
            return
        }

        // 1. Stop MediaRecorder if active
        try {
            recorder?.apply {
                try {
                    stop()
                    Log.i(TAG, "MediaRecorder stopped cleanly, header/moov written")
                } catch (e: RuntimeException) {
                    Log.w(TAG, "MediaRecorder.stop() threw RuntimeException: ${e.message}")
                }
                try {
                    release()
                } catch (e: Throwable) {
                    Log.w(TAG, "MediaRecorder.release() threw: ${e.message}")
                }
            }
        } catch (e: Throwable) {
            Log.e(TAG, "Error stopping MediaRecorder: ${e.message}")
        } finally {
            recorder = null
        }

        // 2. Stop single AudioRecord if active
        if (isAudioRecordRunning && audioRecord != null) {
            isAudioRecordRunning = false
            try {
                audioRecord?.stop()
                audioRecord?.release()
                Log.i(TAG, "AudioRecord stopped and released cleanly")
            } catch (e: Throwable) {
                Log.w(TAG, "AudioRecord stop/release threw: ${e.message}")
            }
            audioRecord = null

            try {
                audioRecordThread?.join(500)
            } catch (ignored: Throwable) {}
            audioRecordThread = null
        }

        // 3. Stop VoIP Dual-Stream (Mic + AudioPolicy Downlink) if active
        if (uplinkRecord != null || downlinkRecord != null || activeAudioPolicy != null) {
            isAudioRecordRunning = false
            try {
                uplinkRecord?.stop()
                uplinkRecord?.release()
                Log.i(TAG, "VoIP Uplink AudioRecord released")
            } catch (e: Throwable) {
                Log.w(TAG, "uplinkRecord stop/release threw: ${e.message}")
            }
            uplinkRecord = null

            try {
                downlinkRecord?.stop()
                downlinkRecord?.release()
                Log.i(TAG, "VoIP Downlink AudioRecord released")
            } catch (e: Throwable) {
                Log.w(TAG, "downlinkRecord stop/release threw: ${e.message}")
            }
            downlinkRecord = null

            if (activeAudioPolicy != null) {
                try {
                    val ctx = getEffectiveContext()
                    val audioManager = ctx?.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                    if (audioManager != null) {
                        val unreg = AudioManager::class.java.methods.firstOrNull {
                            it.name == "unregisterAudioPolicyAsync" || it.name == "unregisterAudioPolicy"
                        }
                        unreg?.invoke(audioManager, activeAudioPolicy)
                        Log.i(TAG, "Privileged AudioPolicy unregistered successfully")
                    }
                } catch (e: Throwable) {
                    Log.w(TAG, "Failed unregistering AudioPolicy: ${e.message}")
                }
                activeAudioPolicy = null
            }

            try { uplinkThread?.join(500) } catch (ignored: Throwable) {}
            try { downlinkThread?.join(500) } catch (ignored: Throwable) {}
            try { mixerThread?.join(500) } catch (ignored: Throwable) {}
            uplinkThread = null
            downlinkThread = null
            mixerThread = null
        }

        // Update WAV header with final size if audio data was written
        try {
            val fd = activePfd?.fileDescriptor
            if (fd != null && audioRecordBytesWritten > 0L) {
                val totalAudioLen = audioRecordBytesWritten
                val totalDataLen = totalAudioLen + 36
                val fos = FileOutputStream(fd)
                android.system.Os.lseek(fd, 0, android.system.OsConstants.SEEK_SET)
                writeWavHeader(fos, totalAudioLen, totalDataLen, activeSampleRate, CHANNELS, BITS_PER_SAMPLE)
                fos.flush()
                Log.i(TAG, "WAV header finalized: rate=$activeSampleRate, audioBytes=$totalAudioLen, totalBytes=${totalDataLen + 8}")
            }
        } catch (e: Throwable) {
            Log.w(TAG, "Failed updating WAV header: ${e.message}")
        } finally {
            audioRecordBytesWritten = 0L
        }

        isAudioRecordRunning = false
        isCurrentlyRecording = false
        activeSource = -1

        try {
            activePfd?.close()
        } catch (e: Throwable) {
            Log.w(TAG, "Error closing activePfd: ${e.message}")
        }
        activePfd = null
    }

    override fun isRecording(): Boolean = isCurrentlyRecording

    override fun setSpeakerphone(on: Boolean): Boolean {
        var success = false

        // 1. Force global hardware audio routing via AudioSystem.setParameters & setForceUse
        try {
            val audioSystemClass = Class.forName("android.media.AudioSystem")
            try {
                val setParametersMethod = audioSystemClass.getMethod("setParameters", String::class.java)
                setParametersMethod.invoke(null, if (on) "routing=2" else "routing=0")
                setParametersMethod.invoke(null, if (on) "speaker=on" else "speaker=off")
                setParametersMethod.invoke(null, if (on) "audio_devices=2" else "audio_devices=1")
                Log.i(TAG, "Privileged AudioSystem.setParameters applied via UID 2000 (speaker=$on)")
            } catch (ignored: Throwable) {}

            val setForceUseMethod = audioSystemClass.getMethod(
                "setForceUse",
                Int::class.javaPrimitiveType,
                Int::class.javaPrimitiveType
            )
            // 0 = FOR_COMMUNICATION, 1 = FORCE_SPEAKER, 0 = FORCE_NONE
            setForceUseMethod.invoke(null, 0, if (on) 1 else 0)
            // 2 = FOR_MEDIA, 1 = FORCE_SPEAKER, 0 = FORCE_NONE
            setForceUseMethod.invoke(null, 2, if (on) 1 else 0)
            // 1 = FOR_RECORD, 1 = FORCE_SPEAKER, 0 = FORCE_NONE
            setForceUseMethod.invoke(null, 1, if (on) 1 else 0)
            Log.i(TAG, "Privileged AudioSystem.setForceUse speakerphone=$on applied via UID 2000")
            success = true
        } catch (e: Throwable) {
            Log.w(TAG, "AudioSystem reflection failed: ${e.message}")
        }

        // 2. Also set communication device via AudioManager
        try {
            val ctx = getEffectiveContext()
            val audioManager = ctx?.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
            if (audioManager != null) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    if (on) {
                        val speaker = audioManager.availableCommunicationDevices.firstOrNull {
                            it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER
                        }
                        if (speaker != null) {
                            val ok = audioManager.setCommunicationDevice(speaker)
                            Log.i(TAG, "Privileged setCommunicationDevice(TYPE_BUILTIN_SPEAKER): $ok (UID 2000)")
                        }
                    } else {
                        audioManager.clearCommunicationDevice()
                        Log.i(TAG, "Privileged clearCommunicationDevice() (UID 2000)")
                    }
                }
                @Suppress("DEPRECATION")
                try { audioManager.isSpeakerphoneOn = on } catch (ignored: Throwable) {}

                if (on) {
                    val max = audioManager.getStreamMaxVolume(AudioManager.STREAM_VOICE_CALL)
                    audioManager.setStreamVolume(AudioManager.STREAM_VOICE_CALL, max, 0)
                }
                success = true
            }
        } catch (e: Throwable) {
            Log.e(TAG, "Privileged setSpeakerphone failed: ${e.message}")
        }

        // 3. Force media_session stream volume boost via UID 2000 shell command
        if (on) {
            try {
                Runtime.getRuntime().exec(arrayOf("cmd", "media_session", "volume", "--stream", "0", "--set", "15"))
                Runtime.getRuntime().exec(arrayOf("cmd", "media_session", "volume", "--stream", "3", "--set", "15"))
            } catch (ignored: Throwable) {}
        }

        return success
    }

    override fun isSpeakerphoneOn(): Boolean {
        val ctx = getEffectiveContext()
        val audioManager = ctx?.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return false
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            audioManager.communicationDevice?.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER
        } else {
            @Suppress("DEPRECATION")
            audioManager.isSpeakerphoneOn
        }
    }

    override fun isVoipRecordingActive(): Boolean {
        return try {
            val ctx = getEffectiveContext()
            val audioManager = ctx?.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return false
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                val configs = audioManager.activeRecordingConfigurations
                configs.any { cfg ->
                    val isVoiceComm = cfg.clientAudioSource == MediaRecorder.AudioSource.VOICE_COMMUNICATION
                    val isExternalVoipPkg = try {
                        val pkgMethod = cfg.javaClass.getMethod("getClientPackageName")
                        val pkg = pkgMethod.invoke(cfg) as? String ?: ""
                        pkg.contains("whatsapp", ignoreCase = true) || pkg.contains("telegram", ignoreCase = true)
                    } catch (e: Throwable) {
                        false
                    }
                    val isExternalUid = try {
                        val uidMethod = cfg.javaClass.getMethod("getClientUid")
                        val uid = uidMethod.invoke(cfg) as Int
                        uid != 2000 && uid != android.os.Process.myUid()
                    } catch (e: Throwable) {
                        true
                    }
                    (isVoiceComm && isExternalUid) || isExternalVoipPkg
                }
            } else {
                false
            }
        } catch (e: Throwable) {
            Log.w(TAG, "isVoipRecordingActive error: ${e.message}")
            false
        }
    }

    override fun destroy() {
        Log.i(TAG, "destroy() invoked on CallRecorderUserService")
        stopRecording()
    }
}
