import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_providers.dart';
import '../domain/user_contact_channel.dart';

class UserContactRepository {
  UserContactRepository(this._client);

  final SupabaseClient _client;

  Future<List<UserContactChannel>> fetchContacts(String userId) async {
    final response = await _client
        .from('user_contact_channels')
        .select()
        .eq('user_id', userId)
        .order('channel')
        .order('position');

    final data = (response as List).cast<Map<String, dynamic>>();
    return data.map(UserContactChannel.fromMap).toList();
  }

  Future<UserContactChannel> upsertContact({
    String? id,
    required String channel,
    required String label,
    required String value,
  }) async {
    final sanitizedValue = channel == 'whatsapp'
        ? _sanitizeWhatsapp(value)
        : _sanitizeInstagram(value);
    final payload = <String, dynamic>{
      'channel': channel,
      'label': label.trim(),
      'value': sanitizedValue,
    };

    Map<String, dynamic> response;
    if (id == null) {
      final userId = _requireUserId();
      payload['user_id'] = userId;
      payload['position'] = await _nextPosition(userId, channel);

      response = await _client
          .from('user_contact_channels')
          .insert(payload)
          .select()
          .single();
    } else {
      response = await _client
          .from('user_contact_channels')
          .update(payload)
          .eq('id', id)
          .select()
          .single();
    }

    return UserContactChannel.fromMap(response);
  }

  Future<void> deleteContact(String id) async {
    await _client.from('user_contact_channels').delete().eq('id', id);
  }

  Future<int> _nextPosition(String userId, String channel) async {
    final response = await _client
        .from('user_contact_channels')
        .select('position')
        .eq('user_id', userId)
        .eq('channel', channel)
        .order('position', ascending: false)
        .limit(1)
        .maybeSingle();

    if (response == null) {
      return 0;
    }
    final position = (response['position'] as num?)?.toInt() ?? -1;
    return position + 1;
  }

  String _requireUserId() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Usuário não autenticado.');
    }
    return userId;
  }

  String _sanitizeWhatsapp(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    var normalized = digits.startsWith('55') ? digits.substring(2) : digits;
    if (normalized.length > 11) {
      normalized = normalized.substring(normalized.length - 11);
    }
    if (normalized.length < 10) {
      throw StateError('Informe o DDD e o número com pelo menos 10 dígitos.');
    }
    final full = '55$normalized';
    return '+$full';
  }

  String _sanitizeInstagram(String value) {
    final trimmed = value.trim().replaceAll('@', '');
    if (trimmed.isEmpty) {
      throw StateError('Informe o usuário do Instagram.');
    }
    return trimmed;
  }
}

final userContactRepositoryProvider = Provider<UserContactRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return UserContactRepository(client);
});
