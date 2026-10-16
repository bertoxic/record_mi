import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import '../models/recording_item.dart';
import '../services/audio_player_service.dart';
import '../services/shizuku_service.dart';
import '../services/storage_service.dart';
import 'app_toast.dart';
import 'recording_detail_modal.dart';
import '../theme/app_theme.dart';

class RecordingTile extends StatefulWidget {
  final RecordingItem item;
  final VoidCallback onUpdated;
  final bool isTrashView;
  final bool isSelectionMode;
  final bool isSelected;
  final ValueChanged<bool?>? onSelectChanged;
  final VoidCallback? onLongPress;

  const RecordingTile({
    super.key,
    required this.item,
    required this.onUpdated,
    this.isTrashView = false,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onSelectChanged,
    this.onLongPress,
  });

  @override
  State<RecordingTile> createState() => _RecordingTileState();
}

class _RecordingTileState extends State<RecordingTile> with SingleTickerProviderStateMixin {
  late final AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
  }

  @override
  void dispose() {
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playerService = AudioPlayerService();
    final storageService = StorageService();
    final shizukuService = ShizukuService();

    final item = widget.item;
    final callColor = _getCallTypeColor(item.callType);
    final callIcon = _getCallTypeIcon(item.callType);

    return ValueListenableBuilder<String?>(
      valueListenable: playerService.currentlyPlayingPath,
      builder: (context, playingPath, _) {
        final isCurrentTrack = playingPath == item.path;

        return ValueListenableBuilder<PlayerState>(
          valueListenable: playerService.playerState,
          builder: (context, playerState, _) {
            final isPlaying = isCurrentTrack && playerState == PlayerState.playing;

            if (isPlaying) {
              if (!_waveController.isAnimating) {
                _waveController.repeat();
              }
            } else {
              if (_waveController.isAnimating) {
                _waveController.stop();
              }
            }

            final colors = AppColors.of(context);

            return AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                color: widget.isSelected
                    ? colors.primary.withValues(alpha: 0.14)
                    : (isCurrentTrack
                        ? colors.cardBg
                        : colors.cardBg.withValues(alpha: colors.isDark ? 0.6 : 0.95)),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: widget.isSelected
                      ? colors.primary
                      : (isCurrentTrack
                          ? colors.primary.withValues(alpha: 0.6)
                          : colors.cardBorder),
                  width: (widget.isSelected || isCurrentTrack) ? 1.5 : 1.0,
                ),
                boxShadow: (widget.isSelected || isCurrentTrack)
                    ? [
                        BoxShadow(
                          color: colors.primary.withValues(alpha: colors.isDark ? 0.14 : 0.08),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        )
                      ]
                    : null,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Main Item Row
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    onTap: widget.isSelectionMode
                        ? () {
                            HapticFeedback.selectionClick();
                            widget.onSelectChanged?.call(!widget.isSelected);
                          }
                        : null,
                    onLongPress: () {
                      HapticFeedback.heavyImpact();
                      widget.onLongPress?.call();
                    },
                    // Checkbox in selection mode OR Animated Play / Pause Button
                    leading: widget.isSelectionMode
                        ? GestureDetector(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              widget.onSelectChanged?.call(!widget.isSelected);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: widget.isSelected
                                    ? colors.primary
                                    : colors.cardBg,
                                border: Border.all(
                                  color: widget.isSelected
                                      ? colors.primary
                                      : colors.border,
                                  width: 1.8,
                                ),
                              ),
                              child: widget.isSelected
                                  ? const Icon(Icons.check_rounded, color: Colors.white, size: 24)
                                  : Icon(Icons.circle_outlined, color: colors.textMuted, size: 22),
                            ),
                          )
                        : GestureDetector(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              if (isPlaying) {
                                playerService.pause();
                              } else {
                                playerService.play(item.path);
                              }
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isPlaying
                                    ? colors.primary
                                    : callColor.withValues(alpha: colors.isDark ? 0.15 : 0.12),
                                border: Border.all(
                                  color: isPlaying
                                      ? colors.primary
                                      : callColor.withValues(alpha: 0.4),
                                  width: 1.5,
                                ),
                                boxShadow: isPlaying
                                    ? [
                                        BoxShadow(
                                          color: colors.primary.withValues(alpha: 0.35),
                                          blurRadius: 10,
                                          spreadRadius: 1,
                                        )
                                      ]
                                    : null,
                              ),
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                                child: Icon(
                                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                  key: ValueKey<bool>(isPlaying),
                                  color: isPlaying ? Colors.white : callColor,
                                  size: 24,
                                ),
                              ),
                            ),
                          ),

                    // Contact Title & Call Type Pill
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.displayTitle,
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 14.5,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: callColor.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(callIcon, size: 10, color: callColor),
                              const SizedBox(width: 3),
                              Text(
                                item.callType,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: callColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    // Subtitle: Overflow-Proof Metadata String & Note Chip
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 3),
                        // Using a single Text widget with ellipsis guarantees 0.0px overflow on all screens!
                        Text(
                          '${item.formattedDate} • ${item.formattedSize}',
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (item.note != null && item.note!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.sticky_note_2_outlined, size: 11, color: Colors.amberAccent),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  item.note!,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.amberAccent,
                                    fontStyle: FontStyle.italic,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),

                    // Trailing Action Buttons (Compact constraints prevent squeezing subtitle)
                    trailing: widget.isSelectionMode
                        ? Checkbox(
                            value: widget.isSelected,
                            activeColor: colors.primary,
                            checkColor: Colors.white,
                            side: BorderSide(color: colors.border, width: 1.5),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                            onChanged: (val) {
                              HapticFeedback.selectionClick();
                              widget.onSelectChanged?.call(val);
                            },
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!widget.isTrashView) ...[
                          // Star Favorite Button
                          IconButton(
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            padding: const EdgeInsets.all(4),
                            icon: Icon(
                              item.isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                              color: item.isFavorite ? Colors.amber : colors.textMuted,
                              size: 21,
                            ),
                            tooltip: item.isFavorite ? 'Unstar' : 'Star',
                            onPressed: () async {
                              HapticFeedback.lightImpact();
                              await storageService.toggleFavorite(item.path);
                              item.isFavorite = !item.isFavorite;
                              widget.onUpdated();
                            },
                          ),
                          // Native Share Button
                          IconButton(
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            padding: const EdgeInsets.all(4),
                            icon: Icon(Icons.share_outlined, color: colors.textSecondary, size: 19),
                            tooltip: 'Share',
                            onPressed: () async {
                              HapticFeedback.lightImpact();
                              await shizukuService.shareRecording(item.path);
                            },
                          ),
                          // Details & More Menu
                          PopupMenuButton<String>(
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            padding: const EdgeInsets.all(4),
                            icon: Icon(Icons.more_vert_rounded, color: colors.textSecondary, size: 19),
                            color: colors.cardBg,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            onSelected: (val) async {
                              if (val == 'info') {
                                RecordingDetailModal.show(context, item, widget.onUpdated);
                              } else if (val == 'trash') {
                                await storageService.moveToTrash(item.path);
                                widget.onUpdated();
                                if (context.mounted) {
                                  AppToast.showInfo(
                                    context,
                                    'Moved to Trash',
                                    actionLabel: 'Undo',
                                    onAction: () async {
                                      await storageService.restoreFromTrash(item.path);
                                      widget.onUpdated();
                                    },
                                  );
                                }
                              }
                            },
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: 'info',
                                child: Row(
                                  children: [
                                    Icon(Icons.info_outline, size: 18, color: colors.textSecondary),
                                    const SizedBox(width: 10),
                                    Text('Details & Notes', style: TextStyle(color: colors.textPrimary)),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'trash',
                                child: Row(
                                  children: [
                                    Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                                    SizedBox(width: 10),
                                    Text('Move to Trash', style: TextStyle(color: Colors.redAccent)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ] else ...[
                          // In Trash View: Restore & Delete Forever
                          IconButton(
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            padding: const EdgeInsets.all(4),
                            icon: const Icon(Icons.restore_from_trash_rounded, color: Colors.tealAccent, size: 21),
                            tooltip: 'Restore',
                            onPressed: () async {
                              HapticFeedback.lightImpact();
                              await storageService.restoreFromTrash(item.path);
                              widget.onUpdated();
                            },
                          ),
                          IconButton(
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            padding: const EdgeInsets.all(4),
                            icon: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent, size: 21),
                            tooltip: 'Delete Forever',
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  backgroundColor: colors.cardBg,
                                  title: Text('Delete Permanently?', style: TextStyle(color: colors.textPrimary)),
                                  content: Text(
                                    'This recording will be immediately erased from device storage and cannot be recovered.',
                                    style: TextStyle(color: colors.textSecondary),
                                  ),
                                  actions: [
                                    TextButton(
                                      child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
                                      onPressed: () => Navigator.pop(ctx, false),
                                    ),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                                      child: const Text('Delete', style: TextStyle(color: Colors.white)),
                                      onPressed: () => Navigator.pop(ctx, true),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                await storageService.deletePermanently(item.path);
                                widget.onUpdated();
                              }
                            },
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Smooth Animated Drawer with Audio Visualizer & Millisecond Precision Scrubbing
                  AnimatedSize(
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeInOutCubic,
                    child: isCurrentTrack
                        ? _buildPlaybackDrawer(playerService, isPlaying)
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPlaybackDrawer(AudioPlayerService playerService, bool isPlaying) {
    final colors = AppColors.of(context);

    return Padding(
      padding: const EdgeInsets.only(left: 14, right: 14, bottom: 10, top: 2),
      child: ValueListenableBuilder<Duration>(
        valueListenable: playerService.position,
        builder: (context, pos, _) {
          return ValueListenableBuilder<Duration>(
            valueListenable: playerService.duration,
            builder: (context, dur, _) {
              final durMs = dur.inMilliseconds > 0 ? dur.inMilliseconds.toDouble() : 1.0;
              final posMs = pos.inMilliseconds.toDouble().clamp(0.0, durMs);

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Divider(color: colors.divider, height: 1),
                  const SizedBox(height: 8),

                  // Animated Waveform Sound Visualizer
                  _WaveformVisualizer(
                    controller: _waveController,
                    isPlaying: isPlaying,
                    progress: posMs / durMs,
                  ),
                  const SizedBox(height: 4),

                  // Continuous Millisecond Precision Slider
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3.0,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                      activeTrackColor: colors.primary,
                      inactiveTrackColor: colors.audioProgressBg,
                      thumbColor: colors.primary,
                    ),
                    child: Slider(
                      min: 0.0,
                      max: durMs,
                      value: posMs,
                      onChanged: (val) {
                        playerService.seek(Duration(milliseconds: val.toInt()));
                      },
                    ),
                  ),

                  // Controls Row: -5s, +5s, Speed Selector, and Timestamps
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      children: [
                        // Elapsed Time
                        Text(
                          _formatDuration(pos),
                          style: TextStyle(
                            color: colors.primary,
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                        ),
                        const Spacer(),

                        // Rewind -5s
                        InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            HapticFeedback.lightImpact();
                            playerService.seekRelative(const Duration(seconds: -5));
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            child: Row(
                              children: [
                                Icon(Icons.replay_5_rounded, size: 16, color: colors.textSecondary),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Fast-forward +5s
                        InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            HapticFeedback.lightImpact();
                            playerService.seekRelative(const Duration(seconds: 5));
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            child: Row(
                              children: [
                                Icon(Icons.forward_5_rounded, size: 16, color: colors.textSecondary),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Playback Speed Toggle Pill (1.0x -> 1.25x -> 1.5x -> 2.0x)
                        ValueListenableBuilder<double>(
                          valueListenable: playerService.playbackRate,
                          builder: (context, rate, _) {
                            return InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () {
                                HapticFeedback.selectionClick();
                                final nextRate = rate == 1.0
                                    ? 1.25
                                    : (rate == 1.25 ? 1.5 : (rate == 1.5 ? 2.0 : 1.0));
                                playerService.setPlaybackRate(nextRate);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: colors.chipBg,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: colors.chipBorder),
                                ),
                                child: Text(
                                  '${rate}x',
                                  style: TextStyle(
                                    color: colors.textPrimary,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        const Spacer(),

                        // Total Duration
                        Text(
                          _formatDuration(dur),
                          style: TextStyle(
                            color: colors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Color _getCallTypeColor(String type) {
    switch (type.toLowerCase()) {
      case 'incoming':
        return Colors.greenAccent;
      case 'outgoing':
        return const Color(0xFF38BDF8);
      case 'voip':
        return Colors.tealAccent;
      case 'group':
        return Colors.purpleAccent;
      default:
        return Colors.orangeAccent;
    }
  }

  IconData _getCallTypeIcon(String type) {
    switch (type.toLowerCase()) {
      case 'incoming':
        return Icons.call_received_rounded;
      case 'outgoing':
        return Icons.call_made_rounded;
      case 'voip':
        return Icons.chat_bubble_outline_rounded;
      case 'group':
        return Icons.group_rounded;
      default:
        return Icons.mic_rounded;
    }
  }
}

/// Dynamic, 60fps audio waveform visualizer bars
class _WaveformVisualizer extends StatelessWidget {
  final AnimationController controller;
  final bool isPlaying;
  final double progress;

  const _WaveformVisualizer({
    required this.controller,
    required this.isPlaying,
    required this.progress,
  });

  static const List<double> _baseHeights = [
    0.35, 0.65, 0.45, 0.85, 0.55, 0.95, 0.4, 0.75,
    0.6, 0.85, 0.5, 0.9, 0.7, 0.45, 0.8, 0.6,
    0.75, 0.5, 0.9, 0.4, 0.65, 0.85, 0.45, 0.35
  ];

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final phase = controller.value * 2 * math.pi;

        return SizedBox(
          height: 22,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(_baseHeights.length, (index) {
              final barProgress = index / _baseHeights.length;
              final isPlayed = barProgress <= progress;

              double heightFactor = _baseHeights[index];
              if (isPlaying) {
                final oscillation = math.sin(phase + (index * 0.4)) * 0.35;
                heightFactor = (heightFactor + oscillation).clamp(0.2, 1.0);
              } else {
                heightFactor = (heightFactor * 0.5).clamp(0.2, 0.5);
              }

              return AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                width: 2.5,
                height: 22 * heightFactor,
                decoration: BoxDecoration(
                  color: isPlayed
                      ? colors.primary
                      : colors.audioProgressBg,
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}
