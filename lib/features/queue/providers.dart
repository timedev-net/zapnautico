import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../boats/data/boat_repository.dart';
import '../boats/domain/boat.dart';
import '../user_profiles/domain/profile_models.dart';
import '../user_profiles/providers.dart';
import 'data/launch_queue_repository.dart';
import 'domain/launch_queue_entry.dart';

const queueNoMarinaFilterValue = '__queue_no_marina__';

final queueFilterProvider = StateProvider<String?>((ref) => null);

final queueForcedMarinaIdProvider = Provider<String?>((ref) {
  final profilesAsync = ref.watch(currentUserProfilesProvider);

  return profilesAsync.maybeWhen(
    data: (profiles) {
      final isAdmin = profiles.any(
        (profile) => profile.profileSlug == 'administrador',
      );
      if (isAdmin) return null;

      for (final UserProfileAssignment profile in profiles) {
        final marinaId = profile.marinaId;
        final hasMarina = marinaId != null && marinaId.isNotEmpty;
        if (profile.profileSlug == 'marina' && hasMarina) {
          return marinaId;
        }
      }
      return null;
    },
    orElse: () => null,
  );
});

final queueAppliedFilterProvider = Provider<String?>((ref) {
  final forcedMarinaId = ref.watch(queueForcedMarinaIdProvider);
  if (forcedMarinaId != null) return forcedMarinaId;

  return ref.watch(queueFilterProvider);
});

final queueEntriesProvider =
    FutureProvider<List<LaunchQueueEntry>>((ref) async {
  final repository = ref.watch(launchQueueRepositoryProvider);
  final marinaId = ref.watch(queueAppliedFilterProvider);
  final entries = await repository.fetchEntries();

  if (marinaId == queueNoMarinaFilterValue) {
    return entries.where((entry) => entry.marinaId.isEmpty).toList();
  }

  if (marinaId != null && marinaId.isNotEmpty) {
    return entries.where((entry) => entry.marinaId == marinaId).toList();
  }

  return entries;
});

final queueOperationInProgressProvider = StateProvider<bool>((ref) => false);

final queueBoatsProvider = FutureProvider<List<Boat>>((ref) {
  final repository = ref.watch(boatRepositoryProvider);
  return repository.fetchBoats();
});
