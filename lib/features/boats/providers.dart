import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../user_profiles/providers.dart';
import 'data/boat_repository.dart';
import 'domain/boat.dart';

final boatsProvider = FutureProvider<List<Boat>>((ref) async {
  final repository = ref.watch(boatRepositoryProvider);
  String? marinaId;

  try {
    final profiles = await ref.watch(currentUserProfilesProvider.future);
    for (final profile in profiles) {
      if (profile.profileSlug == 'marina' && profile.marinaId != null) {
        marinaId = profile.marinaId;
        break;
      }
    }
  } catch (_) {
    marinaId = null;
  }

  return repository.fetchBoats(marinaId: marinaId);
});

final boatFutureProvider = FutureProvider.family<Boat?, String>((ref, boatId) {
  return ref.watch(boatRepositoryProvider).fetchBoatById(boatId);
});
