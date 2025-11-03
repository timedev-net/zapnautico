import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/chat_message.dart';

class ChatRepository {
  ChatRepository(this._client);

  final SupabaseClient _client;

  Stream<List<ChatMessage>> subscribeToChannel(String channelId) {
    return _client
        .from('chat_messages')
        .stream(primaryKey: ['id'])
        .eq('channel_id', channelId)
        .order('created_at')
        .map((rows) => rows.map(ChatMessage.fromMap).toList());
  }

  Future<void> sendMessage({
    required String channelId,
    required String content,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('Usuário não autenticado.');
    }

    await _client.from('chat_messages').insert({
      'channel_id': channelId,
      'content': content,
      'sender_id': user.id,
      'sender_name': user.userMetadata?['full_name'] ??
          user.userMetadata?['name'] ??
          user.email,
    });
  }
}

