import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/recording_item.dart';
import '../services/shizuku_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import 'app_toast.dart';

class BatchStorageManagerSheet extends StatefulWidget {
  final VoidCallback onUpdated;
  final List<RecordingItem>? initialRecordings;

  const BatchStorageManagerSheet({
    super.key,
    required this.onUpdated,
    this.initialRecordings,
  });

  static Future<void> show(
    BuildContext context, {
    required VoidCallback onUpdated,
    List<RecordingItem>? initialRecordings,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => BatchStorageManagerSheet(
        onUpdated: onUpdated,
        initialRecordings: initialRecordings,
      ),
    );
  }

  @override
  State<BatchStorageManagerSheet> createState() => _BatchStorageManagerSheetState();
}

class _BatchStorageManagerSheetState extends State<BatchStorageManagerSheet> with SingleTickerProviderStateMixin {
  final StorageService _storageService = StorageService();
  final ShizukuService _shizukuService = ShizukuService();

  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  List<RecordingItem> _allRecordings = [];
  bool _isLoading = false;

  final Set<String> _selectedActive = {};
  final Set<String> _selectedTrash = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() => setState(() {}));

    if (widget.initialRecordings != null && widget.initialRecordings!.isNotEmpty) {
      _allRecordings = widget.initialRecordings!;
    } else {
      _loadRecordings();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRecordings() async {
    setState(() => _isLoading = true);
    final raw = await _shizukuService.getRecordings();
    final items = _storageService.mergeMetadata(raw);
    if (mounted) {
      setState(() {
        _allRecordings = items;
        _isLoading = false;
      });
    }
  }

  List<RecordingItem> _getActiveItems() {
    var list = _allRecordings.where((r) => !r.isTrash).toList();
    final q = _searchController.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((r) =>
        r.contactNumber.toLowerCase().contains(q) ||
        r.name.toLowerCase().contains(q) ||
        (r.note != null && r.note!.toLowerCase().contains(q))
      ).toList();
    }
    list.sort((a, b) => b.lastModified.compareTo(a.lastModified));
    return list;
  }

  List<RecordingItem> _getTrashItems() {
    var list = _allRecordings.where((r) => r.isTrash).toList();
    final q = _searchController.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((r) =>
        r.contactNumber.toLowerCase().contains(q) ||
        r.name.toLowerCase().contains(q)
      ).toList();
    }
    list.sort((a, b) => (b.trashedAt ?? 0).compareTo(a.trashedAt ?? 0));
    return list;
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Color _getBadgeColor(String type) {
    switch (type.toLowerCase()) {
      case 'incoming':
        return const Color(0xFF38BDF8);
      case 'outgoing':
        return const Color(0xFF34D399);
      case 'voip':
        return const Color(0xFFA78BFA);
      default:
        return Colors.white54;
    }
  }

  void _toggleSelectAll(List<RecordingItem> visibleItems, Set<String> targetSet) {
    HapticFeedback.lightImpact();
    setState(() {
      if (targetSet.length == visibleItems.length) {
        targetSet.clear();
      } else {
        targetSet.clear();
        targetSet.addAll(visibleItems.map((e) => e.path));
      }
    });
  }

  // Batch actions for Active recordings
  Future<void> _batchMoveToTrash() async {
    if (_selectedActive.isEmpty) return;
    final colors = AppColors.of(context);
    HapticFeedback.lightImpact();
    final count = _selectedActive.length;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            const Icon(Icons.delete_sweep_rounded, color: Colors.amberAccent, size: 24),
            const SizedBox(width: 10),
            Text('Move $count to Trash?', style: TextStyle(color: colors.textPrimary, fontSize: 16)),
          ],
        ),
        content: Text(
          'Selected recordings will be placed in the Trash bin. You can restore them anytime before they auto-purge.',
          style: TextStyle(color: colors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
            onPressed: () => Navigator.pop(ctx, false),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amberAccent,
              foregroundColor: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Move to Trash', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _storageService.batchMoveToTrash(_selectedActive);
      setState(() => _selectedActive.clear());
      await _loadRecordings();
      widget.onUpdated();
      if (mounted) {
        AppToast.showSuccess(context, 'Moved $count recordings to Trash');
      }
    }
  }

  Future<void> _batchDeletePermanently(bool fromTrash) async {
    final targetSet = fromTrash ? _selectedTrash : _selectedActive;
    if (targetSet.isEmpty) return;
    final colors = AppColors.of(context);
    HapticFeedback.lightImpact();
    final count = targetSet.length;

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
          'Selected recordings will be immediately erased from device storage and cannot be recovered.',
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
            child: const Text('Delete Permanently', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _storageService.batchDeletePermanently(targetSet);
      setState(() => targetSet.clear());
      await _loadRecordings();
      widget.onUpdated();
      if (mounted) {
        AppToast.showSuccess(context, 'Permanently erased $count recordings');
      }
    }
  }

  Future<void> _batchRestoreFromTrash() async {
    if (_selectedTrash.isEmpty) return;
    HapticFeedback.lightImpact();
    final count = _selectedTrash.length;

    await _storageService.batchRestoreFromTrash(_selectedTrash);
    setState(() => _selectedTrash.clear());
    await _loadRecordings();
    widget.onUpdated();
    if (mounted) {
      AppToast.showSuccess(context, 'Restored $count recordings from Trash');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final activeItems = _getActiveItems();
    final trashItems = _getTrashItems();

    final isTrashTab = _tabController.index == 1;
    final currentList = isTrashTab ? trashItems : activeItems;
    final currentSet = isTrashTab ? _selectedTrash : _selectedActive;

    final selectedTotalBytes = currentList
        .where((r) => currentSet.contains(r.path))
        .fold<int>(0, (acc, r) => acc + r.size);

    return DraggableScrollableSheet(
      initialChildSize: 0.90,
      minChildSize: 0.50,
      maxChildSize: 0.96,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Sheet Drag Handle
              const SizedBox(height: 10),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.isDark ? Colors.white24 : Colors.black26,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),

              // Sheet Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.checklist_rtl_rounded, color: Color(0xFF38BDF8), size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Batch Storage Manager',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colors.textPrimary),
                          ),
                          Text(
                            'Tick checkboxes for bulk delete, trash, or restore',
                            style: TextStyle(fontSize: 12, color: colors.textMuted),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded, color: colors.textSecondary),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // TabBar: Active Recordings vs Trash
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: BoxDecoration(
                    color: const Color(0xFF38BDF8).withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF38BDF8), width: 1.2),
                  ),
                  labelColor: const Color(0xFF38BDF8),
                  unselectedLabelColor: colors.textMuted,
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  dividerColor: Colors.transparent,
                  tabs: [
                    Tab(text: 'Active Recordings (${activeItems.length})'),
                    Tab(text: 'Trash Bin (${trashItems.length})'),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Quick Search in Manager
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  style: TextStyle(color: colors.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Filter recordings in this view...',
                    hintStyle: TextStyle(color: colors.textMuted),
                    prefixIcon: Icon(Icons.search_rounded, color: colors.textMuted, size: 18),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear_rounded, color: colors.textMuted, size: 16),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: colors.card,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Select All Header Bar
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.card.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colors.border),
                ),
                child: Row(
                  children: [
                    Checkbox(
                      value: currentList.isNotEmpty && currentSet.length == currentList.length,
                      tristate: currentSet.isNotEmpty && currentSet.length < currentList.length,
                      activeColor: const Color(0xFF38BDF8),
                      checkColor: Colors.white,
                      side: BorderSide(color: colors.isDark ? Colors.white38 : Colors.black38, width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      onChanged: currentList.isEmpty
                          ? null
                          : (_) => _toggleSelectAll(currentList, currentSet),
                    ),
                    GestureDetector(
                      onTap: currentList.isEmpty
                          ? null
                          : () => _toggleSelectAll(currentList, currentSet),
                      child: Text(
                        'Select All (${currentList.length})',
                        style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                    const Spacer(),
                    if (currentSet.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF38BDF8).withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${currentSet.length} selected • ${_formatSize(selectedTotalBytes)}',
                          style: const TextStyle(
                            color: Color(0xFF38BDF8),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),

              // Scrollable Recordings List with Checkboxes
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFF38BDF8)))
                    : currentList.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  isTrashTab ? Icons.delete_outline_rounded : Icons.folder_open_rounded,
                                  size: 40,
                                  color: colors.isDark ? Colors.white24 : Colors.black26,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  isTrashTab ? 'Trash is empty' : 'No active recordings',
                                  style: TextStyle(color: colors.textMuted, fontSize: 14),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            controller: scrollController,
                            itemCount: currentList.length,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                            itemBuilder: (context, i) {
                              final item = currentList[i];
                              final isSelected = currentSet.contains(item.path);
                              final badgeColor = _getBadgeColor(item.callType);

                              return Container(
                                margin: const EdgeInsets.symmetric(vertical: 3),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? const Color(0xFF38BDF8).withValues(alpha: 0.12)
                                      : colors.card,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isSelected
                                        ? const Color(0xFF38BDF8)
                                        : colors.border,
                                    width: isSelected ? 1.4 : 1.0,
                                  ),
                                ),
                                child: CheckboxListTile(
                                  value: isSelected,
                                  activeColor: const Color(0xFF38BDF8),
                                  checkColor: Colors.white,
                                  side: BorderSide(color: colors.isDark ? Colors.white38 : Colors.black38, width: 1.5),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                                  title: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          item.contactNumber,
                                          style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 13.5),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: badgeColor.withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          item.callType,
                                          style: TextStyle(fontSize: 9.5, color: badgeColor, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ),
                                  subtitle: Text(
                                    '${item.formattedDate} • ${item.formattedSize}',
                                    style: TextStyle(color: colors.textMuted, fontSize: 11),
                                  ),
                                  onChanged: (_) {
                                    HapticFeedback.selectionClick();
                                    setState(() {
                                      if (isSelected) {
                                        currentSet.remove(item.path);
                                      } else {
                                        currentSet.add(item.path);
                                      }
                                    });
                                  },
                                ),
                              );
                            },
                          ),
              ),

              // Bottom Batch Action Buttons Sticky Bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: colors.surface,
                  border: Border(top: BorderSide(color: colors.border)),
                ),
                child: SafeArea(
                  top: false,
                  child: isTrashTab
                      ? Row(
                          children: [
                            // Batch Restore Button
                            Expanded(
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.restore_from_trash_rounded, size: 18),
                                label: Text('Restore (${_selectedTrash.length})'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF38BDF8),
                                  foregroundColor: const Color(0xFF0F172A),
                                  disabledBackgroundColor: colors.isDark ? Colors.white10 : Colors.black12,
                                  disabledForegroundColor: colors.isDark ? Colors.white30 : Colors.black38,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                onPressed: _selectedTrash.isEmpty ? null : _batchRestoreFromTrash,
                              ),
                            ),
                            const SizedBox(width: 10),

                            // Batch Delete Permanently from Trash Button
                            Expanded(
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.delete_forever_rounded, size: 18),
                                label: Text('Delete (${_selectedTrash.length})'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.redAccent,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: colors.isDark ? Colors.white10 : Colors.black12,
                                  disabledForegroundColor: colors.isDark ? Colors.white30 : Colors.black38,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                onPressed: _selectedTrash.isEmpty ? null : () => _batchDeletePermanently(true),
                              ),
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            // Move to Trash Button
                            Expanded(
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                                label: Text('To Trash (${_selectedActive.length})'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFF59E0B),
                                  foregroundColor: const Color(0xFF0F172A),
                                  disabledBackgroundColor: colors.isDark ? Colors.white10 : Colors.black12,
                                  disabledForegroundColor: colors.isDark ? Colors.white30 : Colors.black38,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                onPressed: _selectedActive.isEmpty ? null : _batchMoveToTrash,
                              ),
                            ),
                            const SizedBox(width: 10),

                            // Permanent Erase Button
                            Expanded(
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.delete_forever_rounded, size: 18),
                                label: Text('Erase (${_selectedActive.length})'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.redAccent,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: colors.isDark ? Colors.white10 : Colors.black12,
                                  disabledForegroundColor: colors.isDark ? Colors.white30 : Colors.black38,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                onPressed: _selectedActive.isEmpty ? null : () => _batchDeletePermanently(false),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
