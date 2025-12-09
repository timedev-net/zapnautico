import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_providers.dart';

class QueueNotificationService {
  QueueNotificationService(this._client);

  final SupabaseClient _client;

  Future<void> notifyStatusChange({
    required String entryId,
    required String status,
  }) async {
    if (entryId.isEmpty || status.isEmpty) return;

    try {
      await _client.functions.invoke(
        'notify_queue_status_change',
        body: {
          'entry_id': entryId,
          'status': status,
        },
      );
    } catch (error, stackTrace) {
      debugPrint('Falha ao enviar push de status da fila: $error');
      debugPrint('$stackTrace');
    }
  }
}

final queueNotificationServiceProvider =
    Provider<QueueNotificationService>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return QueueNotificationService(client);
});
