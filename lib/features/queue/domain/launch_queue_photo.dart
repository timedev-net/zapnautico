class LaunchQueuePhoto {
  LaunchQueuePhoto({
    required this.id,
    required this.queueEntryId,
    required this.storagePath,
    required this.publicUrl,
    this.createdAt,
  });

  final String id;
  final String queueEntryId;
  final String storagePath;
  final String publicUrl;
  final DateTime? createdAt;

  bool get hasUrl => publicUrl.isNotEmpty;

  factory LaunchQueuePhoto.fromMap(Map<String, dynamic> data) {
    return LaunchQueuePhoto(
      id: data['id']?.toString() ?? '',
      queueEntryId: data['queue_entry_id']?.toString() ?? '',
      storagePath: data['storage_path'] as String? ?? '',
      publicUrl: data['public_url'] as String? ?? '',
      createdAt: _parseNullableDateTime(data['created_at']),
    );
  }

  static DateTime? _parseNullableDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return null;
  }
}
