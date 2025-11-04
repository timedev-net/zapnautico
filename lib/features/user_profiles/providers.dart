import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase_providers.dart';
import 'data/user_profile_repository.dart';
import 'domain/profile_models.dart';

final profileTypesProvider = FutureProvider<List<ProfileType>>((ref) {
  return ref.watch(userProfileRepositoryProvider).fetchProfileTypes();
});

final currentUserProfilesProvider =
    FutureProvider<List<UserProfileAssignment>>((ref) async {
  final user = ref.watch(userProvider);
  final repository = ref.watch(userProfileRepositoryProvider);

  if (user == null) {
    return [];
  }

  return repository.fetchProfilesForUser(user.id);
});

final isAdminProvider = Provider<bool>((ref) {
  final profiles = ref.watch(currentUserProfilesProvider);

  return profiles.maybeWhen(
    data: (value) => value.any((profile) => profile.profileSlug == 'administrador'),
    orElse: () => false,
  );
});

final adminUsersWithProfilesProvider =
    FutureProvider<List<AppUserWithProfiles>>((ref) {
  return ref.watch(userProfileRepositoryProvider).adminFetchUsersWithProfiles();
});

