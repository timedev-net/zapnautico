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
    return ChatMessage(
      id: data['id']?.toString() ?? '',
      groupId: data['group_id']?.toString() ??
          data['channel_id']?.toString() ??
          '00000000-0000-0000-0000-000000000001',
      content: data['content'] as String? ?? '',
      senderId: data['sender_id']?.toString() ?? '',
      createdAt: DateTime.parse(data['created_at'] as String),
      senderName: data['sender_name'] as String?,
      senderAvatarUrl: data['sender_avatar_url'] as String?,
    );
  }
}
