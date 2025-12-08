import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../user_profiles/domain/profile_models.dart';
import '../user_profiles/providers.dart';
import 'data/marina_wall_repository.dart';
import 'domain/marina_wall_post.dart';

final muralPostsProvider = StreamProvider<List<MarinaWallPost>>((ref) {
  return ref.watch(marinaWallRepositoryProvider).watchPosts();
});

final currentMarinaProfileProvider = Provider<UserProfileAssignment?>((ref) {
  final profiles = ref.watch(currentUserProfilesProvider);
  return profiles.maybeWhen(
    data: (data) {
      for (final profile in data) {
        if (profile.profileSlug == 'marina' && profile.marinaId != null) {
          return profile;
        }
      }
      return null;
    },
    orElse: () => null,
  );
});
