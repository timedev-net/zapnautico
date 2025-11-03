import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/quota.dart';

class QuotasRepository {
  QuotasRepository(this._client);

  final SupabaseClient _client;

  Future<List<Quota>> fetchQuotas() async {
    final data = await _client
        .from('boat_quotas')
        .select()
        .order('next_departure', ascending: true);

    final rows = (data as List).cast<Map<String, dynamic>>();
    return rows.map(Quota.fromMap).toList();
  }

  Future<void> reserveSlot(String quotaId) async {
    await _client.rpc('reserve_quota_slot', params: {'quota_id': quotaId});
  }

  Future<void> releaseSlot(String quotaId) async {
    await _client.rpc('release_quota_slot', params: {'quota_id': quotaId});
  }
}
