import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/preferences/shared_preferences_provider.dart';
import '../../core/supabase_providers.dart';
import '../boats/providers.dart';
import '../user_profiles/providers.dart';
import 'data/launch_queue_repository.dart';
import 'domain/launch_queue_entry.dart';

enum QueueAudience { none, marina, proprietario }

class QueueMarinaOption {
  QueueMarinaOption({required this.id, required this.name});

  final String id;
  final String name;
}

class QueueState {
  QueueState({
    required this.audience,
    required this.options,
    required this.selectedOption,
  });

  final QueueAudience audience;
  final List<QueueMarinaOption> options;
  final QueueMarinaOption? selectedOption;

  bool get hasSelection => selectedOption != null;
  String? get selectedMarinaId => selectedOption?.id;
}

class QueueSelectionConfig {
  QueueSelectionConfig({required this.userId, required this.audience});

  final String? userId;
  final QueueAudience audience;
}

class QueueSelectionController extends StateNotifier<AsyncValue<String?>> {
  QueueSelectionController({
    required Future<SharedPreferences> prefsFuture,
    required this.storageKey,
    required this.enabled,
  }) : _prefsFuture = prefsFuture,
       super(
         enabled ? const AsyncValue.loading() : const AsyncValue.data(null),
       ) {
    if (enabled && storageKey != null) {
      _load();
    }
  }

  final Future<SharedPreferences> _prefsFuture;
  final String? storageKey;
  final bool enabled;
  SharedPreferences? _prefs;

  Future<void> _load() async {
    try {
      final prefs = await _prefsFuture;
      _prefs = prefs;
      final stored = storageKey == null ? null : prefs.getString(storageKey!);
      state = AsyncValue.data(stored);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> setSelection(String? marinaId) async {
    if (!enabled || storageKey == null) {
      state = AsyncValue.data(marinaId);
      return;
    }

    final prefs = _prefs ?? await _prefsFuture;
    _prefs = prefs;

    if (marinaId == null || marinaId.isEmpty) {
      await prefs.remove(storageKey!);
    } else {
      await prefs.setString(storageKey!, marinaId);
    }
    state = AsyncValue.data(marinaId);
  }
}

String _selectionStorageKey(String? userId, QueueAudience audience) {
  if (userId == null) {
    return 'queue_last_marina_${audience.name}';
  }
  return 'queue_last_marina_${audience.name}_$userId';
}

final queueSelectionControllerProvider =
    StateNotifierProvider.family<
      QueueSelectionController,
      AsyncValue<String?>,
      QueueSelectionConfig
    >((ref, config) {
      final prefsFuture = ref.watch(sharedPreferencesProvider.future);
      final enabled =
          config.audience == QueueAudience.marina ||
          config.audience == QueueAudience.proprietario;
      final storageKey = enabled
          ? _selectionStorageKey(config.userId, config.audience)
          : null;

      return QueueSelectionController(
        prefsFuture: prefsFuture,
        storageKey: storageKey,
        enabled: enabled,
      );
    });

final queueStateProvider = FutureProvider<QueueState>((ref) async {
  final user = ref.watch(userProvider);
  final profiles = await ref.watch(currentUserProfilesProvider.future);

  final marinaProfiles = profiles
      .where(
        (profile) =>
            profile.profileSlug == 'marina' && profile.marinaId != null,
      )
      .toList();
  final hasMarinaProfile = marinaProfiles.isNotEmpty;
  final hasOwnerProfile = profiles.any(
    (profile) =>
        profile.profileSlug == 'proprietario' ||
        profile.profileSlug == 'cotista',
  );

  QueueAudience audience = QueueAudience.none;
  if (hasMarinaProfile) {
    audience = QueueAudience.marina;
  } else if (hasOwnerProfile) {
    audience = QueueAudience.proprietario;
  }

  final options = <QueueMarinaOption>[];

  if (audience == QueueAudience.marina) {
    for (final profile in marinaProfiles) {
      final id = profile.marinaId;
      if (id == null || id.isEmpty) continue;
      options.add(
        QueueMarinaOption(id: id, name: profile.marinaName ?? 'Marina'),
      );
    }
  } else if (audience == QueueAudience.proprietario) {
    try {
      final boats = await ref.watch(boatsProvider.future);
      final unique = <String, QueueMarinaOption>{};
      for (final boat in boats) {
        final id = boat.marinaId;
        if (id == null || id.isEmpty) continue;
        unique[id] = QueueMarinaOption(
          id: id,
          name: boat.marinaName ?? 'Marina',
        );
      }
      options.addAll(unique.values);
    } catch (_) {
      // Ignora erros na leitura de embarcações ao montar as opções.
    }
  }

  options.sort((a, b) => a.name.compareTo(b.name));

  final selection = ref.watch(
    queueSelectionControllerProvider(
      QueueSelectionConfig(userId: user?.id, audience: audience),
    ),
  );

  final storedId = selection.maybeWhen(
    data: (value) => value,
    orElse: () => null,
  );

  QueueMarinaOption? selectedOption;

  if (storedId != null) {
    for (final option in options) {
      if (option.id == storedId) {
        selectedOption = option;
        break;
      }
    }
  }

  selectedOption ??= options.isNotEmpty ? options.first : null;

  return QueueState(
    audience: audience,
    options: options,
    selectedOption: selectedOption,
  );
});

final launchQueueProvider =
    FutureProvider.family<List<LaunchQueueEntry>, String>((
      ref,
      marinaId,
    ) async {
      if (marinaId.isEmpty) {
        return const <LaunchQueueEntry>[];
      }

      final repository = ref.watch(launchQueueRepositoryProvider);
      return repository.fetchQueue(marinaId: marinaId);
    });

final queueActionInProgressProvider = StateProvider<bool>((ref) => false);
