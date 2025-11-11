import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase_providers.dart';
import 'data/user_contact_repository.dart';
import 'domain/user_contact_channel.dart';

final userContactsProvider =
    FutureProvider<List<UserContactChannel>>((ref) async {
  final user = ref.watch(userProvider);
  if (user == null) {
    return [];
  }

  return ref
      .watch(userContactRepositoryProvider)
      .fetchContacts(user.id);
});
