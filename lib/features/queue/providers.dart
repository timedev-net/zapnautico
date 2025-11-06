import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../boats/data/boat_repository.dart';
import '../boats/domain/boat.dart';
import 'data/launch_queue_repository.dart';
import 'domain/launch_queue_entry.dart';

const queueNoMarinaFilterValue = '__queue_no_marina__';

final queueFilterProvider = StateProvider<String?>((ref) => null);

final queueEntriesProvider =
    FutureProvider<List<LaunchQueueEntry>>((ref) async {
  final repository = ref.watch(launchQueueRepositoryProvider);
  final marinaId = ref.watch(queueFilterProvider);
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
