import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class CallEvent {
  final String type; // "outgoing", "ringing", "connected", "started", "ended"
  final String? number;
  final String? callType;
  final String? fileName;
  final bool? recording;
  final String? path;

  CallEvent({
    required this.type,
    this.number,
    this.callType,
    this.fileName,
    this.recording,
    this.path,
  });
}

class ShizukuService {
  static final ShizukuService _instance = ShizukuService._internal();
  factory ShizukuService() => _instance;
  ShizukuService._internal() {
    _initChannel();
  }

  static const MethodChannel _channel = MethodChannel('com.example.record_mi/shizuku');

  final ValueNotifier<bool> isAlive = ValueNotifier<bool>(false);
  final ValueNotifier<bool> hasPermission = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isBound = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isRecording = ValueNotifier<bool>(false);

  final StreamController<CallEvent> _callEventController = StreamController<CallEvent>.broadcast();
  Stream<CallEvent> get callEvents => _callEventController.stream;

  void _initChannel() {
    _channel.setMethodCallHandler((call) async {
      debugPrint("ShizukuService received native callback: ${call.method} ${call.arguments}");
      final args = call.arguments as Map?;
      final num = args?['number'] as String?;

      switch (call.method) {
        case "onCallOutgoing":
          _callEventController.add(CallEvent(type: "outgoing", number: num));
          break;
        case "onCallRinging":
          final cType = args?['callType'] as String? ?? "incoming";
          _callEventController.add(CallEvent(type: "ringing", number: num, callType: cType));
          break;
        case "onCallConnected":
          final cType = args?['callType'] as String? ?? "cellular";
          _callEventController.add(CallEvent(type: "connected", number: num, callType: cType));
          break;
        case "onCallStarted":
          final rec = args?['recording'] as bool? ?? false;
          final cType = args?['callType'] as String? ?? "cellular";
          final fName = args?['fileName'] as String?;
          isRecording.value = rec;
          _callEventController.add(
            CallEvent(type: "started", number: num, callType: cType, fileName: fName, recording: rec),
          );
          break;
        case "onCallEnded":
          isRecording.value = false;
          final p = args?['path'] as String?;
          _callEventController.add(CallEvent(type: "ended", path: p));
          break;
        case "onServiceStatusChanged":
          final bound = args?['bound'] as bool? ?? false;
          isBound.value = bound;
          break;
        case "onRecordingStatusChanged":
          final rec = args?['recording'] as bool? ?? false;
          isRecording.value = rec;
          break;
      }
    });
  }

  Future<bool> ping() async {
    try {
      final alive = await _channel.invokeMethod<bool>('pingShizuku') ?? false;
      isAlive.value = alive;
      return alive;
    } catch (e) {
      isAlive.value = false;
      return false;
    }
  }

  Future<bool> checkStatus() async {
    try {
      final alive = await ping();
      if (!alive) {
        hasPermission.value = false;
        isBound.value = false;
        isRecording.value = false;
        return false;
      }

      final perm = await _channel.invokeMethod<bool>('checkPermission') ?? false;
      hasPermission.value = perm;

      final bound = await _channel.invokeMethod<bool>('isServiceBound') ?? false;
      isBound.value = bound;

      final rec = await _channel.invokeMethod<bool>('isRecording') ?? false;
      isRecording.value = rec;

      return bound;
    } catch (e) {
      debugPrint("ShizukuService checkStatus error: $e");
      return false;
    }
  }

  Future<bool> initShizuku() async {
    try {
      final res = await _channel.invokeMethod('initShizuku');
      // Wait up to 3 seconds for asynchronous binding to complete
      for (int i = 0; i < 7; i++) {
        await Future.delayed(const Duration(milliseconds: 400));
        final bound = await checkStatus();
        if (bound) return true;
      }
      return res == true;
    } catch (e) {
      debugPrint("ShizukuService initShizuku error: $e");
      return false;
    }
  }

  Future<bool> isShizukuInstalled() async {
    try {
      final installed = await _channel.invokeMethod<bool>('isShizukuInstalled') ?? false;
      return installed;
    } catch (e) {
      return false;
    }
  }

