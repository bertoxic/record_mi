class RecordingItem {
  final String path;
  final String name;
  final int size;
  final int lastModified;
  final String callType;
  final String contactNumber;
  String? customTitle;
  bool isFavorite;
  bool isTrash;
  int? trashedAt;
  String? note;
  Duration? duration;

  RecordingItem({
    required this.path,
    required this.name,
    required this.size,
    required this.lastModified,
    required this.callType,
    required this.contactNumber,
    this.customTitle,
    this.isFavorite = false,
    this.isTrash = false,
    this.trashedAt,
    this.note,
    this.duration,
  });

  String get displayTitle {
    if (customTitle != null && customTitle!.trim().isNotEmpty) {
      return customTitle!.trim();
    }
    if (callType.toLowerCase().contains('voip') || callType.toLowerCase().contains('whatsapp')) {
      if (contactNumber.toLowerCase() == 'whatsapp' || contactNumber.toLowerCase() == 'unknown' || contactNumber.isEmpty) {
        return 'WhatsApp Call';
      }
    }
    return contactNumber;
  }

  DateTime get date => DateTime.fromMillisecondsSinceEpoch(lastModified);

  String get formattedSize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String get formattedDate {
    final d = date;
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final month = months[d.month - 1];
    final hour = d.hour == 0 ? 12 : (d.hour > 12 ? d.hour - 12 : d.hour);
    final amPm = d.hour >= 12 ? 'PM' : 'AM';
    final minute = d.minute.toString().padLeft(2, '0');
    return '$month ${d.day}, ${d.year} • $hour:$minute $amPm';
  }

  int daysLeftInTrash(int retentionDays) {
    if (trashedAt == null) return retentionDays;
    final trashDate = DateTime.fromMillisecondsSinceEpoch(trashedAt!);
    final daysPassed = DateTime.now().difference(trashDate).inDays;
    final remaining = retentionDays - daysPassed;
    return remaining > 0 ? remaining : 0;
  }

  bool isExpired(int retentionDays) {
    if (!isTrash || trashedAt == null) return false;
    final trashDate = DateTime.fromMillisecondsSinceEpoch(trashedAt!);
    return DateTime.now().difference(trashDate).inDays >= retentionDays;
  }

  Map<String, dynamic> toJson() => {
    'path': path,
    'name': name,
    'size': size,
    'lastModified': lastModified,
    'callType': callType,
    'contactNumber': contactNumber,
    'customTitle': customTitle,
    'isFavorite': isFavorite,
    'isTrash': isTrash,
    'trashedAt': trashedAt,
    'note': note,
    'durationMs': duration?.inMilliseconds,
  };

  factory RecordingItem.fromJson(Map<String, dynamic> json) => RecordingItem(
    path: json['path'] as String,
    name: json['name'] as String,
    size: (json['size'] as num?)?.toInt() ?? 0,
    lastModified: (json['lastModified'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
    callType: json['callType'] as String? ?? 'Call',
    contactNumber: json['contactNumber'] as String? ?? 'Unknown',
    customTitle: json['customTitle'] as String?,
    isFavorite: json['isFavorite'] as bool? ?? false,
    isTrash: json['isTrash'] as bool? ?? false,
    trashedAt: (json['trashedAt'] as num?)?.toInt(),
    note: json['note'] as String?,
    duration: json['durationMs'] != null ? Duration(milliseconds: (json['durationMs'] as num).toInt()) : null,
  );
}
