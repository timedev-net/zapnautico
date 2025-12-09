import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_providers.dart';
import '../boats/data/boat_repository.dart';
import '../boats/domain/boat.dart';
import '../boats/providers.dart';
import '../user_profiles/domain/marina_roles.dart';
import '../user_profiles/providers.dart';
import 'data/launch_queue_repository.dart';
import 'domain/launch_queue_entry.dart';

class QueueEntriesState {
  const QueueEntriesState({
    required this.entries,
    required this.inWaterCountForSelectedMarina,
  });

  final List<LaunchQueueEntry> entries;
  final int inWaterCountForSelectedMarina;
}

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

      final marinaProfile = firstMarinaProfile(profiles);
      final marinaId = marinaProfile?.marinaId;
      final hasMarina = marinaId != null && marinaId.isNotEmpty;
      if (hasMarina) return marinaId;
      return null;
    },
    orElse: () => null,
  );
});

final queueOwnerDefaultMarinaIdProvider = Provider<String?>((ref) {
  final profilesAsync = ref.watch(currentUserProfilesProvider);
  final hasOwnerProfile =
      profilesAsync.asData?.value.any(
        (profile) =>
            profile.profileSlug == 'proprietario' ||
            profile.profileSlug == 'cotista',
      ) ??
      false;

  if (!hasOwnerProfile) {
    return null;
  }

  final boatsAsync = ref.watch(boatsProvider);
  final boats = boatsAsync.asData?.value;

  if (boats == null || boats.isEmpty) {
    return null;
  }

  for (final boat in boats) {
    final marinaId = boat.marinaId;
    if (marinaId != null && marinaId.isNotEmpty) {
      return marinaId;
    }
  }

  return null;
});

final queueAppliedFilterProvider = Provider<String?>((ref) {
  final forcedMarinaId = ref.watch(queueForcedMarinaIdProvider);
  if (forcedMarinaId != null) return forcedMarinaId;

  final currentFilter = ref.watch(queueFilterProvider);
  if (currentFilter != null) {
    return currentFilter;
  }

  final ownerDefault = ref.watch(queueOwnerDefaultMarinaIdProvider);
  return ownerDefault?.isNotEmpty == true ? ownerDefault : null;
});

final queueEntriesProvider = StreamProvider<QueueEntriesState>((ref) async* {
  final client = ref.watch(supabaseClientProvider);
  final profiles = await ref.watch(currentUserProfilesProvider.future);
  final currentUserId = ref.watch(userProvider)?.id ?? '';

  final hasAdminProfile = profiles.any(
    (profile) => profile.profileSlug == 'administrador',
  );
  final hasMarinaProfile = hasMarinaRole(profiles);
  final hasOwnerProfile = profiles.any(
    (profile) =>
        profile.profileSlug == 'proprietario' ||
        profile.profileSlug == 'cotista',
  );

  final now = DateTime.now();
  final String? marinaFilter = hasMarinaProfile
      ? ref.watch(queueForcedMarinaIdProvider)
      : null;
  final marinaId = ref.watch(queueAppliedFilterProvider);

  final statuses = [
    'pending',
    'in_progress',
    'in_water',
    'completed',
    'cancelled',
  ];

  final streamBuilder = client
      .from('boat_launch_queue_view')
      .stream(primaryKey: ['id']);

  final stream = (marinaFilter != null && marinaFilter.isNotEmpty)
      ? streamBuilder.eq('marina_id', marinaFilter)
      : streamBuilder.inFilter('status', statuses);

  await for (final rows in stream) {
    final baseEntries = rows
        .cast<Map<String, dynamic>>()
        .map(LaunchQueueEntry.fromMap)
        .where((entry) => statuses.contains(entry.status))
        .toList();

    Iterable<LaunchQueueEntry> filteredEntries = baseEntries;

    if (marinaId == queueNoMarinaFilterValue) {
      filteredEntries =
          filteredEntries.where((entry) => entry.marinaId.isEmpty);
    } else if (marinaId != null && marinaId.isNotEmpty) {
      filteredEntries = filteredEntries.where(
        (entry) => entry.marinaId == marinaId,
      );
    }

    final shouldLimitStatuses =
        hasOwnerProfile && !hasAdminProfile && !hasMarinaProfile;
    if (shouldLimitStatuses) {
      filteredEntries = filteredEntries.where((entry) {
        final isRequester =
            currentUserId.isNotEmpty &&
            entry.requestedBy.isNotEmpty &&
            entry.requestedBy == currentUserId;
        final isPendingOrInProgress =
            entry.status == 'pending' || entry.status == 'in_progress';

        return isRequester || isPendingOrInProgress;
      });
    }

    if (hasMarinaProfile) {
      final todayStart = DateTime(now.year, now.month, now.day);
      final todayEnd = todayStart.add(const Duration(days: 1));

      filteredEntries = filteredEntries.where((entry) {
        final requestedAtLocal = entry.requestedAt.toLocal();
        final isToday =
            !requestedAtLocal.isBefore(todayStart) &&
            requestedAtLocal.isBefore(todayEnd);
        if (isToday) return true;

        final isActiveStatus =
            entry.status != 'cancelled' && entry.status != 'completed';
        return isActiveStatus;
      });
    }

    final entries = filteredEntries.toList()
      ..sort((a, b) {
        int statusOrder(String status) {
          switch (status) {
            case 'in_progress':
              return 0;
            case 'pending':
              return 1;
            case 'in_water':
              return 2;
            case 'completed':
              return 3;
            case 'cancelled':
              return 4;
            default:
              return 5;
          }
        }

        final statusComparison =
            statusOrder(a.status).compareTo(statusOrder(b.status));
        if (statusComparison != 0) return statusComparison;

        final positionComparison =
            a.queuePosition.compareTo(b.queuePosition);
        if (positionComparison != 0) return positionComparison;

        final aReferenceTime = a.processedAt ?? a.requestedAt;
        final bReferenceTime = b.processedAt ?? b.requestedAt;
        return aReferenceTime.compareTo(bReferenceTime);
      });

    final inWaterCountForSelectedMarina =
        entries.where((entry) => entry.status == 'in_water').length;

    yield QueueEntriesState(
      entries: entries,
      inWaterCountForSelectedMarina: inWaterCountForSelectedMarina,
    );
  }
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

class MarinaQueueDashboardData {
  const MarinaQueueDashboardData({
    required this.entries,
    required this.marinaName,
    required this.rangeStart,
  });

  final List<LaunchQueueEntry> entries;
  final String marinaName;
  final DateTime rangeStart;
}

final marinaQueueDashboardProvider = FutureProvider<MarinaQueueDashboardData>((
  ref,
) async {
  final profiles = await ref.watch(currentUserProfilesProvider.future);
  final marinaProfile = firstMarinaProfile(profiles);
  if (marinaProfile == null ||
      marinaProfile.marinaId == null ||
      marinaProfile.marinaId!.isEmpty) {
    throw StateError('Nenhuma marina vinculada ao seu perfil.');
  }

  final repository = ref.watch(launchQueueRepositoryProvider);
  final now = DateTime.now();
  final rangeStart = DateTime(
    now.year,
    now.month,
    now.day,
  ).subtract(const Duration(days: 13));

  final entries = await repository.fetchEntries(
    marinaId: marinaProfile.marinaId,
    fromDate: rangeStart,
  );

  return MarinaQueueDashboardData(
    entries: entries,
    marinaName: marinaProfile.marinaName ?? '',
    rangeStart: rangeStart,
  );
});
