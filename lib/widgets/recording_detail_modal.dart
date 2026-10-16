import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/recording_item.dart';
import '../services/audio_player_service.dart';
import '../services/shizuku_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import 'app_toast.dart';

class RecordingDetailModal extends StatefulWidget {
  final RecordingItem item;
  final VoidCallback onUpdated;

  const RecordingDetailModal({
    super.key,
    required this.item,
    required this.onUpdated,
  });

  static Future<void> show(BuildContext context, RecordingItem item, VoidCallback onUpdated) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RecordingDetailModal(item: item, onUpdated: onUpdated),
    );
  }

  @override
  State<RecordingDetailModal> createState() => _RecordingDetailModalState();
}

class _RecordingDetailModalState extends State<RecordingDetailModal> {
  late final TextEditingController _noteController;
  final AudioPlayerService _playerService = AudioPlayerService();
  final StorageService _storageService = StorageService();
  final ShizukuService _shizukuService = ShizukuService();

  bool _isEditingNote = false;

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController(text: widget.item.note ?? '');
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _saveNote() async {
    await _storageService.updateNote(widget.item.path, _noteController.text);
    widget.item.note = _noteController.text.trim().isEmpty ? null : _noteController.text.trim();
    setState(() => _isEditingNote = false);
    widget.onUpdated();
    if (mounted) {
      AppToast.showSuccess(context, 'Note updated successfully');
    }
  }

