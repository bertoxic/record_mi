import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import '../models/app_settings.dart';
import '../services/shizuku_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_toast.dart';
import '../widgets/batch_storage_manager_sheet.dart';
import 'onboarding_screen.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback onSettingsChanged;
  final VoidCallback? onBackToHome;

  const SettingsScreen({
    super.key,
    required this.onSettingsChanged,
    this.onBackToHome,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final StorageService _storageService = StorageService();
  final ShizukuService _shizukuService = ShizukuService();

  bool _isReconnecting = false;
  bool _overlayPermission = false;
  bool _isTestingOverlay = false;

  @override
  void initState() {
    super.initState();
    _checkOverlayPermission();
  }

  Future<void> _checkOverlayPermission() async {
    final granted = await FlutterOverlayWindow.isPermissionGranted();
    if (mounted) setState(() => _overlayPermission = granted);
  }

  Future<void> _update(AppSettings newSettings) async {
    await _storageService.updateSettings(newSettings);
    widget.onSettingsChanged();
    if (mounted) setState(() {});
  }

  Future<void> _reconnectShizuku() async {
    setState(() => _isReconnecting = true);
    await _shizukuService.initShizuku();
    await _shizukuService.checkStatus();
    if (mounted) {
      setState(() => _isReconnecting = false);
      if (_shizukuService.isBound.value) {
        AppToast.showSuccess(context, 'Shizuku Privileged Service Connected!');
      } else {
        AppToast.showError(context, 'Could not connect. Ensure Shizuku is running.');
      }
    }
  }

  Future<void> _toggleOverlayPreview() async {
    HapticFeedback.lightImpact();
    if (_isTestingOverlay) {
      await FlutterOverlayWindow.closeOverlay();
      if (mounted) setState(() => _isTestingOverlay = false);
    } else {
      if (!await FlutterOverlayWindow.isPermissionGranted()) {
        await FlutterOverlayWindow.requestPermission();
        await _checkOverlayPermission();
        if (!_overlayPermission) return;
      }
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
      if (mounted) setState(() => _isTestingOverlay = true);
      Future.delayed(const Duration(milliseconds: 250), () async {
        await FlutterOverlayWindow.shareData({
          'callState': 'active',
          'number': 'Preview Mode',
          'isRecording': false,
          'callType': 'test',
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final s = _storageService.settings.value;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        widget.onBackToHome?.call();
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity != null && details.primaryVelocity! > 250) {
            HapticFeedback.lightImpact();
            widget.onBackToHome?.call();
          }
        },
        child: Scaffold(
          backgroundColor: colors.scaffoldBg,
          appBar: AppBar(
            backgroundColor: colors.scaffoldBg,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            leading: widget.onBackToHome != null
                ? IconButton(
                    icon: Icon(Icons.arrow_back_rounded, color: colors.textPrimary),
                    tooltip: 'Back to Recordings',
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      widget.onBackToHome?.call();
                    },
                  )
                : null,
            title: Row(
              children: [
                Icon(Icons.tune_rounded, color: colors.primary, size: 26),
                const SizedBox(width: 10),
                Text(
                  'Settings & Config',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: colors.textPrimary),
                ),
              ],
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              // Section: Appearance & Theme
              _buildSectionHeader('Appearance & Theme', colors),
              _buildCard(
                colors: colors,
                children: [
                  SwitchListTile(
                    secondary: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 280),
                      child: Icon(
                        s.themeMode == 'light' ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                        key: ValueKey(s.themeMode),
                        color: s.themeMode == 'light' ? Colors.amber : colors.primary,
                        size: 26,
                      ),
                    ),
                    title: Text('Light Theme', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      s.themeMode == 'light' ? 'Bright & clean surface theme active' : 'Dark slate battery-saving theme active',
                      style: TextStyle(color: colors.textSecondary, fontSize: 12),
                    ),
                    value: s.themeMode == 'light',
                    activeTrackColor: colors.primary,
                    onChanged: (val) {
                      HapticFeedback.lightImpact();
                      _update(s.copyWith(themeMode: val ? 'light' : 'dark'));
                    },
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Section: Privileged Shizuku Engine
              _buildSectionHeader('Privileged Audio Capture (Shizuku)', colors),
              _buildShizukuStatusCard(colors),
              const SizedBox(height: 20),

              // Section: Call Recording Preferences
              _buildSectionHeader('Recording Options', colors),
              _buildCard(
                colors: colors,
                children: [
                  // Auto-Record Toggle
                  SwitchListTile(
                    title: Text('Auto-Record Calls', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      'Automatically captures incoming, outgoing, and WhatsApp calls',
                      style: TextStyle(color: colors.textSecondary, fontSize: 12),
                    ),
                    value: s.autoRecord,
                    activeTrackColor: colors.primary,
                    onChanged: (val) => _update(s.copyWith(autoRecord: val)),
                  ),
                  Divider(color: colors.divider, height: 1),

                  // Audio Format
                  ListTile(
                    title: Text('Audio Format', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      s.audioFormat.toUpperCase() == 'M4A'
                          ? 'M4A / AAC (High Quality & Small Size)'
                          : (s.audioFormat.toUpperCase() == 'WAV' ? 'WAV (Uncompressed PCM)' : '3GP / AMR'),
                      style: TextStyle(color: colors.textSecondary, fontSize: 12),
                    ),
                    trailing: DropdownButton<String>(
                      value: s.audioFormat,
                      dropdownColor: colors.cardBg,
                      style: TextStyle(color: colors.primary, fontWeight: FontWeight.bold),
                      underline: const SizedBox(),
                      items: const [
                        DropdownMenuItem(value: 'm4a', child: Text('M4A (AAC)')),
                        DropdownMenuItem(value: 'wav', child: Text('WAV (PCM)')),
                        DropdownMenuItem(value: '3gp', child: Text('3GP (AMR)')),
                      ],
                      onChanged: (val) {
                        if (val != null) _update(s.copyWith(audioFormat: val));
                      },
                    ),
                  ),
                  Divider(color: colors.divider, height: 1),

                  // Audio Source
                  ListTile(
                    title: Text('Audio Source', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      _getSourceDescription(s.audioSource),
                      style: TextStyle(color: colors.textSecondary, fontSize: 12),
                    ),
                    trailing: DropdownButton<int>(
                      value: s.audioSource,
                      dropdownColor: colors.cardBg,
                      style: TextStyle(color: colors.primary, fontWeight: FontWeight.bold),
                      underline: const SizedBox(),
                      items: const [
                        DropdownMenuItem(value: -1, child: Text('Auto (Optimized)')),
                        DropdownMenuItem(value: 6, child: Text('VOICE_RECOG (6)')),
                        DropdownMenuItem(value: 7, child: Text('VOICE_COMM (7)')),
                        DropdownMenuItem(value: 4, child: Text('VOICE_CALL (4)')),
                        DropdownMenuItem(value: 1, child: Text('MIC (1)')),
                      ],
                      onChanged: (val) {
                        if (val != null) _update(s.copyWith(audioSource: val));
                      },
                    ),
                  ),
                  Divider(color: colors.divider, height: 1),

                  // Standard Call Auto-Speakerphone
                  SwitchListTile(
                    title: Text('Auto-Speakerphone (Cellular)', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      'Toggles loudspeaker when cellular call is answered for clear 2-way recording',
                      style: TextStyle(color: colors.textSecondary, fontSize: 12),
                    ),
                    value: s.autoSpeakerphone,
                    activeTrackColor: colors.primary,
                    onChanged: (val) => _update(s.copyWith(autoSpeakerphone: val)),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Section: VoIP / WhatsApp Integration
              _buildSectionHeader('WhatsApp & VoIP Recording', colors),
              _buildCard(
                colors: colors,
                children: [
                  SwitchListTile(
                    title: Text('Record WhatsApp & VoIP', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      'Detects WhatsApp voice/video calls via Accessibility and captures conversation',
                      style: TextStyle(color: colors.textSecondary, fontSize: 12),
                    ),
                    value: s.recordVoipCalls,
                    activeTrackColor: colors.primary,
                    onChanged: (val) => _update(s.copyWith(recordVoipCalls: val)),
                  ),
                  Divider(color: colors.divider, height: 1),
                  SwitchListTile(
                    title: Text('VoIP Auto-Speakerphone', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      'Uses UID 2000 shell privileges to route WhatsApp call downlink to loudspeaker',
                      style: TextStyle(color: colors.textSecondary, fontSize: 12),
                    ),
                    value: s.voipAutoSpeakerphone,
                    activeTrackColor: colors.primary,
                    onChanged: (val) => _update(s.copyWith(voipAutoSpeakerphone: val)),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Section: Floating Control Pill (Overlay)
              _buildSectionHeader('In-Call Floating Control Pill', colors),
              _buildCard(
                colors: colors,
                children: [
                  SwitchListTile(
                    title: Text('Enable Floating Overlay', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      'Displays minimal draggable pill during calls to control recording and speaker',
                      style: TextStyle(color: colors.textSecondary, fontSize: 12),
                    ),
                    value: s.floatingOverlayEnabled,
                    activeTrackColor: colors.primary,
                    onChanged: (val) => _update(s.copyWith(floatingOverlayEnabled: val)),
                  ),
                  Divider(color: colors.divider, height: 1),
                  ListTile(
                    title: Text('Overlay Permission', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      _overlayPermission ? 'Granted (Ready to display)' : 'Not Granted (Tap to allow display over apps)',
                      style: TextStyle(color: _overlayPermission ? Colors.tealAccent : Colors.redAccent, fontSize: 12),
                    ),
                    trailing: _overlayPermission
                        ? const Icon(Icons.check_circle_rounded, color: Colors.tealAccent)
                        : TextButton(
                            child: const Text('Grant'),
                            onPressed: () async {
                              await FlutterOverlayWindow.requestPermission();
                              await _checkOverlayPermission();
                            },
                          ),
                  ),
                  Divider(color: colors.divider, height: 1),
                  ListTile(
                    leading: Icon(
                      _isTestingOverlay ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                      color: colors.primary,
                    ),
                    title: Text(
                      _isTestingOverlay ? 'Hide Overlay Preview' : 'Test Floating Overlay Pill',
                      style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      'Previews the live floating widget so you can test drag and toggles',
                      style: TextStyle(color: colors.textSecondary, fontSize: 12),
                    ),
                    trailing: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isTestingOverlay ? Colors.redAccent : colors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _toggleOverlayPreview,
                      child: Text(_isTestingOverlay ? 'Close' : 'Preview'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Section: Storage & Batch Audio Management
              _buildSectionHeader('Storage & Batch Audio Management', colors),
              _buildCard(
                colors: colors,
                children: [
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.checklist_rtl_rounded, color: colors.primary, size: 22),
                    ),
                    title: Text('Batch Delete & Clean Storage', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      'Tick checkboxes to bulk delete, trash, or purge recordings',
                      style: TextStyle(color: colors.textSecondary, fontSize: 12),
                    ),
                    trailing: Icon(Icons.chevron_right_rounded, color: colors.textSecondary),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      BatchStorageManagerSheet.show(
                        context,
                        onUpdated: () {
                          widget.onSettingsChanged();
                        },
                      );
                    },
                  ),
                  Divider(color: colors.divider, height: 1),

                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent, size: 22),
                    ),
                    title: Text('Empty Trash Bin Now', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      'Permanently delete all held trash items to free disk space',
                      style: TextStyle(color: colors.textSecondary, fontSize: 12),
                    ),
                    trailing: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: colors.cardBg,
                            title: Text('Empty Trash Bin?', style: TextStyle(color: colors.textPrimary)),
                            content: Text(
                              'This will permanently delete all trashed recordings from your phone.',
                              style: TextStyle(color: colors.textSecondary),
                            ),
                            actions: [
                              TextButton(
                                child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
                                onPressed: () => Navigator.pop(ctx, false),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                                child: const Text('Empty Trash', style: TextStyle(color: Colors.white)),
                                onPressed: () => Navigator.pop(ctx, true),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          final count = await _storageService.emptyTrash();
                          widget.onSettingsChanged();
                          if (context.mounted) {
                            AppToast.showSuccess(context, 'Permanently erased $count recordings');
                          }
                        }
                      },
                      child: const Text('Empty', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  Divider(color: colors.divider, height: 1),

                  ListTile(
                    title: Text('Auto-Purge Retention Period', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      'Recordings in trash are permanently erased after ${s.trashRetentionDays} days',
                      style: TextStyle(color: colors.textSecondary, fontSize: 12),
                    ),
                    trailing: DropdownButton<int>(
                      value: s.trashRetentionDays,
                      dropdownColor: colors.cardBg,
                      style: TextStyle(color: colors.primary, fontWeight: FontWeight.bold),
                      underline: const SizedBox(),
                      items: const [
                        DropdownMenuItem(value: 7, child: Text('7 Days')),
                        DropdownMenuItem(value: 14, child: Text('14 Days')),
                        DropdownMenuItem(value: 30, child: Text('30 Days (Default)')),
                        DropdownMenuItem(value: 60, child: Text('60 Days')),
                        DropdownMenuItem(value: 90, child: Text('90 Days')),
                      ],
                      onChanged: (val) {
                        if (val != null) _update(s.copyWith(trashRetentionDays: val));
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Section: General Preferences
              _buildSectionHeader('General & Localization', colors),
              _buildCard(
                colors: colors,
                children: [
                  // Language Selector
                  ListTile(
                    leading: Icon(Icons.language_rounded, color: colors.primary),
                    title: Text('App Language', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600)),
                    subtitle: Text(_getLanguageName(s.language), style: TextStyle(color: colors.textSecondary, fontSize: 12)),
                    trailing: DropdownButton<String>(
                      value: s.language,
                      dropdownColor: colors.cardBg,
                      style: TextStyle(color: colors.primary, fontWeight: FontWeight.bold),
                      underline: const SizedBox(),
                      items: const [
                        DropdownMenuItem(value: 'en', child: Text('English')),
                        DropdownMenuItem(value: 'es', child: Text('Español')),
                        DropdownMenuItem(value: 'fr', child: Text('Français')),
                        DropdownMenuItem(value: 'de', child: Text('Deutsch')),
                        DropdownMenuItem(value: 'zh', child: Text('中文')),
                        DropdownMenuItem(value: 'ar', child: Text('العربية')),
                        DropdownMenuItem(value: 'hi', child: Text('हिन्दी')),
                      ],
                      onChanged: (val) {
                        if (val != null) _update(s.copyWith(language: val));
                      },
                    ),
                  ),
                  Divider(color: colors.divider, height: 1),

                  // Replay Onboarding Intro
                  ListTile(
                    leading: const Icon(Icons.auto_stories_rounded, color: Colors.tealAccent),
                    title: Text('App Intro & Onboarding', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600)),
                    subtitle: Text('Review feature tour and setup guides', style: TextStyle(color: colors.textSecondary, fontSize: 12)),
                    trailing: Icon(Icons.chevron_right_rounded, color: colors.textSecondary),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const OnboardingScreen()),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // About Card
              _buildCard(
                colors: colors,
                children: [
                  ListTile(
                    leading: Icon(Icons.info_outline_rounded, color: colors.textSecondary),
                    title: Text('RecordMi Privileged Call Recorder', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600)),
                    subtitle: Text('Version 2.2 • Shizuku Shell UID 2000 Engine • Android 14 Ready', style: TextStyle(color: colors.textMuted, fontSize: 11)),
                  ),
                ],
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, AppColors colors) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: colors.primary,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  Widget _buildCard({required AppColors colors, required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: colors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.cardBorder),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildShizukuStatusCard(AppColors colors) {
    return ValueListenableBuilder<bool>(
      valueListenable: _shizukuService.isBound,
      builder: (context, isBound, _) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isBound
                  ? Colors.tealAccent.withValues(alpha: 0.5)
                  : Colors.redAccent.withValues(alpha: 0.5),
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isBound ? Colors.tealAccent : Colors.redAccent,
                      boxShadow: [
                        BoxShadow(
                          color: isBound ? Colors.tealAccent : Colors.redAccent,
                          blurRadius: 8,
                        )
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isBound ? 'Privileged Daemon Connected' : 'Daemon Disconnected',
                          style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        Text(
                          isBound
                              ? 'Running as UID 2000 (shell). Full 2-way call audio capture unlocked.'
                              : 'Shizuku privileged UserService is not bound.',
                          style: TextStyle(color: colors.textSecondary, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (!isBound) ...[
                    OutlinedButton.icon(
                      icon: const Icon(Icons.shop_two_rounded, size: 15),
                      label: const Text('Get Shizuku', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colors.primary,
                        side: BorderSide(color: colors.primary),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        _shizukuService.openShizukuPlayStore();
                      },
                    ),
                    const SizedBox(width: 8),
                  ],

                  ElevatedButton.icon(
                    icon: _isReconnecting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.refresh_rounded, size: 16),
                    label: Text(_isReconnecting ? 'Reconnecting...' : 'Reconnect Shizuku'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isBound ? colors.primary : Colors.teal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _isReconnecting ? null : _reconnectShizuku,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  String _getSourceDescription(int src) {
    switch (src) {
      case 6:
        return 'VOICE_RECOGNITION (6) - Unmutes Samsung One UI 6 hardware';
      case 7:
        return 'VOICE_COMMUNICATION (7) - VoIP & Echo Cancellation';
      case 4:
        return 'VOICE_CALL (4) - Privileged Uplink + Downlink';
      case 1:
        return 'MIC (1) - Standard Microphone';
      default:
        return 'Auto-Select (Samsung optimized 2-way capture)';
    }
  }

  String _getLanguageName(String lang) {
    switch (lang) {
      case 'es':
        return 'Español';
      case 'fr':
        return 'Français';
      case 'de':
        return 'Deutsch';
      case 'zh':
        return '中文 (Chinese)';
      case 'ar':
        return 'العربية (Arabic)';
      case 'hi':
        return 'हिन्दी (Hindi)';
      default:
        return 'English';
    }
  }
}
