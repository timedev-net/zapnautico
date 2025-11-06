import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_providers.dart';
import '../domain/launch_queue_entry.dart';

class LaunchQueueRepository {
  LaunchQueueRepository(this._client);

  final SupabaseClient _client;

  Future<List<LaunchQueueEntry>> fetchQueue({required String marinaId}) async {
    final response = await _client
        .from('boat_launch_queue_view')
        .select()
        .eq('marina_id', marinaId)
        .order('queue_position', ascending: true);

    final data = (response as List).cast<Map<String, dynamic>>();
    return data.map(LaunchQueueEntry.fromMap).toList();
  }

  Future<void> enqueueBoat({
    required String boatId,
    required String marinaId,
  }) async {
    await _client.from('boat_launch_queue').insert({
      'boat_id': boatId,
      'marina_id': marinaId,
    });
  }

  Future<void> enqueueGenericEntry({
    required String marinaId,
    String? label,
  }) async {
    await _client.from('boat_launch_queue').insert({
      'marina_id': marinaId,
      'generic_boat_name': (label?.trim().isNotEmpty ?? false)
          ? label!.trim()
          : 'Embarcação aguardando descida',
    });
  }

  Future<void> cancelRequest(String entryId) async {
    await _client.from('boat_launch_queue').delete().eq('id', entryId);
  }

  Future<void> updateEntry({
    required String entryId,
    String? status,
    DateTime? processedAt,
    String? genericBoatName,
  }) async {
    final updatePayload = <String, dynamic>{};

    if (status != null) {
      updatePayload['status'] = status;
    }

    if (processedAt != null) {
      updatePayload['processed_at'] = processedAt.toUtc().toIso8601String();
    }

    if (genericBoatName != null) {
      updatePayload['generic_boat_name'] = genericBoatName.trim();
    }

    if (updatePayload.isEmpty) {
      return;
    }

    await _client
        .from('boat_launch_queue')
        .update(updatePayload)
        .eq('id', entryId);
  }

  Future<void> notifyMarinaLaunchRequest({
    required String marinaId,
    required String boatId,
  }) async {
    try {
      await _client.functions.invoke(
        'notify_marina_launch_request',
        body: {'marina_id': marinaId, 'boat_id': boatId},
      );
    } catch (_) {
      // Ignora falhas de notificação para não interromper o fluxo principal.
    }
  }
}

final launchQueueRepositoryProvider = Provider<LaunchQueueRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return LaunchQueueRepository(client);
});