  Future<void> _showRenameDialog(BuildContext context) async {
    final controller = TextEditingController(text: widget.item.displayTitle);
    final colors = AppColors.of(context);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Rename Recording',
          style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: colors.textPrimary),
          decoration: InputDecoration(
            hintText: 'Enter title (e.g. WhatsApp Call)',
            hintStyle: TextStyle(color: colors.textMuted),
            filled: true,
            fillColor: colors.inputBg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colors.border),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: colors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      await _storageService.updateCustomTitle(widget.item.path, result);
      setState(() {
        widget.item.customTitle = result;
      });
      widget.onUpdated();
      if (mounted) {
        AppToast.showSuccess(context, 'Recording renamed successfully');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final item = widget.item;
    final isPlaying = _playerService.isPlaying(item.path);

    return Container(
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: BoxDecoration(
        color: colors.cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: colors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: colors.isDark ? 0.5 : 0.1),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Title & Copy Action
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _getCallTypeColor(item.callType).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _getCallTypeIcon(item.callType),
                  color: _getCallTypeColor(item.callType),
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.displayTitle,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: colors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.edit_outlined, size: 18, color: colors.textMuted),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: 'Rename recording',
                          onPressed: () => _showRenameDialog(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${item.callType} Call • ${item.formattedDate}',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  item.isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: item.isFavorite ? Colors.amber : colors.textMuted,
                  size: 28,
                ),
                onPressed: () async {
                  await _storageService.toggleFavorite(item.path);
                  setState(() => item.isFavorite = !item.isFavorite);
                  widget.onUpdated();
                },
              ),
            ],
          ),

          const SizedBox(height: 20),
          Divider(color: colors.divider, height: 1),
          const SizedBox(height: 16),

          // File Info Grid
          _buildInfoRow(Icons.straighten_rounded, 'File Size', item.formattedSize),
          const SizedBox(height: 10),
          _buildInfoRow(Icons.folder_open_rounded, 'File Name', item.name, canCopy: true),
          const SizedBox(height: 10),
          _buildInfoRow(Icons.link_rounded, 'Storage Path', item.path, canCopy: true),

          if (item.isTrash) ...[
            const SizedBox(height: 10),
            _buildInfoRow(
              Icons.delete_sweep_rounded,
              'Trash Status',
              'Auto-deletes in ${item.daysLeftInTrash(_storageService.settings.value.trashRetentionDays)} days',
              valueColor: Colors.amberAccent,
            ),
          ],

          const SizedBox(height: 16),
          Divider(color: colors.divider, height: 1),
          const SizedBox(height: 16),

          // Note Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Call Notes & Tags',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              if (!_isEditingNote)
                TextButton.icon(
                  icon: const Icon(Icons.edit_note, size: 18),
                  label: Text(item.note == null ? 'Add Note' : 'Edit'),
                  onPressed: () => setState(() => _isEditingNote = true),
                )
              else
                TextButton(
                  onPressed: _saveNote,
                  child: Text('Save', style: TextStyle(color: colors.primary)),
                ),
            ],
          ),
          if (_isEditingNote) ...[
            TextField(
              controller: _noteController,
              autofocus: true,
              maxLines: 2,
              style: TextStyle(color: colors.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'e.g. Discussed client contract details...',
                hintStyle: TextStyle(color: colors.textMuted),
                filled: true,
                fillColor: colors.subCardBg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colors.primary),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
            ),
          ] else if (item.note != null && item.note!.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.subCardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.border),
              ),
              child: Text(
                item.note!,
                style: TextStyle(color: colors.textPrimary, fontSize: 13),
              ),
            ),
          ] else ...[
            Text(
              'No note added. Tap "Add Note" to add tags or context.',
              style: TextStyle(color: colors.textMuted, fontSize: 12),
            ),
          ],

          const SizedBox(height: 24),

          // Action Buttons
          Row(
            children: [
              // Play/Pause button
              Expanded(
                child: ElevatedButton.icon(
                  icon: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                  label: Text(isPlaying ? 'Pause' : 'Play Audio'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () async {
                    if (isPlaying) {
                      await _playerService.pause();
                    } else {
                      await _playerService.play(item.path);
                    }
                    setState(() {});
                  },
                ),
              ),
              const SizedBox(width: 10),

              // Share button
              IconButton.filledTonal(
                icon: const Icon(Icons.share_rounded),
                style: IconButton.styleFrom(
                  backgroundColor: colors.chipBg,
                  foregroundColor: colors.textPrimary,
                  padding: const EdgeInsets.all(12),
                ),
                onPressed: () async {
                  await _shizukuService.shareRecording(item.path);
                },
              ),
              const SizedBox(width: 10),

              // Trash / Delete / Restore button
              if (item.isTrash)
                IconButton.filledTonal(
                  icon: const Icon(Icons.restore_from_trash_rounded, color: Colors.tealAccent),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.tealAccent.withValues(alpha: 0.15),
                    padding: const EdgeInsets.all(12),
                  ),
                  tooltip: 'Restore from Trash',
                  onPressed: () async {
                    final nav = Navigator.of(context);
                    await _storageService.restoreFromTrash(item.path);
                    widget.onUpdated();
                    if (mounted) nav.pop();
                  },
                )
              else
                IconButton.filledTonal(
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.redAccent.withValues(alpha: 0.15),
                    padding: const EdgeInsets.all(12),
                  ),
                  tooltip: 'Move to Trash',
                  onPressed: () async {
                    final nav = Navigator.of(context);
                    await _storageService.moveToTrash(item.path);
                    widget.onUpdated();
                    if (!context.mounted) return;
                    nav.pop();
                    AppToast.showInfo(
                      context,
                      'Moved to Trash (auto-purged in 30 days)',
                      actionLabel: 'Undo',
                      onAction: () async {
                        await _storageService.restoreFromTrash(item.path);
                        widget.onUpdated();
                      },
                    );
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, {bool canCopy = false, Color? valueColor}) {
    final colors = AppColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: colors.textSecondary),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(color: colors.textSecondary, fontSize: 12),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: valueColor ?? colors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (canCopy)
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: value));
              AppToast.showInfo(context, 'Copied $label to clipboard');
            },
            child: Icon(Icons.copy_rounded, size: 14, color: colors.primary),
          ),
      ],
    );
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
