import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

class MicroRecordingPill extends StatefulWidget {
  const MicroRecordingPill({super.key});

  @override
  State<MicroRecordingPill> createState() => _MicroRecordingPillState();
}

class _MicroRecordingPillState extends State<MicroRecordingPill>
    with SingleTickerProviderStateMixin {
  bool _isRecording = false;
  bool _isSpeakerOn = false;
  int _seconds = 0;
  Timer? _timer;
  late AnimationController _animController;
  StreamSubscription<dynamic>? _overlayDataSubscription;

  String _callState = "active"; // "ringing", "outgoing", "active", "paused"
  String? _phoneNumber;
  String _callType = "incoming";

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    // Request latest call and recording state from main app immediately on overlay mount
    FlutterOverlayWindow.shareData("REQUEST_CURRENT_STATE");

    _overlayDataSubscription =
        FlutterOverlayWindow.overlayListener.listen((data) {
      if (data is Map) {
        final state = data['callState'] as String? ?? _callState;
        final num = data['number'] as String? ?? _phoneNumber;
        final recording = data['isRecording'] as bool? ?? _isRecording;
        final type = data['callType'] as String? ?? _callType;
        final speaker = data['speakerOn'] as bool? ?? _isSpeakerOn;

        setState(() {
          _callState = state;
          _phoneNumber = num;
          _callType = type;
          _isRecording = recording;
          _isSpeakerOn = speaker;
        });

        if (recording && _timer == null) {
          _startTimer();
        } else if (!recording && _timer != null) {
          _stopTimer();
        }
      } else if (data == "RECORDING_STARTED") {
        setState(() => _isRecording = true);
        _startTimer();
      } else if (data == "RECORDING_STOPPED") {
        setState(() => _isRecording = false);
        _stopTimer();
      }
    });
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _stopTimer();
    _overlayDataSubscription?.cancel();
    _animController.dispose();
    super.dispose();
  }

  String get _formattedTime {
    final mins = (_seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (_seconds % 60).toString().padLeft(2, '0');
    return "$mins:$secs";
  }

  String _getDisplayLabel() {
    if (_isRecording) {
      final suffix = _phoneNumber != null ? " • ${_formatShortNumber(_phoneNumber!)}" : "";
      return "REC $_formattedTime$suffix";
    }
    if (_callState == "ringing") {
      if (_callType == "voip") {
        return "WhatsApp Ringing...";
      }
      final suffix = _phoneNumber != null ? " ${_formatShortNumber(_phoneNumber!)}" : "";
      return "Ringing$suffix";
    }
    if (_callState == "outgoing") {
      final suffix = _phoneNumber != null ? " ${_formatShortNumber(_phoneNumber!)}" : "";
      return "Calling$suffix";
    }
    if (_callType == "voip") {
      return "WhatsApp Call";
    }
    if (_callType == "group") {
      return "Group Call";
    }
    return "Call Active";
  }

  String _formatShortNumber(String n) {
    if (n.length <= 10) return n;
    if (n.contains("(") && n.contains(")")) {
      final name = n.split("(")[0].trim();
      if (name.length <= 10) return name;
      return "${name.substring(0, 8)}..";
    }
    return "...${n.substring(n.length - 6)}";
  }

  Color _getBadgeColor() {
    if (_isRecording) return const Color(0xFFF43F5E); // Ruby Rose
    if (_callType == "voip") return const Color(0xFF25D366); // WhatsApp green
    if (_callState == "ringing") return const Color(0xFFFBBF24); // Amber
    if (_callState == "outgoing") return const Color(0xFF38BDF8); // Cyan
    return const Color(0xFF2DD4BF); // Teal
  }

  IconData _getBadgeIcon() {
    if (_isRecording) return Icons.fiber_manual_record;
    if (_callState == "ringing") return Icons.ring_volume_rounded;
    if (_callState == "outgoing") return Icons.call_made_rounded;
    if (_callType == "voip") return Icons.phone_in_talk_rounded;
    return Icons.phone_in_talk_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final badgeColor = _getBadgeColor();

    return Material(
      color: Colors.transparent,
      child: Center(
        child: Container(
          constraints: const BoxConstraints(
            maxWidth: 350,
            maxHeight: 52,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFA0F172A), Color(0xFA1E293B)],
            ),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: badgeColor.withValues(alpha: 0.75),
              width: 1.2,
            ),
            boxShadow: [
              const BoxShadow(
                color: Color(0x99000000),
                blurRadius: 16,
                offset: Offset(0, 4),
              ),
              BoxShadow(
                color: badgeColor.withValues(alpha: 0.2),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Pulsing Status Indicator
              FadeTransition(
                opacity: _animController,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _getBadgeIcon(),
                    color: badgeColor,
                    size: 13,
                  ),
                ),
              ),
              const SizedBox(width: 6),

              // Status & Timer Display (overflow-proof with strict constraints and ellipsis)
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 130),
                  child: Text(
                    _getDisplayLabel(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      letterSpacing: 0.1,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 6),

              // Speakerphone Toggle Button (Boosts other party's voice for crystal clear 2-way audio)
              GestureDetector(
                onTap: () {
                  setState(() => _isSpeakerOn = !_isSpeakerOn);
                  FlutterOverlayWindow.shareData("SPEAKER_CMD");
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    color: _isSpeakerOn
                        ? const Color(0xFF38BDF8)
                        : Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _isSpeakerOn
                          ? const Color(0xFF38BDF8)
                          : Colors.white24,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isSpeakerOn ? Icons.volume_up_rounded : Icons.volume_up_outlined,
                        color: _isSpeakerOn
                            ? const Color(0xFF0F172A)
                            : (_callType == "voip" ? const Color(0xFF38BDF8) : Colors.white70),
                        size: 14,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        _isSpeakerOn ? "ON" : (_callType == "voip" ? "2-WAY" : "SPK"),
                        style: TextStyle(
                          color: _isSpeakerOn
                              ? const Color(0xFF0F172A)
                              : (_callType == "voip" ? const Color(0xFF38BDF8) : Colors.white70),
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),

              // Record / Stop Action Button
              GestureDetector(
                onTap: () {
                  if (_isRecording) {
                    FlutterOverlayWindow.shareData("STOP_CMD");
                  } else {
                    FlutterOverlayWindow.shareData("START_CMD");
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: _isRecording
                        ? const Color(0xFFF43F5E).withValues(alpha: 0.25)
                        : const Color(0xFF2DD4BF).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _isRecording ? const Color(0xFFF43F5E) : const Color(0xFF2DD4BF),
                      width: 1.2,
                    ),
                  ),
                  child: Icon(
                    _isRecording ? Icons.stop_rounded : Icons.fiber_manual_record,
                    color: _isRecording ? const Color(0xFFF43F5E) : const Color(0xFF2DD4BF),
                    size: 14,
                  ),
                ),
              ),
              const SizedBox(width: 6),

              // Dismiss / Close Pill Button (X)
              GestureDetector(
                onTap: () {
                  FlutterOverlayWindow.shareData("DISMISS_CMD");
                },
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    color: Colors.white60,
                    size: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
