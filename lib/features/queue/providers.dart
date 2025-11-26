import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../boats/data/boat_repository.dart';
import '../boats/domain/boat.dart';
import '../user_profiles/domain/profile_models.dart';
import '../user_profiles/providers.dart';
import '../../core/supabase_providers.dart';
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

/// Keeps the queue entries updated by listening to realtime changes.
final queueRealtimeSyncProvider = Provider.autoDispose<void>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final channel = client.channel('realtime-boat-launch-queue');

  void refresh() => ref.invalidate(queueEntriesProvider);

  channel
    ..onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'boat_launch_queue',
      callback: (_) => refresh(),
    )
    ..onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'boat_launch_queue',
      callback: (_) => refresh(),
    )
    ..onPostgresChanges(
      event: PostgresChangeEvent.delete,
      schema: 'public',
      table: 'boat_launch_queue',
      callback: (_) => refresh(),
    );

  channel.subscribe();

  ref.onDispose(() async {
    try {
      await channel.unsubscribe();
    } catch (_) {}
    try {
      await client.removeChannel(channel);
    } catch (_) {}
  });
});
