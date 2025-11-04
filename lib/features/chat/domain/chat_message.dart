class ChatMessage {
  ChatMessage({
    required this.id,
    required this.groupId,
    required this.content,
    required this.senderId,
    required this.createdAt,
    this.senderName,
    this.senderAvatarUrl,
  });

  final String id;
  final String groupId;
  final String content;
  final String senderId;
  final DateTime createdAt;
  final String? senderName;
  final String? senderAvatarUrl;

  factory ChatMessage.fromMap(Map<String, dynamic> data) {
    final createdAtRaw = data['created_at'];
    final createdAt = createdAtRaw is DateTime
        ? createdAtRaw.toUtc()
        : DateTime.tryParse(createdAtRaw?.toString() ?? '')?.toUtc();

    return ChatMessage(
      id: data['id']?.toString() ?? '',
      groupId: data['group_id']?.toString() ??
          data['channel_id']?.toString() ??
          '00000000-0000-0000-0000-000000000001',
      content: data['content'] as String? ?? '',
      senderId: data['sender_id']?.toString() ?? '',
      createdAt: createdAt ?? DateTime.now().toUtc(),
      senderName: data['sender_name'] as String?,
      senderAvatarUrl: data['sender_avatar_url'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'group_id': groupId,
      'content': content,
      'sender_id': senderId,
      'created_at': createdAt.toIso8601String(),
      'sender_name': senderName,
      'sender_avatar_url': senderAvatarUrl,
    };
  }
}