  Future<bool> openShizukuPlayStore() async {
    try {
      final opened = await _channel.invokeMethod<bool>('openShizukuPlayStore') ?? false;
      return opened;
    } catch (e) {
      debugPrint("ShizukuService openShizukuPlayStore error: $e");
      return false;
    }
  }

  Future<bool> requestPermission() async {
    try {
      final res = await _channel.invokeMethod('requestPermission');
      for (int i = 0; i < 7; i++) {
        await Future.delayed(const Duration(milliseconds: 400));
        final bound = await checkStatus();
        if (bound) return true;
      }
      return res == true;
    } catch (e) {
      debugPrint("ShizukuService requestPermission error: $e");
      return false;
    }
  }

  Future<bool> startRecord({
    String? fileName,
    String callType = "manual",
    int audioSource = -1,
  }) async {
    try {
      final name = fileName ?? "manual_${DateTime.now().millisecondsSinceEpoch}.m4a";
      final started = await _channel.invokeMethod<bool>('startRecord', {
        'fileName': name,
        'callType': callType,
        'audioSource': audioSource,
      }) ?? false;
      if (started) {
        isRecording.value = true;
      }
      return started;
    } catch (e) {
      debugPrint("ShizukuService startRecord error: $e");
      return false;
    }
  }

  Future<dynamic> stopRecord() async {
    try {
      final pathOrSuccess = await _channel.invokeMethod('stopRecord');
      isRecording.value = false;
      return pathOrSuccess;
    } catch (e) {
      debugPrint("ShizukuService stopRecord error: $e");
      isRecording.value = false;
      return null;
    }
  }

  Future<bool> toggleSpeakerphone() async {
    try {
      final state = await _channel.invokeMethod<bool>('toggleSpeakerphone') ?? false;
      return state;
    } catch (e) {
      debugPrint("ShizukuService toggleSpeakerphone error: $e");
      return false;
    }
  }

  Future<List<Map<dynamic, dynamic>>> getRecordings() async {
    try {
      final list = await _channel.invokeListMethod<Map<dynamic, dynamic>>('getRecordings');
      return list ?? [];
    } catch (e) {
      debugPrint("ShizukuService getRecordings error: $e");
      return [];
    }
  }

  Future<bool> deleteRecording(String path) async {
    try {
      final deleted = await _channel.invokeMethod<bool>('deleteRecording', {'path': path}) ?? false;
      return deleted;
    } catch (e) {
      debugPrint("ShizukuService deleteRecording error: $e");
      return false;
    }
  }

  Future<bool> shareRecording(String path) async {
    try {
      final shared = await _channel.invokeMethod<bool>('shareRecording', {'path': path}) ?? false;
      return shared;
    } catch (e) {
      debugPrint("ShizukuService shareRecording error: $e");
      return false;
    }
  }

  Future<bool> isSpeakerphoneOn() async {
    try {
      final on = await _channel.invokeMethod<bool>('isSpeakerphoneOn') ?? false;
      return on;
    } catch (e) {
      return false;
    }
  }

  Future<void> updateAppSettings({
    required bool autoRecord,
    required bool autoSpeakerphone,
    required bool recordVoipCalls,
    required bool voipAutoSpeakerphone,
    required String audioFormat,
    required int audioSource,
  }) async {
    try {
      await _channel.invokeMethod('updateAppSettings', {
        'autoRecord': autoRecord,
        'autoSpeakerphone': autoSpeakerphone,
        'recordVoipCalls': recordVoipCalls,
        'voipAutoSpeakerphone': voipAutoSpeakerphone,
        'audioFormat': audioFormat,
        'audioSource': audioSource,
      });
    } catch (e) {
      debugPrint("ShizukuService updateAppSettings error: $e");
    }
  }

  Future<void> updateVoipSettings({required bool recordVoip, required bool autoSpeakerphone}) async {
    try {
      await _channel.invokeMethod('updateVoipSettings', {
        'recordVoip': recordVoip,
        'autoSpeakerphone': autoSpeakerphone,
      });
    } catch (e) {
      debugPrint("ShizukuService updateVoipSettings error: $e");
    }
  }
}
