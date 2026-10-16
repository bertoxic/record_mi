import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:phone_state/phone_state.dart';

import '../models/recording_item.dart';
import '../services/audio_player_service.dart';
import '../services/shizuku_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_toast.dart';
import 'favorites_screen.dart';
import 'recordings_screen.dart';
import 'settings_screen.dart';
import 'trash_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  final StorageService _storageService = StorageService();
  final ShizukuService _shizukuService = ShizukuService();
  final AudioPlayerService _audioPlayerService = AudioPlayerService();

  int _currentIndex = 0;
  bool _isLoading = false;
  List<RecordingItem> _recordings = [];

  // Active call monitoring state
  String _callStatusType = "idle";
  String? _currentPhoneNumber;
  String _activeCallType = "incoming";

  StreamSubscription<CallEvent>? _callEventsSub;
  StreamSubscription<PhoneState>? _phoneSub;
  StreamSubscription<dynamic>? _overlaySub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _initApp();
  }

  Future<void> _initApp() async {
    await _storageService.init();
    await _storageService.autoPurgeExpiredTrash();
    await _requestPermissions();
    await _shizukuService.checkStatus();
    await _syncAllSettings();

    _setupCallEventListener();
    _listenToPhoneState();
    _listenToOverlayCommands();

    await _fetchRecordings();
  }

  Future<void> _syncAllSettings() async {
    final s = _storageService.settings.value;
    await _shizukuService.updateAppSettings(
      autoRecord: s.autoRecord,
      autoSpeakerphone: s.autoSpeakerphone,
      recordVoipCalls: s.recordVoipCalls,
      voipAutoSpeakerphone: s.voipAutoSpeakerphone,
      audioFormat: s.audioFormat,
      audioSource: s.audioSource,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _callEventsSub?.cancel();
    _phoneSub?.cancel();
    _overlaySub?.cancel();
    _audioPlayerService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _shizukuService.checkStatus();
      _storageService.autoPurgeExpiredTrash();
      _fetchRecordings();
    }
  }

  Future<void> _requestPermissions() async {
    try {
      await [
        Permission.phone,
        Permission.microphone,
        Permission.notification,
      ].request();

      if (!await FlutterOverlayWindow.isPermissionGranted()) {
        await FlutterOverlayWindow.requestPermission();
      }
    } catch (e) {
      debugPrint("Error requesting permissions: $e");
    }
  }

  void _setupCallEventListener() {
    _callEventsSub = _shizukuService.callEvents.listen((event) async {
      debugPrint("MainShell received CallEvent: ${event.type}");
      switch (event.type) {
        case "outgoing":
          if (mounted) {
            setState(() {
              _callStatusType = "outgoing";
              _currentPhoneNumber = event.number;
              _activeCallType = "outgoing";
            });
          }
          await _showFloatingPill();
          await _broadcastStateToOverlay();
          break;

        case "ringing":
          if (mounted) {
            setState(() {
              _callStatusType = "ringing";
              _currentPhoneNumber = event.number;
              _activeCallType = event.callType ?? "incoming";
            });
          }
          await _showFloatingPill();
          await _broadcastStateToOverlay();
          break;

        case "connected":
          if (mounted) {
            setState(() {
              _callStatusType = "active";
              final isVoip = event.callType == "voip";
              _activeCallType = isVoip ? "voip" : (event.callType ?? "cellular");
              if (isVoip) {
                _currentPhoneNumber = (event.number != null && event.number!.isNotEmpty && event.number != "Unknown")
                    ? event.number
                    : "WhatsApp Call";
              } else {
                _currentPhoneNumber = event.number ?? _currentPhoneNumber;
              }
            });
          }
          await _broadcastStateToOverlay();
          break;

        case "started":
          if (mounted) {
            setState(() {
              _callStatusType = "active";
              final isVoip = event.callType == "voip";
              _activeCallType = isVoip ? "voip" : (event.callType ?? "cellular");
              if (isVoip) {
                _currentPhoneNumber = (event.number != null && event.number!.isNotEmpty && event.number != "Unknown")
                    ? event.number
                    : "WhatsApp Call";
              } else {
                _currentPhoneNumber = event.number ?? _currentPhoneNumber;
              }
            });
          }
          await _showFloatingPill();
          await _broadcastStateToOverlay();
          break;

        case "ended":
          if (mounted) {
            setState(() {
              _callStatusType = "idle";
              _currentPhoneNumber = null;
              _activeCallType = "incoming";
            });
          }
          await FlutterOverlayWindow.closeOverlay();
          await _fetchRecordings();
          if (event.path != null && event.path!.isNotEmpty) {
            if (mounted) {
              AppToast.show(
                context,
                "Call recording saved successfully",
                type: ToastType.success,
              );
            }
          }
          break;
      }
    });
  }

  void _listenToPhoneState() {
    _phoneSub = PhoneState.stream.listen((PhoneState event) {
      if (!mounted) return;
      if (event.status == PhoneStateStatus.CALL_ENDED) {
        setState(() {
          _currentPhoneNumber = null;
        });
      } else if (event.number != null && event.number!.isNotEmpty) {
        setState(() {
          _currentPhoneNumber = event.number;
        });
      }
    });
  }

  void _listenToOverlayCommands() {
    _overlaySub = FlutterOverlayWindow.overlayListener.listen((event) async {
      debugPrint("Overlay event received in MainShell: $event");
      if (event == "REQUEST_CURRENT_STATE") {
        await _broadcastStateToOverlay();
      } else if (event == "STOP_CMD") {
        await _shizukuService.stopRecord();
        await _fetchRecordings();
        await _broadcastStateToOverlay();
      } else if (event == "START_CMD") {
        final isVoip = _activeCallType == "voip";
        final callNum = isVoip
            ? (_currentPhoneNumber ?? "WhatsApp Call")
            : (_currentPhoneNumber ?? "manual");
        final s = _storageService.settings.value;
        final ext = isVoip
            ? "wav"
            : (s.audioFormat.toLowerCase() == "wav"
                ? "wav"
                : (s.audioFormat.toLowerCase() == "3gp" ? "3gp" : "m4a"));
        final safeNum = callNum.replaceAll(RegExp(r'[^a-zA-Z0-9+]'), '_');
        final fileName = "call_${_activeCallType}_${safeNum}_${DateTime.now().millisecondsSinceEpoch}.$ext";
        await _shizukuService.startRecord(
          fileName: fileName,
          callType: isVoip ? "voip:$ext" : _activeCallType,
          audioSource: s.audioSource,
        );
        await _broadcastStateToOverlay();
      } else if (event == "SPEAKER_CMD") {
        final isSpeakerOn = await _shizukuService.toggleSpeakerphone();
        await FlutterOverlayWindow.shareData({
          'speakerOn': isSpeakerOn,
        });
      } else if (event == "DISMISS_CMD") {
        await FlutterOverlayWindow.closeOverlay();
      }
    });
  }

  Future<void> _showFloatingPill() async {
    try {
      final s = _storageService.settings.value;
      if (!s.floatingOverlayEnabled) {
        debugPrint("Floating overlay disabled by user in settings.");
        return;
      }
      if (!await FlutterOverlayWindow.isPermissionGranted()) {
        debugPrint("Overlay permission not granted.");
        return;
      }

      if (!(await FlutterOverlayWindow.isActive())) {
        final dpr = WidgetsBinding.instance.platformDispatcher.views.firstOrNull?.devicePixelRatio ?? 2.625;
        final int pillWidth = (360 * dpr).round();
        final int pillHeight = (85 * dpr).round();
        await FlutterOverlayWindow.showOverlay(
          enableDrag: true,
          overlayTitle: "Call Recorder Active",
          overlayContent: "Privileged audio capture enabled",
          flag: OverlayFlag.defaultFlag,
          alignment: OverlayAlignment.topCenter,
          startPosition: const OverlayPosition(0, 130),
          visibility: NotificationVisibility.visibilitySecret,
          positionGravity: PositionGravity.none,
          height: pillHeight,
          width: pillWidth,
        );
      }
    } catch (e) {
      debugPrint("Error showing overlay pill: $e");
    }
  }

  Future<void> _broadcastStateToOverlay() async {
    try {
      if (await FlutterOverlayWindow.isActive()) {
        final isSpeakerOn = await _shizukuService.isSpeakerphoneOn();
        final data = {
          'callState': _callStatusType,
          'number': _currentPhoneNumber,
          'isRecording': _shizukuService.isRecording.value,
          'callType': _activeCallType,
          'speakerOn': isSpeakerOn,
        };
        await FlutterOverlayWindow.shareData(data);
      }
    } catch (e) {
      debugPrint("Error broadcasting to overlay: $e");
    }
  }

  Future<void> _fetchRecordings() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final raw = await _shizukuService.getRecordings();
    final items = _storageService.mergeMetadata(raw);

    if (mounted) {
      setState(() {
        _recordings = items;
        _isLoading = false;
      });
    }
  }

  DateTime? _lastBackPressTime;

  void _navigateHome() {
    if (_currentIndex != 0) {
      HapticFeedback.lightImpact();
      setState(() => _currentIndex = 0);
    }
  }

  Widget _wrapWithSwipeBack(Widget child, int screenIndex) {
    if (screenIndex == 0) return child;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity != null && details.primaryVelocity! > 250) {
          _navigateHome();
        }
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final trashCount = _recordings.where((r) => r.isTrash).length;
    final favCount = _recordings.where((r) => r.isFavorite && !r.isTrash).length;

    final screens = [
      RecordingsScreen(
        recordings: _recordings,
        onRefresh: _fetchRecordings,
        isLoading: _isLoading,
      ),
      FavoritesScreen(
        recordings: _recordings,
        onRefresh: _fetchRecordings,
        onBackToHome: _navigateHome,
      ),
      TrashScreen(
        recordings: _recordings,
        onRefresh: _fetchRecordings,
        onBackToHome: _navigateHome,
      ),
      SettingsScreen(
        onSettingsChanged: () {
          _syncAllSettings();
          _fetchRecordings();
          setState(() {});
        },
        onBackToHome: _navigateHome,
      ),
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;

        // If on any non-recording screen (Favorites, Trash, Settings):
        // Swiping back always returns the user to the Recording screen (Home)
        if (_currentIndex != 0) {
          _navigateHome();
          return;
        }

        // On Home screen: double back tap within 2 seconds to exit app
        final now = DateTime.now();
        if (_lastBackPressTime == null || now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
          _lastBackPressTime = now;
          AppToast.showInfo(context, 'Press back again to exit');
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: colors.scaffoldBg,
        body: IndexedStack(
          index: _currentIndex,
          children: [
            screens[0],
            _wrapWithSwipeBack(screens[1], 1),
            _wrapWithSwipeBack(screens[2], 2),
            _wrapWithSwipeBack(screens[3], 3),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
          backgroundColor: colors.navBarBg,
          indicatorColor: colors.primary.withValues(alpha: colors.isDark ? 0.2 : 0.15),
          elevation: 8,
          destinations: [
            NavigationDestination(
              icon: Icon(Icons.mic_none_rounded, color: colors.navBarUnselectedIcon),
              selectedIcon: Icon(Icons.mic_rounded, color: colors.navBarSelectedIcon),
              label: 'Recordings',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: favCount > 0,
                label: Text('$favCount'),
                backgroundColor: Colors.amber,
                textColor: Colors.black,
                child: Icon(Icons.star_outline_rounded, color: colors.navBarUnselectedIcon),
              ),
              selectedIcon: const Icon(Icons.star_rounded, color: Colors.amber),
              label: 'Favorites',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: trashCount > 0,
                label: Text('$trashCount'),
                backgroundColor: Colors.redAccent,
                child: Icon(Icons.delete_outline_rounded, color: colors.navBarUnselectedIcon),
              ),
              selectedIcon: const Icon(Icons.delete_rounded, color: Colors.redAccent),
              label: 'Trash',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined, color: colors.navBarUnselectedIcon),
              selectedIcon: Icon(Icons.settings_rounded, color: colors.navBarSelectedIcon),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}
