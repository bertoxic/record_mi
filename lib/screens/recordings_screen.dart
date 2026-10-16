import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/recording_item.dart';
import '../services/shizuku_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_toast.dart';
import '../widgets/recording_tile.dart';
import '../widgets/shizuku_setup_card.dart';

class RecordingsScreen extends StatefulWidget {
  final List<RecordingItem> recordings;
  final VoidCallback onRefresh;
  final bool isLoading;

  const RecordingsScreen({
    super.key,
    required this.recordings,
    required this.onRefresh,
    this.isLoading = false,
  });

  @override
  State<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends State<RecordingsScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ShizukuService _shizukuService = ShizukuService();
  final StorageService _storageService = StorageService();

  String _filterType = 'all'; // 'all', 'incoming', 'outgoing', 'voip'
  String _dateFilter = 'all'; // 'all', 'today', 'week', 'month'
  String _sortOrder = 'newest'; // 'newest', 'oldest', 'size'
  bool _isTestingRecording = false;

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

  Future<void> _batchStar() async {
    if (_selectedPaths.isEmpty) return;
    HapticFeedback.lightImpact();
    final filtered = _getFilteredRecordings();
    final selectedItems = filtered.where((r) => _selectedPaths.contains(r.path)).toList();
    final allStarred = selectedItems.isNotEmpty && selectedItems.every((r) => r.isFavorite);
    final newFav = !allStarred;
    final count = await _storageService.batchToggleFavorite(_selectedPaths, newFav);
    setState(() {
      _selectedPaths.clear();
      _inSelectionMode = false;
    });
    widget.onRefresh();
    if (mounted) {
      AppToast.showSuccess(
        context,
        newFav ? 'Starred $count recordings' : 'Removed stars from $count recordings',
      );
    }
  }

