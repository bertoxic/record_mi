import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class AudioPlayerService {
  static final AudioPlayerService _instance = AudioPlayerService._internal();
  factory AudioPlayerService() => _instance;
  AudioPlayerService._internal() {
    _init();
  }

  final AudioPlayer _player = AudioPlayer();

  final ValueNotifier<String?> currentlyPlayingPath = ValueNotifier<String?>(null);
  final ValueNotifier<PlayerState> playerState = ValueNotifier<PlayerState>(PlayerState.stopped);
  final ValueNotifier<Duration> position = ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<Duration> duration = ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<double> playbackRate = ValueNotifier<double>(1.0);

  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;

  void _init() {
    _stateSub = _player.onPlayerStateChanged.listen((state) {
      playerState.value = state;
      if (state == PlayerState.completed || state == PlayerState.stopped) {
        currentlyPlayingPath.value = null;
        position.value = Duration.zero;
      }
    });

    _posSub = _player.onPositionChanged.listen((pos) {
      position.value = pos;
    });

    _durSub = _player.onDurationChanged.listen((dur) {
      duration.value = dur;
    });
  }

  Future<void> play(String path) async {
    try {
      if (currentlyPlayingPath.value == path && playerState.value == PlayerState.paused) {
        await _player.resume();
      } else {
        await _player.stop();
        currentlyPlayingPath.value = path;
        position.value = Duration.zero;
        await _player.play(DeviceFileSource(path));
        if (playbackRate.value != 1.0) {
          await _player.setPlaybackRate(playbackRate.value);
        }
      }
    } catch (e) {
      debugPrint("AudioPlayerService play error: $e");
    }
  }

  Future<void> pause() async {
    try {
      await _player.pause();
    } catch (e) {
      debugPrint("AudioPlayerService pause error: $e");
    }
  }

  Future<void> resume() async {
    try {
      await _player.resume();
    } catch (e) {
      debugPrint("AudioPlayerService resume error: $e");
    }
  }

  Future<void> stop() async {
    try {
      await _player.stop();
      currentlyPlayingPath.value = null;
      position.value = Duration.zero;
    } catch (e) {
      debugPrint("AudioPlayerService stop error: $e");
    }
  }

  Future<void> seek(Duration newPos) async {
    try {
      await _player.seek(newPos);
    } catch (e) {
      debugPrint("AudioPlayerService seek error: $e");
    }
  }

  Future<void> seekRelative(Duration delta) async {
    try {
      final cur = position.value;
      final dur = duration.value;
      final targetMs = (cur.inMilliseconds + delta.inMilliseconds).clamp(0, dur.inMilliseconds > 0 ? dur.inMilliseconds : 0);
      await _player.seek(Duration(milliseconds: targetMs));
    } catch (e) {
      debugPrint("AudioPlayerService seekRelative error: $e");
    }
  }

  Future<void> setPlaybackRate(double rate) async {
    try {
      playbackRate.value = rate;
      await _player.setPlaybackRate(rate);
    } catch (e) {
      debugPrint("AudioPlayerService setPlaybackRate error: $e");
    }
  }

  bool isPlaying(String path) {
    return currentlyPlayingPath.value == path && playerState.value == PlayerState.playing;
  }

  bool isCurrent(String path) {
    return currentlyPlayingPath.value == path;
  }

  void dispose() {
    _stateSub?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _player.dispose();
  }
}
