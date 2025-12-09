class UserNotification {
  UserNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.status,
    required this.createdAt,
    this.data,
    this.readAt,
  });

  final String id;
  final String title;
  final String body;
  final String status;
  final Map<String, dynamic>? data;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isPending => status == 'pending';

  factory UserNotification.fromMap(Map<String, dynamic> map) {
    return UserNotification(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      body: map['body']?.toString() ?? '',
      status: map['status']?.toString() ?? 'pending',
      data: map['data'] as Map<String, dynamic>?,
      createdAt: _parseDate(map['created_at']),
      readAt: _parseNullableDate(map['read_at']),
    );
  }

  static DateTime _parseDate(dynamic value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.parse(value);
    return DateTime.now();
  }

  static DateTime? _parseNullableDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
