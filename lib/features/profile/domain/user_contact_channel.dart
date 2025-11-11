class UserContactChannel {
  UserContactChannel({
    required this.id,
    required this.userId,
    required this.channel,
    required this.label,
    required this.value,
    required this.position,
    required this.metadata,
  });

  final String id;
  final String userId;
  final String channel;
  final String label;
  final String value;
  final int position;
  final Map<String, dynamic> metadata;

  bool get isWhatsapp => channel == 'whatsapp';
  bool get isInstagram => channel == 'instagram';

  String get normalizedWhatsapp {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('55')) {
      return '+$digits';
    }
    return '+55$digits';
  }

  String get instaHandle {
    if (value.startsWith('@')) return value;
    return '@${value.replaceAll('@', '')}';
  }

  UserContactChannel copyWith({
    String? label,
    String? value,
    int? position,
    Map<String, dynamic>? metadata,
  }) {
    return UserContactChannel(
      id: id,
      userId: userId,
      channel: channel,
      label: label ?? this.label,
      value: value ?? this.value,
      position: position ?? this.position,
      metadata: metadata ?? this.metadata,
    );
  }

  factory UserContactChannel.fromMap(Map<String, dynamic> data) {
    return UserContactChannel(
      id: data['id']?.toString() ?? '',
      userId: data['user_id']?.toString() ?? '',
      channel: data['channel'] as String? ?? 'whatsapp',
      label: data['label'] as String? ?? '',
      value: data['value'] as String? ?? '',
      position: (data['position'] as num?)?.toInt() ?? 0,
      metadata: _parseMetadata(data['metadata']),
    );
  }

  static Map<String, dynamic> _parseMetadata(Object? source) {
    if (source is Map<String, dynamic>) {
      return source;
    }
    if (source is Map) {
      return source.map((key, value) => MapEntry(key.toString(), value));
    }
    return const {};
  }
}
