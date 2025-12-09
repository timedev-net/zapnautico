import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_providers.dart';
import '../domain/user_notification.dart';

class NotificationRepository {
  NotificationRepository(this._client);

  final SupabaseClient _client;

  Future<int> fetchPendingCount() async {
    final response = await _client
        .from('user_notifications')
        .select('id')
        .eq('status', 'pending');

    return (response as List).length;
  }

  Future<List<UserNotification>> fetchNotifications({int limit = 100}) async {
    final response = await _client
        .from('user_notifications')
        .select()
        .order('created_at', ascending: false)
        .limit(limit);

    final data = (response as List).cast<Map<String, dynamic>>();
    return data.map(UserNotification.fromMap).toList();
  }

  Future<void> markAsRead(String notificationId) async {
    if (notificationId.isEmpty) return;
    await _client
        .from('user_notifications')
        .update({
          'status': 'read',
          'read_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', notificationId);
  }

  Future<void> markAllAsRead() async {
    await _client
        .from('user_notifications')
        .update({
          'status': 'read',
          'read_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('status', 'pending');
  }
}

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return NotificationRepository(client);
});
