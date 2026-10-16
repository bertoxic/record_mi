import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/app_settings.dart';
import '../models/recording_item.dart';

class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  final ValueNotifier<AppSettings> settings = ValueNotifier<AppSettings>(const AppSettings());
  final ValueNotifier<Map<String, Map<String, dynamic>>> metadataMap =
      ValueNotifier<Map<String, Map<String, dynamic>>>({});

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    await _loadSettings();
    await _loadMetadata();
    _initialized = true;
  }

  Future<File> _getSettingsFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/app_settings.json');
  }

  Future<File> _getMetadataFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/recordings_metadata.json');
  }

  Future<void> _loadSettings() async {
    try {
      final file = await _getSettingsFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        var loaded = AppSettings.fromJson(json);
        if (!loaded.recordVoipCalls) {
          loaded = loaded.copyWith(recordVoipCalls: true, voipAutoSpeakerphone: true);
        }
        settings.value = loaded;
      }
    } catch (e) {
      debugPrint("StorageService: Error loading settings: $e");
    }
  }

  Future<void> updateSettings(AppSettings newSettings) async {
    settings.value = newSettings;
    try {
      final file = await _getSettingsFile();
      await file.writeAsString(jsonEncode(newSettings.toJson()));
    } catch (e) {
      debugPrint("StorageService: Error saving settings: $e");
    }
  }

  Future<void> _loadMetadata() async {
    try {
      final file = await _getMetadataFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final rawMap = jsonDecode(content) as Map<String, dynamic>;
        final Map<String, Map<String, dynamic>> parsed = {};
        rawMap.forEach((k, v) {
          if (v is Map) {
            parsed[k] = Map<String, dynamic>.from(v);
          }
        });
        metadataMap.value = parsed;
      }
    } catch (e) {
      debugPrint("StorageService: Error loading metadata: $e");
    }
  }

  Future<void> _saveMetadata() async {
    try {
      final file = await _getMetadataFile();
      await file.writeAsString(jsonEncode(metadataMap.value));
    } catch (e) {
      debugPrint("StorageService: Error saving metadata: $e");
    }
  }

  /// Automatically purges trash items older than retention period (default 30 days)
  Future<int> autoPurgeExpiredTrash() async {
    final retentionDays = settings.value.trashRetentionDays;
    final map = Map<String, Map<String, dynamic>>.from(metadataMap.value);
    final now = DateTime.now();
    int purgedCount = 0;

    final keysToRemove = <String>[];

    for (final entry in map.entries) {
      final meta = entry.value;
      final isTrash = meta['isTrash'] as bool? ?? false;
      final trashedAt = meta['trashedAt'] as int?;

      if (isTrash && trashedAt != null) {
        final trashDate = DateTime.fromMillisecondsSinceEpoch(trashedAt);
        final difference = now.difference(trashDate).inDays;
        if (difference >= retentionDays) {
          final path = entry.key;
          try {
            final f = File(path);
            if (await f.exists()) {
              await f.delete();
            }
          } catch (e) {
            debugPrint("Failed to delete expired file $path: $e");
          }
          keysToRemove.add(path);
          purgedCount++;
        }
      }
    }

    if (purgedCount > 0) {
      for (final k in keysToRemove) {
        map.remove(k);
      }
      metadataMap.value = map;
      await _saveMetadata();
      debugPrint("Auto-purged $purgedCount expired recordings older than $retentionDays days.");
    }

    return purgedCount;
  }

  /// Merges native recording items with stored metadata
  List<RecordingItem> mergeMetadata(List<Map<dynamic, dynamic>> rawNativeList) {
    final meta = metadataMap.value;
    final List<RecordingItem> list = [];

    for (final raw in rawNativeList) {
      final path = raw['path'] as String? ?? '';
      if (path.isEmpty) continue;

      final m = meta[path];
      final isFav = m?['isFavorite'] as bool? ?? false;
      final isTr = m?['isTrash'] as bool? ?? false;
      final trAt = m?['trashedAt'] as int?;
      final note = m?['note'] as String?;
      final durMs = m?['durationMs'] as int?;
      final customTitle = m?['customTitle'] as String?;

      list.add(
        RecordingItem(
          path: path,
          name: raw['name'] as String? ?? '',
          size: (raw['size'] as num?)?.toInt() ?? 0,
          lastModified: (raw['lastModified'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
          callType: raw['callType'] as String? ?? 'Call',
          contactNumber: raw['contactNumber'] as String? ?? 'Unknown',
          customTitle: customTitle,
          isFavorite: isFav,
          isTrash: isTr,
          trashedAt: trAt,
          note: note,
          duration: durMs != null ? Duration(milliseconds: durMs) : null,
        ),
      );
    }

    return list;
  }

  Future<void> toggleFavorite(String path) async {
    final map = Map<String, Map<String, dynamic>>.from(metadataMap.value);
    final current = map[path] ?? <String, dynamic>{};
    final currentFav = current['isFavorite'] as bool? ?? false;
    current['isFavorite'] = !currentFav;
    map[path] = current;
    metadataMap.value = map;
    await _saveMetadata();
  }

  Future<void> moveToTrash(String path) async {
    final map = Map<String, Map<String, dynamic>>.from(metadataMap.value);
    final current = map[path] ?? <String, dynamic>{};
    current['isTrash'] = true;
    current['trashedAt'] = DateTime.now().millisecondsSinceEpoch;
    map[path] = current;
    metadataMap.value = map;
    await _saveMetadata();
  }

  Future<void> restoreFromTrash(String path) async {
    final map = Map<String, Map<String, dynamic>>.from(metadataMap.value);
    final current = map[path] ?? <String, dynamic>{};
    current['isTrash'] = false;
    current['trashedAt'] = null;
    map[path] = current;
    metadataMap.value = map;
    await _saveMetadata();
  }

  Future<void> updateCustomTitle(String path, String title) async {
    final map = Map<String, Map<String, dynamic>>.from(metadataMap.value);
    final current = map[path] ?? <String, dynamic>{};
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      current.remove('customTitle');
    } else {
      current['customTitle'] = trimmed;
    }
    map[path] = current;
    metadataMap.value = map;
    await _saveMetadata();
  }

  Future<void> updateNote(String path, String note) async {
    final map = Map<String, Map<String, dynamic>>.from(metadataMap.value);
    final current = map[path] ?? <String, dynamic>{};
    current['note'] = note.trim();
    map[path] = current;
    metadataMap.value = map;
    await _saveMetadata();
  }

  Future<void> deletePermanently(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) {
        await f.delete();
      }
    } catch (e) {
      debugPrint("Error deleting file permanently: $e");
    }

    final map = Map<String, Map<String, dynamic>>.from(metadataMap.value);
    map.remove(path);
    metadataMap.value = map;
    await _saveMetadata();
  }

  Future<int> emptyTrash() async {
    final map = Map<String, Map<String, dynamic>>.from(metadataMap.value);
    final keysToRemove = <String>[];
    int count = 0;

    for (final entry in map.entries) {
      final meta = entry.value;
      if (meta['isTrash'] == true) {
        final path = entry.key;
        try {
          final f = File(path);
          if (await f.exists()) {
            await f.delete();
          }
        } catch (e) {
          debugPrint("Error deleting file during emptyTrash: $e");
        }
        keysToRemove.add(path);
        count++;
      }
    }

    for (final k in keysToRemove) {
      map.remove(k);
    }
    metadataMap.value = map;
    await _saveMetadata();
    return count;
  }

  /// Batch move multiple recordings to trash
  Future<int> batchMoveToTrash(Iterable<String> paths) async {
    final map = Map<String, Map<String, dynamic>>.from(metadataMap.value);
    int count = 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final path in paths) {
      final current = map[path] ?? <String, dynamic>{};
      current['isTrash'] = true;
      current['trashedAt'] = now;
      map[path] = current;
      count++;
    }
    metadataMap.value = map;
    await _saveMetadata();
    return count;
  }

  /// Batch restore multiple recordings from trash
  Future<int> batchRestoreFromTrash(Iterable<String> paths) async {
    final map = Map<String, Map<String, dynamic>>.from(metadataMap.value);
    int count = 0;
    for (final path in paths) {
      final current = map[path] ?? <String, dynamic>{};
      current['isTrash'] = false;
      current['trashedAt'] = null;
      map[path] = current;
      count++;
    }
    metadataMap.value = map;
    await _saveMetadata();
    return count;
  }

  /// Batch permanently delete multiple recordings from disk and metadata
  Future<int> batchDeletePermanently(Iterable<String> paths) async {
    final map = Map<String, Map<String, dynamic>>.from(metadataMap.value);
    int count = 0;
    for (final path in paths) {
      try {
        final f = File(path);
        if (await f.exists()) {
          await f.delete();
        }
      } catch (e) {
        debugPrint("Error deleting file permanently: $e");
      }
      map.remove(path);
      count++;
    }
    metadataMap.value = map;
    await _saveMetadata();
    return count;
  }

  /// Batch favorite or unfavorite multiple recordings
  Future<int> batchToggleFavorite(Iterable<String> paths, bool favorite) async {
    final map = Map<String, Map<String, dynamic>>.from(metadataMap.value);
    int count = 0;
    for (final path in paths) {
      final current = map[path] ?? <String, dynamic>{};
      current['isFavorite'] = favorite;
      map[path] = current;
      count++;
    }
    metadataMap.value = map;
    await _saveMetadata();
    return count;
  }
}
