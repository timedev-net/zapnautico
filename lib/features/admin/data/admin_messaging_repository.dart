import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_providers.dart';

class AdminMessagingRepository {
  AdminMessagingRepository(this._client);

  final SupabaseClient _client;

  Future<AdminBroadcastResult> sendBroadcastNotification({
    required String title,
    required String body,
    Map<String, String>? data,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'admin_broadcast_push',
        body: {
          'title': title,
          'body': body,
          if (data != null && data.isNotEmpty) 'data': data,
        },
      );

      return AdminBroadcastResult.fromResponse(response.data);
    } on FunctionException catch (error) {
      final details = error.details;
      if (details is Map && details['error'] is String) {
        throw AdminPushException(details['error'] as String);
      }
      throw AdminPushException(
        details?.toString() ?? 'Falha (${error.status}) ao enviar notificações.',
      );
    } catch (error) {
      throw AdminPushException('Não foi possível enviar a notificação: $error');
    }
  }
}

class AdminBroadcastResult {
  const AdminBroadcastResult({
    this.delivered = 0,
    this.failed = 0,
    this.targetedDevices = 0,
    this.message,
  });

  final int delivered;
  final int failed;
  final int targetedDevices;
  final String? message;

  bool get hasMessage => message != null && message!.isNotEmpty;

  factory AdminBroadcastResult.fromResponse(dynamic data) {
    if (data is Map<String, dynamic>) {
      return AdminBroadcastResult(
        delivered: _toInt(data['delivered']) ?? 0,
        failed: _toInt(data['failed']) ?? 0,
        targetedDevices:
            _toInt(data['targetedDevices']) ?? _toInt(data['totalRecipients']) ?? 0,
        message: data['message'] as String?,
      );
    }

    if (data is String && data.isNotEmpty) {
      return AdminBroadcastResult(message: data);
    }

    return const AdminBroadcastResult();
  }

  static int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value);
      return parsed;
    }
    return null;
  }
}

class AdminPushException implements Exception {
  AdminPushException(this.message);

  final String message;

  @override
  String toString() => message;
}

final adminMessagingRepositoryProvider =
    Provider<AdminMessagingRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return AdminMessagingRepository(client);
});
