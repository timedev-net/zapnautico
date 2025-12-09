import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_providers.dart';
import '../notifications/data/notification_repository.dart';
import '../notifications/domain/user_notification.dart';

final pendingNotificationsCountProvider = FutureProvider<int>((ref) async {
  final repository = ref.watch(notificationRepositoryProvider);
  return repository.fetchPendingCount();
});

final userNotificationsProvider = FutureProvider<List<UserNotification>>((
  ref,
) async {
  final repository = ref.watch(notificationRepositoryProvider);
  return repository.fetchNotifications();
});

final notificationsRealtimeSyncProvider = Provider.autoDispose<void>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final userId = ref.watch(userProvider)?.id;
  if (userId == null || userId.isEmpty) return;

  final channel = client.channel('realtime-user-notifications');

  void refresh() {
    ref.invalidate(userNotificationsProvider);
    ref.invalidate(pendingNotificationsCountProvider);
  }

  channel
    ..onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'user_notifications',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'user_id',
        value: userId,
      ),
      callback: (_) => refresh(),
    )
    ..onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'user_notifications',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'user_id',
        value: userId,
      ),
      callback: (_) => refresh(),
    )
    ..onPostgresChanges(
      event: PostgresChangeEvent.delete,
      schema: 'public',
      table: 'user_notifications',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'user_id',
        value: userId,
      ),
      callback: (_) => refresh(),
    );

  channel.subscribe();

  ref.onDispose(() async {
    try {
      await channel.unsubscribe();
    } catch (_) {}
    try {
      await client.removeChannel(channel);
    } catch (_) {}
  });
});
