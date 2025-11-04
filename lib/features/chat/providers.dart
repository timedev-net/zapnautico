import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_providers.dart';
import 'data/chat_repository.dart';
import 'domain/chat_group.dart';
import 'domain/chat_message.dart';

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
