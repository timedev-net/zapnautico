import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/chat_group.dart';
import '../domain/chat_message.dart';

class ChatRepository {
  ChatRepository(this._client);

  final SupabaseClient _client;

  Stream<List<ChatGroup>> watchGroups() {
    return _client
        .from('chat_groups')
        .stream(primaryKey: ['id'])
        .order('name')
        .map((rows) => rows.map(ChatGroup.fromMap).toList());
  }

  Stream<Set<String>> watchMembership(String userId) {
    return _client
        .from('chat_group_members')
        .stream(primaryKey: ['group_id', 'user_id'])
        .eq('user_id', userId)
        .map((rows) => rows
            .map((row) => row['group_id']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toSet());
  }

  Stream<List<ChatMessage>> watchMessages(String groupId) {
    final controller = StreamController<List<ChatMessage>>.broadcast();
    var messages = <ChatMessage>[];

    Future<void> emit() async {
      if (!controller.isClosed) {
        messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        controller.add(List.unmodifiable(messages));
      }
    }

    Future<void> loadInitial() async {
      final response = await _client
          .from('chat_messages')
          .select()
          .eq('group_id', groupId)
          .order('created_at');
      final data = (response as List).cast<Map<String, dynamic>>();
      messages = data.map(ChatMessage.fromMap).toList();
      await emit();
    }

    final channel = _client.channel('chat-group-$groupId');

    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'chat_messages',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'group_id',
        value: groupId,
      ),
      callback: (change) async {
        switch (change.eventType) {
          case PostgresChangeEvent.insert:
            messages.add(ChatMessage.fromMap(change.newRecord));
            await emit();
            break;
          case PostgresChangeEvent.update:
            final newRecord = change.newRecord;
            final index = messages.indexWhere((m) => m.id == newRecord['id']?.toString());
            if (index != -1) {
              messages[index] = ChatMessage.fromMap(newRecord);
              await emit();
            }
            break;
          case PostgresChangeEvent.delete:
            final oldRecord = change.oldRecord;
            messages.removeWhere((m) => m.id == oldRecord['id']?.toString());
            await emit();
            break;
          default:
            break;
        }
      },
    );

    controller
      ..onListen = () async {
        await loadInitial();
        channel.subscribe();
      }
      ..onCancel = () async {
        await channel.unsubscribe();
        _client.removeChannel(channel);
      };

    return controller.stream;
  }

  Future<void> createGroup({
    required String name,
    String? description,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('Usuário não autenticado.');
    }

    await _client.from('chat_groups').insert({
      'name': name,
      'description': description,
      'created_by': user.id,
    });
  }

  Future<void> joinGroup(String groupId) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('Usuário não autenticado.');
    }

    await _client.from('chat_group_members').insert({
      'group_id': groupId,
      'user_id': user.id,
    });
  }

  Future<void> leaveGroup(String groupId) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('Usuário não autenticado.');
    }

    await _client
        .from('chat_group_members')
        .delete()
        .eq('group_id', groupId)
        .eq('user_id', user.id);
  }

  Future<void> sendMessage({
    required String groupId,
    required String content,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('Usuário não autenticado.');
    }

    final metadata = user.userMetadata ?? {};
    final senderName = metadata['full_name'] as String? ??
        metadata['name'] as String? ??
        user.email;
    final avatarUrl = metadata['avatar_url'] as String? ??
        user.appMetadata['avatar_url'] as String? ??
        metadata['picture'] as String?;

    await _client.from('chat_messages').insert({
      'group_id': groupId,
      'content': content,
      'sender_id': user.id,
      'sender_name': senderName,
      'sender_avatar_url': avatarUrl,
    });
  }
}
