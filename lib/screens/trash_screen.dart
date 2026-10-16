import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/recording_item.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_toast.dart';
import '../widgets/recording_tile.dart';

class TrashScreen extends StatefulWidget {
  final List<RecordingItem> recordings;
  final VoidCallback onRefresh;
  final VoidCallback? onBackToHome;

  const TrashScreen({
    super.key,
    required this.recordings,
    required this.onRefresh,
    this.onBackToHome,
  });

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  final StorageService _storageService = StorageService();

  bool _inSelectionMode = false;
  final Set<String> _selectedPaths = {};

  bool get _isSelectionMode => _inSelectionMode || _selectedPaths.isNotEmpty;

  void _toggleSelection(String path) {
    HapticFeedback.selectionClick();
    setState(() {
      _inSelectionMode = true;
      if (_selectedPaths.contains(path)) {
        _selectedPaths.remove(path);
        if (_selectedPaths.isEmpty) {
          _inSelectionMode = false;
        }
      } else {
        _selectedPaths.add(path);
      }
    });
  }

  void _selectAll(List<RecordingItem> visibleItems) {
    HapticFeedback.lightImpact();
    setState(() {
      _inSelectionMode = true;
      if (_selectedPaths.length == visibleItems.length) {
        _selectedPaths.clear();
      } else {
        _selectedPaths.clear();
        _selectedPaths.addAll(visibleItems.map((e) => e.path));
      }
    });
  }

  Future<void> _batchRestore() async {
    if (_selectedPaths.isEmpty) return;
    HapticFeedback.lightImpact();
    final count = await _storageService.batchRestoreFromTrash(_selectedPaths);
    setState(() {
      _selectedPaths.clear();
      _inSelectionMode = false;
    });
    widget.onRefresh();
    if (mounted) {
      AppToast.showSuccess(context, 'Restored $count recordings');
    }
  }

  Future<void> _batchDeletePermanentlyDialog() async {
    if (_selectedPaths.isEmpty) return;
    final colors = AppColors.of(context);
    HapticFeedback.lightImpact();
    final count = _selectedPaths.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            const Icon(Icons.delete_forever_rounded, color: Colors.redAccent, size: 24),
            const SizedBox(width: 10),
            Text('Delete $count Forever?', style: TextStyle(color: colors.textPrimary, fontSize: 16)),
          ],
        ),
        content: Text(
          'Selected recordings will be permanently removed from your phone storage. This action cannot be undone.',
          style: TextStyle(color: colors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
            onPressed: () => Navigator.pop(ctx, false),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Delete Forever', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final deleted = await _storageService.batchDeletePermanently(_selectedPaths);
      setState(() {
        _selectedPaths.clear();
        _inSelectionMode = false;
      });
      widget.onRefresh();
      if (mounted) {
        AppToast.showSuccess(context, 'Permanently erased $deleted recordings');
      }
    }
  }

  List<RecordingItem> _getTrashItems() {
    final list = widget.recordings.where((r) => r.isTrash).toList();
    list.sort((a, b) => (b.trashedAt ?? 0).compareTo(a.trashedAt ?? 0));
    return list;
  }

  Future<void> _emptyTrashDialog() async {
    final colors = AppColors.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.cardBg,
        title: Text('Empty Trash?', style: TextStyle(color: colors.textPrimary)),
        content: Text(
          'All items in trash will be permanently deleted from your phone. This action cannot be undone.',
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
      widget.onRefresh();
      if (mounted) {
        AppToast.showSuccess(
          context,
          'Permanently deleted $count recordings',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final trashItems = _getTrashItems();
    final retentionDays = _storageService.settings.value.trashRetentionDays;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isSelectionMode) {
          setState(() {
            _selectedPaths.clear();
            _inSelectionMode = false;
          });
        } else {
          widget.onBackToHome?.call();
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity != null && details.primaryVelocity! > 250) {
            if (_isSelectionMode) {
              HapticFeedback.lightImpact();
              setState(() {
                _selectedPaths.clear();
                _inSelectionMode = false;
              });
            } else {
              HapticFeedback.lightImpact();
              widget.onBackToHome?.call();
            }
          }
        },
        child: Scaffold(
          backgroundColor: colors.scaffoldBg,
          appBar: _isSelectionMode
              ? AppBar(
                  backgroundColor: colors.cardBg,
                  surfaceTintColor: Colors.transparent,
                  elevation: 0,
                  leading: IconButton(
                    icon: Icon(Icons.close_rounded, color: colors.textPrimary),
                    tooltip: 'Exit selection',
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      setState(() {
                        _selectedPaths.clear();
                        _inSelectionMode = false;
                      });
                    },
                  ),
                  title: Text(
                    '${_selectedPaths.length} Selected',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: colors.textPrimary),
                  ),
                  actions: [
                    // Select All / Deselect All
                    IconButton(
                      icon: Icon(
                        _selectedPaths.length == trashItems.length && trashItems.isNotEmpty
                            ? Icons.deselect_rounded
                            : Icons.select_all_rounded,
                        color: colors.primary,
                      ),
                      tooltip: _selectedPaths.length == trashItems.length ? 'Deselect all' : 'Select all',
                      onPressed: () => _selectAll(trashItems),
                    ),
                    // Batch Restore
                    IconButton(
                      icon: const Icon(Icons.restore_from_trash_rounded, color: Colors.tealAccent),
                      tooltip: 'Restore selected',
                      onPressed: _batchRestore,
                    ),
                    // Batch Delete Forever
                    IconButton(
                      icon: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent),
                      tooltip: 'Delete selected permanently',
                      onPressed: _batchDeletePermanentlyDialog,
                    ),
                    const SizedBox(width: 4),
                  ],
                )
              : AppBar(
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
                      const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent, size: 26),
                      const SizedBox(width: 10),
                      Text(
                        'Trash Bin',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: colors.textPrimary),
                      ),
                    ],
                  ),
                  actions: [
                    if (trashItems.isNotEmpty) ...[
                      IconButton(
                        icon: Icon(Icons.checklist_rounded, color: colors.primary),
                        tooltip: 'Select multiple',
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          setState(() => _inSelectionMode = true);
                        },
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent, size: 18),
                        label: const Text('Empty', style: TextStyle(color: Colors.redAccent)),
                        onPressed: _emptyTrashDialog,
                      ),
                    ],
                  ],
                ),
          body: Column(
            children: [
              // Informational Banner
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: colors.cardBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.auto_delete_outlined, color: Colors.amberAccent, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Recordings in trash are automatically purged after $retentionDays days.',
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),

              Expanded(
                child: trashItems.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: colors.cardBg,
                                border: Border.all(color: colors.border, width: 1),
                              ),
                              child: Icon(Icons.delete_outline_rounded, size: 48, color: colors.textMuted),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Trash is empty',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colors.textPrimary),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Deleted recordings will be held here before auto-purging',
                              style: TextStyle(fontSize: 13, color: colors.textMuted),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: trashItems.length,
                        itemBuilder: (context, i) {
                          final item = trashItems[i];
                          return RecordingTile(
                            item: item,
                            onUpdated: widget.onRefresh,
                            isTrashView: true,
                            isSelectionMode: _isSelectionMode,
                            isSelected: _selectedPaths.contains(item.path),
                            onSelectChanged: (_) => _toggleSelection(item.path),
                            onLongPress: () => _toggleSelection(item.path),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
