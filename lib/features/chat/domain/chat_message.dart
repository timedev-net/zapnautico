class ChatMessage {
  ChatMessage({
    required this.id,
    required this.channelId,
    required this.content,
    required this.senderId,
    required this.createdAt,
    this.senderName,
  });

  final String id;
  final String channelId;
  final String content;
  final String senderId;
  final DateTime createdAt;
  final String? senderName;

  factory ChatMessage.fromMap(Map<String, dynamic> data) {
    return ChatMessage(
      id: data['id']?.toString() ?? '',
      channelId: data['channel_id']?.toString() ?? 'geral',
      content: data['content'] as String? ?? '',
      senderId: data['sender_id']?.toString() ?? '',
      createdAt: DateTime.parse(data['created_at'] as String),
      senderName: data['sender_name'] as String?,
    );
  }
}

