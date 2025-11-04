import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_providers.dart';
import 'data/chat_repository.dart';
import 'domain/chat_group.dart';
import 'domain/chat_message.dart';
import 'domain/typing_user.dart';

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return ChatRepository(client);
});

final chatGroupsProvider = StreamProvider<List<ChatGroup>>((ref) {
  return ref.watch(chatRepositoryProvider).watchGroups();
});

final chatGroupMembershipProvider = StreamProvider<Set<String>>((ref) {
  final user = ref.watch(userProvider) ?? Supabase.instance.client.auth.currentUser;
  if (user == null) {
    return Stream.value(<String>{});
  }
  return ref.watch(chatRepositoryProvider).watchMembership(user.id);
});

final chatMessagesProvider =
    StreamProvider.autoDispose.family<List<ChatMessage>, String>((ref, groupId) {
  return ref.watch(chatRepositoryProvider).watchMessages(groupId);
});

typedef ChatGroupPresenceParams = ({String groupId, bool trackSelf});

final chatGroupOnlineCountProvider =
    StreamProvider.autoDispose.family<int, ChatGroupPresenceParams>((ref, params) {
  return ref
      .watch(chatRepositoryProvider)
      .watchOnlineUsers(params.groupId, trackCurrentUser: params.trackSelf);
});

typedef ChatGroupTypingParams = ({String groupId, String? excludeUserId});

final chatGroupTypingProvider =
    StreamProvider.autoDispose.family<Set<TypingUser>, ChatGroupTypingParams>((ref, params) {
  return ref
      .watch(chatRepositoryProvider)
      .watchTypingUsers(params.groupId)
      .map((users) => params.excludeUserId == null
          ? users
          : users.where((user) => user.userId != params.excludeUserId).toSet());
});
