import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/chat_group.dart';
import '../domain/chat_message.dart';
import '../domain/typing_user.dart';

class ChatRepository {
  ChatRepository(this._client);

  final SupabaseClient _client;
  final Map<String, _GroupChannelState> _groupChannels = {};

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
      if (controller.isClosed) return;
      messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      controller.add(List<ChatMessage>.unmodifiable(messages));
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

    void upsertMessage(ChatMessage message) {
      final index = messages.indexWhere((m) => m.id == message.id);
      if (index == -1) {
        messages.add(message);
      } else {
        messages[index] = message;
      }
      unawaited(emit());
    }

    void removeMessage(String id) {
      messages.removeWhere((m) => m.id == id);
      unawaited(emit());
    }

    final channelState = _acquireGroupChannel(groupId);
    final channel = channelState.channel;

    final postgresFilter = PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'group_id',
      value: groupId,
    );

    channel
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'chat_messages',
        filter: postgresFilter,
        callback: (change) {
          switch (change.eventType) {
            case PostgresChangeEvent.insert:
              upsertMessage(ChatMessage.fromMap(change.newRecord));
              break;
            case PostgresChangeEvent.update:
              upsertMessage(ChatMessage.fromMap(change.newRecord));
              break;
            case PostgresChangeEvent.delete:
              final id = change.oldRecord['id']?.toString();
              if (id != null && id.isNotEmpty) {
                removeMessage(id);
              }
              break;
            default:
              break;
          }
        },
      )
      ..onBroadcast(
        event: 'new-message',
        callback: (payload) {
          upsertMessage(ChatMessage.fromMap(payload));
        },
      );

    controller
      ..onListen = () async {
        await loadInitial();
        if (!channelState.subscribed) {
          channelState.subscribed = true;
          channel.subscribe();
        }
      }
      ..onCancel = () async {
        await _releaseGroupChannel(groupId, channel);
      };

    return controller.stream;
  }

  Stream<int> watchOnlineUsers(
    String groupId, {
    bool trackCurrentUser = true,
  }) {
    final controller = StreamController<int>.broadcast();
    final user = _client.auth.currentUser;
    final channel = _client.channel(
      'chat-group-$groupId-presence',
      opts: const RealtimeChannelConfig(
        key: 'user_id',
      ),
    );

    void emitCount() {
      if (controller.isClosed) return;
      final state = channel.presenceState();
      final count = state.fold<int>(
        0,
        (total, presence) => total + presence.presences.length,
      );
      controller.add(count);
    }

    channel
      ..onPresenceSync((_) => emitCount())
      ..onPresenceJoin((_) => emitCount())
      ..onPresenceLeave((_) => emitCount());

    controller
      ..onListen = () {
        channel.subscribe((status, error) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            if (trackCurrentUser && user != null) {
              final metadata = user.userMetadata ?? {};
              unawaited(
                channel.track({
                  'user_id': user.id,
                  'name': metadata['full_name'] ??
                      metadata['name'] ??
                      user.email ??
                      user.id,
                  'joined_at': DateTime.now().toIso8601String(),
                  'group_id': groupId,
                }).then((_) => emitCount()),
              );
            } else {
              emitCount();
            }
          } else if (status == RealtimeSubscribeStatus.channelError) {
            if (!controller.isClosed) {
              controller.addError(
                error ?? StateError('Não foi possível acompanhar usuários online.'),
              );
            }
          }
        });
      }
      ..onCancel = () async {
        try {
          await channel.untrack();
        } catch (_) {
          // Ignore untrack failures (e.g., before subscription completes).
        }
        try {
          await channel.unsubscribe();
        } catch (_) {
          // Best-effort unsubscribe; ignore errors to avoid breaking stream disposal.
        }
        await _client.removeChannel(channel);
      };

    return controller.stream;
  }

  Stream<Set<TypingUser>> watchTypingUsers(String groupId) {
    final controller = StreamController<Set<TypingUser>>.broadcast();
    final typingUsers = <String, _TypingSnapshot>{};
    Timer? cleanupTimer;

    void emit() {
      if (controller.isClosed) return;
      controller.add(typingUsers.entries
          .map((entry) => TypingUser(userId: entry.key, name: entry.value.name))
          .toSet());
    }

    void ensureCleanupTimer() {
      if (typingUsers.isEmpty) {
        cleanupTimer?.cancel();
        cleanupTimer = null;
        return;
      }
      cleanupTimer ??= Timer.periodic(const Duration(seconds: 5), (_) {
        final now = DateTime.now();
        var removed = false;
        typingUsers.removeWhere((key, snapshot) {
          final expired = now.difference(snapshot.lastEvent) > const Duration(seconds: 4);
          if (expired) removed = true;
          return expired;
        });
        if (removed) {
          emit();
        }
        if (typingUsers.isEmpty) {
          cleanupTimer?.cancel();
          cleanupTimer = null;
        }
      });
    }

    void handleTypingPayload(Map<String, dynamic> payload) {
      final userId = payload['user_id']?.toString();
      if (userId == null || userId.isEmpty) return;
      final isTyping = payload['is_typing'] as bool? ?? true;
      final name = payload['name'] as String? ?? 'Cotista';

      if (isTyping) {
        typingUsers[userId] = _TypingSnapshot(name: name, lastEvent: DateTime.now());
      } else {
        typingUsers.remove(userId);
      }

      ensureCleanupTimer();
      emit();
    }

    final channelState = _acquireGroupChannel(groupId);
    final channel = channelState.channel;

    channel.onBroadcast(
      event: 'typing',
      callback: (payload) => handleTypingPayload(payload),
    );

    controller
      ..onListen = () {
        emit();
        if (!channelState.subscribed) {
          channelState.subscribed = true;
          channel.subscribe();
        }
      }
      ..onCancel = () async {
        cleanupTimer?.cancel();
        await _releaseGroupChannel(groupId, channel);
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

  Future<void> notifyTyping({
    required String groupId,
    required bool isTyping,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    final metadata = user.userMetadata ?? {};
    final senderName = metadata['full_name'] as String? ??
        metadata['name'] as String? ??
        user.email ??
        'Cotista';

    final payload = {
      'user_id': user.id,
      'name': senderName,
      'is_typing': isTyping,
      'sent_at': DateTime.now().toIso8601String(),
    };

    final activeChannel = _currentGroupChannel(groupId);
    if (activeChannel != null) {
      try {
        await activeChannel.sendBroadcastMessage(
          event: 'typing',
          payload: payload,
        );
        return;
      } catch (_) {
        // Fallback to temporary channel below.
      }
    }

    final channel = _client.channel('chat-group-$groupId');
    try {
      await channel.sendBroadcastMessage(
        event: 'typing',
        payload: payload,
      );
    } finally {
      await _client.removeChannel(channel);
    }
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

    final Map<String, dynamic> inserted = await _client
        .from('chat_messages')
        .insert({
          'group_id': groupId,
          'content': content,
          'sender_id': user.id,
          'sender_name': senderName,
          'sender_avatar_url': avatarUrl,
        })
        .select()
        .single();

    final message = ChatMessage.fromMap(inserted);
    unawaited(_broadcastNewMessage(groupId, message));
  }

  Future<void> _broadcastNewMessage(String groupId, ChatMessage message) async {
    final payload = message.toMap();
    final channel = _currentGroupChannel(groupId);

    if (channel != null) {
      try {
        await channel.sendBroadcastMessage(
          event: 'new-message',
          payload: payload,
        );
        return;
      } catch (_) {
        // Fallback for cases where the channel is not fully joined locally.
      }
    }

    final tempChannel = _client.channel('chat-group-$groupId');
    try {
      await tempChannel.sendBroadcastMessage(
        event: 'new-message',
        payload: payload,
      );
    } finally {
      await _client.removeChannel(tempChannel);
    }
  }

  _GroupChannelState _acquireGroupChannel(String groupId) {
    final state = _groupChannels.putIfAbsent(
      groupId,
      () => _GroupChannelState(
        _client.channel(
          'chat-group-$groupId',
          opts: const RealtimeChannelConfig(
            ack: false,
            self: true,
          ),
        ),
      ),
    );
    state.listeners++;
    return state;
  }

  Future<void> _releaseGroupChannel(
    String groupId,
    RealtimeChannel channel,
  ) async {
    final state = _groupChannels[groupId];
    if (state == null) return;

    state.listeners = state.listeners - 1;
    if (state.listeners <= 0) {
      state.listeners = 0;
      if (state.subscribed) {
        try {
          await channel.unsubscribe();
        } catch (_) {
          // Ignore teardown errors.
        }
      }
      await _client.removeChannel(channel);
      _groupChannels.remove(groupId);
    }
  }

  RealtimeChannel? _currentGroupChannel(String groupId) {
    return _groupChannels[groupId]?.channel;
  }
}

class _GroupChannelState {
  _GroupChannelState(this.channel);

  final RealtimeChannel channel;
  int listeners = 0;
  bool subscribed = false;
}

class _TypingSnapshot {
  _TypingSnapshot({required this.name, required this.lastEvent});

  final String name;
  DateTime lastEvent;
}