  Future<void> _batchTrashDialog() async {
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
            const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent, size: 24),
            const SizedBox(width: 10),
            Text('Move $count ${count == 1 ? "Recording" : "Recordings"} to Trash?', style: TextStyle(color: colors.textPrimary, fontSize: 16)),
          ],
        ),
        content: Text(
          'Selected recordings will be moved to the Trash bin. You can restore them anytime before the auto-purge period.',
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
            child: const Text('Move to Trash', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final moved = await _storageService.batchMoveToTrash(_selectedPaths);
      final pathsToUndo = Set<String>.from(_selectedPaths);
      setState(() {
        _selectedPaths.clear();
        _inSelectionMode = false;
      });
      widget.onRefresh();
      if (mounted) {
        AppToast.showInfo(
          context,
          'Moved $moved recordings to Trash',
          actionLabel: 'Undo',
          onAction: () async {
            await _storageService.batchRestoreFromTrash(pathsToUndo);
            widget.onRefresh();
          },
        );
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<RecordingItem> _getFilteredRecordings() {
    // Only non-trashed items
    var list = widget.recordings.where((r) => !r.isTrash).toList();

    // 1. Filter by call type
    if (_filterType != 'all') {
      list = list.where((r) => r.callType.toLowerCase() == _filterType).toList();
    }

    // 2. Filter by search query
    final query = _searchController.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      list = list.where((r) {
        final matchesNum = r.contactNumber.toLowerCase().contains(query);
        final matchesName = r.name.toLowerCase().contains(query);
        final matchesNote = r.note != null && r.note!.toLowerCase().contains(query);
        return matchesNum || matchesName || matchesNote;
      }).toList();
    }

    // 3. Filter by date
    final now = DateTime.now();
    if (_dateFilter == 'today') {
      list = list.where((r) {
        final d = r.date;
        return d.year == now.year && d.month == now.month && d.day == now.day;
      }).toList();
    } else if (_dateFilter == 'week') {
      final sevenDaysAgo = now.subtract(const Duration(days: 7));
      list = list.where((r) => r.date.isAfter(sevenDaysAgo)).toList();
    } else if (_dateFilter == 'month') {
      final thirtyDaysAgo = now.subtract(const Duration(days: 30));
      list = list.where((r) => r.date.isAfter(thirtyDaysAgo)).toList();
    }

    // 4. Sort
    if (_sortOrder == 'newest') {
      list.sort((a, b) => b.lastModified.compareTo(a.lastModified));
    } else if (_sortOrder == 'oldest') {
      list.sort((a, b) => a.lastModified.compareTo(b.lastModified));
    } else if (_sortOrder == 'size') {
      list.sort((a, b) => b.size.compareTo(a.size));
    }

    return list;
  }

  Future<void> _runTestRecording() async {
    if (_isTestingRecording) return;
    setState(() => _isTestingRecording = true);

    AppToast.showInfo(
      context,
      'Starting 5-second privileged 2-way test recording...',
    );

    final started = await _shizukuService.startRecord(
      fileName: 'test_${DateTime.now().millisecondsSinceEpoch}.m4a',
      callType: 'test',
    );

    if (!started) {
      if (mounted) {
        setState(() => _isTestingRecording = false);
        AppToast.showError(
          context,
          'Could not start test recording. Ensure Shizuku is connected.',
        );
      }
      return;
    }

    // Record for 5 seconds
    await Future.delayed(const Duration(seconds: 5));
    final path = await _shizukuService.stopRecord();

    if (mounted) {
      setState(() => _isTestingRecording = false);
      widget.onRefresh();
      AppToast.showSuccess(
        context,
        path != null ? 'Test recording saved successfully!' : 'Test recording complete.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final filtered = _getFilteredRecordings();

    return PopScope(
      canPop: !_isSelectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isSelectionMode) {
          HapticFeedback.lightImpact();
          setState(() {
            _selectedPaths.clear();
            _inSelectionMode = false;
          });
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
                      _selectedPaths.length == filtered.length && filtered.isNotEmpty
                          ? Icons.deselect_rounded
                          : Icons.select_all_rounded,
                      color: colors.primary,
                    ),
                    tooltip: _selectedPaths.length == filtered.length ? 'Deselect all' : 'Select all',
                    onPressed: () => _selectAll(filtered),
                  ),
                  // Batch Star
                  IconButton(
                    icon: const Icon(Icons.star_rounded, color: Colors.amber),
                    tooltip: 'Star / Unstar selected',
                    onPressed: _batchStar,
                  ),
                  // Batch Trash
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                    tooltip: 'Move selected to trash',
                    onPressed: _batchTrashDialog,
                  ),
                  const SizedBox(width: 4),
                ],
              )
            : AppBar(
                backgroundColor: colors.scaffoldBg,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                title: Row(
                  children: [
                    Icon(Icons.mic_external_on_rounded, color: colors.primary, size: 26),
                    const SizedBox(width: 10),
                    Text(
                      'Call Recordings',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: colors.textPrimary),
                    ),
                  ],
                ),
                actions: [
                  // Selection Mode trigger button
                  if (filtered.isNotEmpty)
                    IconButton(
                      icon: Icon(Icons.checklist_rounded, color: colors.primary),
                      tooltip: 'Select recordings',
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        setState(() {
                          _inSelectionMode = true;
                        });
                      },
                    ),
                  // Test Recording Button
                  IconButton(
                    icon: _isTestingRecording
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.redAccent),
                          )
                        : const Icon(Icons.fiber_manual_record, color: Colors.redAccent),
                    tooltip: 'Run 5s Test Recording',
                    onPressed: _isTestingRecording ? null : _runTestRecording,
                  ),
                  // Refresh Button
                  IconButton(
                    icon: Icon(Icons.refresh_rounded, color: colors.textSecondary),
                    tooltip: 'Refresh list',
                    onPressed: widget.onRefresh,
                  ),
                ],
              ),
        body: Column(
          children: [
            // Shizuku Detection & Play Store Download Card
            ShizukuSetupCard(onRefresh: widget.onRefresh),

            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                style: TextStyle(color: colors.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search number, name, or note...',
                  hintStyle: TextStyle(color: colors.textMuted),
                  prefixIcon: Icon(Icons.search_rounded, color: colors.textSecondary, size: 20),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear_rounded, color: colors.textSecondary, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: colors.inputBg,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: colors.border, width: 1),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: colors.border, width: 1),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: colors.primary, width: 1.5),
                  ),
                ),
              ),
            ),

            // Filter Chips & Date/Sort bar
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  _buildFilterChip('All', 'all', colors),
                  const SizedBox(width: 8),
                  _buildFilterChip('Incoming', 'incoming', colors, icon: Icons.call_received_rounded),
                  const SizedBox(width: 8),
                  _buildFilterChip('Outgoing', 'outgoing', colors, icon: Icons.call_made_rounded),
                  const SizedBox(width: 8),
                  _buildFilterChip('WhatsApp', 'voip', colors, icon: Icons.chat_bubble_outline_rounded),
                  const SizedBox(width: 12),
                  Container(width: 1, height: 24, color: colors.divider),
                  const SizedBox(width: 12),

                  // Date filter dropdown
                  PopupMenuButton<String>(
                    initialValue: _dateFilter,
                    color: colors.cardBg,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: _dateFilter != 'all'
                            ? colors.primary.withValues(alpha: 0.18)
                            : colors.chipBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _dateFilter != 'all' ? colors.primary : colors.chipBorder,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.date_range_rounded,
                            size: 14,
                            color: _dateFilter != 'all' ? colors.primary : colors.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _dateFilter == 'all'
                                ? 'Date: All'
                                : (_dateFilter == 'today'
                                    ? 'Today'
                                    : (_dateFilter == 'week' ? 'Past 7d' : 'Past 30d')),
                            style: TextStyle(
                              fontSize: 12,
                              color: _dateFilter != 'all' ? colors.primary : colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    onSelected: (val) => setState(() => _dateFilter = val),
                    itemBuilder: (context) => [
                      PopupMenuItem(value: 'all', child: Text('All Time', style: TextStyle(color: colors.textPrimary))),
                      PopupMenuItem(value: 'today', child: Text('Today', style: TextStyle(color: colors.textPrimary))),
                      PopupMenuItem(value: 'week', child: Text('Past 7 Days', style: TextStyle(color: colors.textPrimary))),
                      PopupMenuItem(value: 'month', child: Text('Past 30 Days', style: TextStyle(color: colors.textPrimary))),
                    ],
                  ),
                  const SizedBox(width: 8),

                  // Sort dropdown
                  PopupMenuButton<String>(
                    initialValue: _sortOrder,
                    color: colors.cardBg,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: colors.chipBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: colors.chipBorder),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.sort_rounded, size: 14, color: colors.textSecondary),
                          const SizedBox(width: 4),
                          Text(
                            _sortOrder == 'newest' ? 'Newest' : (_sortOrder == 'oldest' ? 'Oldest' : 'Size'),
                            style: TextStyle(fontSize: 12, color: colors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    onSelected: (val) => setState(() => _sortOrder = val),
                    itemBuilder: (context) => [
                      PopupMenuItem(value: 'newest', child: Text('Newest First', style: TextStyle(color: colors.textPrimary))),
                      PopupMenuItem(value: 'oldest', child: Text('Oldest First', style: TextStyle(color: colors.textPrimary))),
                      PopupMenuItem(value: 'size', child: Text('Largest Size', style: TextStyle(color: colors.textPrimary))),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),

            // Recordings List
            Expanded(
              child: widget.isLoading
                  ? Center(child: CircularProgressIndicator(color: colors.primary))
                  : filtered.isEmpty
                      ? _buildEmptyState(colors)
                      : RefreshIndicator(
                          color: colors.primary,
                          backgroundColor: colors.cardBg,
                          onRefresh: () async => widget.onRefresh(),
                          child: ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            itemCount: filtered.length,
                            itemBuilder: (context, i) {
                              final item = filtered[i];
                              return RecordingTile(
                                item: item,
                                onUpdated: widget.onRefresh,
                                isSelectionMode: _isSelectionMode,
                                isSelected: _selectedPaths.contains(item.path),
                                onSelectChanged: (_) => _toggleSelection(item.path),
                                onLongPress: () => _toggleSelection(item.path),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value, AppColors colors, {IconData? icon}) {
    final isSelected = _filterType == value;
    return GestureDetector(
      onTap: () => setState(() => _filterType = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? colors.primary : colors.chipBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? colors.primary : colors.chipBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: isSelected ? Colors.white : colors.textSecondary),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.white : colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(AppColors colors) {
    return Center(
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
            child: Icon(Icons.phone_missed_rounded, size: 48, color: colors.textMuted),
          ),
          const SizedBox(height: 16),
          Text(
            'No recordings found',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colors.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            _searchController.text.isNotEmpty || _filterType != 'all' || _dateFilter != 'all'
                ? 'Try clearing your search or filters'
                : 'Incoming & outgoing calls will appear here automatically',
            style: TextStyle(fontSize: 13, color: colors.textMuted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            icon: const Icon(Icons.fiber_manual_record, size: 16, color: Colors.redAccent),
            label: const Text('Try Test Recording'),
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.cardBg,
              foregroundColor: colors.textPrimary,
              side: BorderSide(color: colors.border),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _runTestRecording,
          ),
        ],
      ),
    );
  }
}
