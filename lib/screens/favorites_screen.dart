import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/recording_item.dart';
import '../theme/app_theme.dart';
import '../widgets/recording_tile.dart';

class FavoritesScreen extends StatefulWidget {
  final List<RecordingItem> recordings;
  final VoidCallback onRefresh;
  final VoidCallback? onBackToHome;

  const FavoritesScreen({
    super.key,
    required this.recordings,
    required this.onRefresh,
    this.onBackToHome,
  });

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<RecordingItem> _getFavorites() {
    var list = widget.recordings.where((r) => r.isFavorite && !r.isTrash).toList();
    final query = _searchController.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      list = list.where((r) {
        final matchesNum = r.contactNumber.toLowerCase().contains(query);
        final matchesName = r.name.toLowerCase().contains(query);
        final matchesNote = r.note != null && r.note!.toLowerCase().contains(query);
        return matchesNum || matchesName || matchesNote;
      }).toList();
    }
    list.sort((a, b) => b.lastModified.compareTo(a.lastModified));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final favorites = _getFavorites();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        widget.onBackToHome?.call();
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: (details) {
          // Swipe back to recordings screen (drag from left to right)
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
                const Icon(Icons.star_rounded, color: Colors.amber, size: 26),
                const SizedBox(width: 10),
                Text(
                  'Starred Recordings',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: colors.textPrimary),
                ),
              ],
            ),
          ),
          body: Column(
            children: [
              // Search within favorites
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  style: TextStyle(color: colors.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search starred calls...',
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
              const SizedBox(height: 6),

              Expanded(
                child: favorites.isEmpty
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
                              child: Icon(Icons.star_outline_rounded, size: 48, color: colors.textMuted),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No starred recordings',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colors.textPrimary),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Tap the star icon on any recording to pin it here',
                              style: TextStyle(fontSize: 13, color: colors.textMuted),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: favorites.length,
                        itemBuilder: (context, i) => RecordingTile(
                          item: favorites[i],
                          onUpdated: widget.onRefresh,
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
