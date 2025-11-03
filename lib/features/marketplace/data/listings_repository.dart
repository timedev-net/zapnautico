import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/listing.dart';

class ListingsRepository {
  ListingsRepository(this._client);

  final SupabaseClient _client;

  Stream<List<Listing>> watchListings() {
    return _client
        .from('marketplace_listings')
        .stream(primaryKey: ['id'])
        .order('created_at')
        .map((rows) => rows.map(Listing.fromMap).toList());
  }

  Future<void> publishListing({
    required String title,
    required String type,
    required String status,
    double? price,
    String? currency,
    String? description,
    String? mediaUrl,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Usuário não autenticado.');
    }

    await _client.from('marketplace_listings').insert({
      'title': title,
      'type': type,
      'status': status,
      'price': price,
      'currency': currency,
      'description': description,
      'media_url': mediaUrl,
      'owner_id': userId,
    });
  }

  Future<void> updateListingStatus({
    required String id,
    required String status,
  }) async {
    await _client
        .from('marketplace_listings')
        .update({'status': status}).eq('id', id);
  }
}

