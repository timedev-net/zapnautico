import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase_providers.dart';
import '../user_profiles/domain/profile_models.dart';
import '../user_profiles/domain/marina_roles.dart';
import '../user_profiles/providers.dart';
import 'data/boat_repository.dart';
import 'domain/boat.dart';

final boatsProvider = FutureProvider<List<Boat>>((ref) async {
  final repository = ref.watch(boatRepositoryProvider);
  final user = ref.watch(userProvider);

  List<UserProfileAssignment> profiles = const [];
  try {
    profiles = await ref.watch(currentUserProfilesProvider.future);
  } catch (_) {
    profiles = const [];
  }

  final isAdmin = profiles.any(
    (profile) => profile.profileSlug == 'administrador',
  );

  String? marinaId;
  if (!isAdmin) {
    for (final profile in profiles) {
      if (isMarinaRoleSlug(profile.profileSlug) &&
          profile.marinaId != null) {
        marinaId = profile.marinaId;
        break;
      }
    }
  }

  String? ownerId;
  final hasOwnerProfile = profiles.any(
    (profile) =>
        profile.profileSlug == 'proprietario' ||
        profile.profileSlug == 'cotista',
  );
  if (!isAdmin && marinaId == null && hasOwnerProfile && user != null) {
    ownerId = user.id;
  }

  return repository.fetchBoats(marinaId: marinaId, ownerId: ownerId);
});

final boatFutureProvider = FutureProvider.family<Boat?, String>((ref, boatId) {
  return ref.watch(boatRepositoryProvider).fetchBoatById(boatId);
});
