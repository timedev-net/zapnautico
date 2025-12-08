import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/supabase_providers.dart';
import '../../boats/domain/boat.dart';
import '../../marinas/domain/marina.dart';
import '../../marinas/providers.dart';
import '../../user_profiles/providers.dart';
import '../data/launch_queue_repository.dart';
import '../domain/launch_queue_entry.dart';
import '../providers.dart';

final _scheduledStatusTimers = <String, Timer>{};
final _inProgressPreviousStatuses = <String, String>{};

enum _QueueStatusTab { pending, inWater, completed, cancelled }

final _queueStatusTabProvider = StateProvider.autoDispose<_QueueStatusTab>(
  (ref) => _QueueStatusTab.pending,
);

class QueueCrudPage extends ConsumerWidget {
  const QueueCrudPage({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(queueEntriesProvider);
    final marinasAsync = ref.watch(marinasProvider);
    final profilesAsync = ref.watch(currentUserProfilesProvider);
    final isAdmin = ref.watch(isAdminProvider);
    final isProcessing = ref.watch(queueOperationInProgressProvider);
    final selectedMarinaId = ref.watch(queueAppliedFilterProvider);
    final forcedMarinaId = ref.watch(queueForcedMarinaIdProvider);
    final currentUserId = ref.watch(userProvider)?.id;
    final selectedStatusTab = ref.watch(_queueStatusTabProvider);
    final hasLockedMarinaFilter = forcedMarinaId != null;
    ref.watch(queueRealtimeSyncProvider);

    final marinas = marinasAsync.asData?.value ?? const <Marina>[];
    final hasOwnerProfile = profilesAsync.maybeWhen(
      data: (profiles) => profiles.any(
        (profile) =>
            profile.profileSlug == 'proprietario' ||
            profile.profileSlug == 'cotista',
      ),
      orElse: () => false,
    );
    final hasMarinaProfile = profilesAsync.maybeWhen(
      data: (profiles) =>
          profiles.any((profile) => profile.profileSlug == 'marina'),
      orElse: () => false,
    );
    final shouldRestrictOwnerView =
        hasOwnerProfile && !isAdmin && !hasMarinaProfile;

    return Scaffold(
      appBar:
          showAppBar ? AppBar(title: const Text('Fila de embarcações')) : null,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: isProcessing ? null : () => _openForm(context, ref),
        icon: isProcessing
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add),
        label: const Text('Nova entrada'),
      ),
      body: entriesAsync.when(
        data: (state) {
          final entries = hasMarinaProfile
              ? _filterEntriesForSelectedTab(state.entries, selectedStatusTab)
              : state.entries;
          final Map<_QueueStatusTab, int> statusCounts =
              _countEntriesByTab(state.entries);
          String? selectedMarinaName;
          if (selectedMarinaId != null &&
              selectedMarinaId.isNotEmpty &&
              selectedMarinaId != queueNoMarinaFilterValue) {
            for (final marina in marinas) {
              if (marina.id == selectedMarinaId) {
                selectedMarinaName = marina.name;
                break;
              }
            }
          }
          final showInWaterCount =
              shouldRestrictOwnerView &&
              selectedMarinaId != null &&
              selectedMarinaId.isNotEmpty &&
              selectedMarinaId != queueNoMarinaFilterValue;
          final filterTopPadding = hasMarinaProfile ? 8.0 : 16.0;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (hasMarinaProfile)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: _QueueStatusSummary(
                    counts: statusCounts,
                    selectedTab: selectedStatusTab,
                    onTabSelected: (tab) => ref
                        .read(_queueStatusTabProvider.notifier)
                        .state = tab,
                  ),
                ),
              if (!hasLockedMarinaFilter)
                Padding(
                  padding:
                      EdgeInsets.fromLTRB(16, filterTopPadding, 16, 0),
                  child: _QueueMarinaFilter(
                    marinas: marinas,
                    selectedMarinaId: selectedMarinaId,
                    onChanged: (value) {
                      ref.read(queueFilterProvider.notifier).state = value;
                      ref.invalidate(queueEntriesProvider);
                    },
                  ),
                ),
              if (showInWaterCount)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    children: [
                      const Icon(Icons.water_drop_outlined, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Na água em ${selectedMarinaName ?? 'marina selecionada'}: ${state.inWaterCountForSelectedMarina}',
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: _QueueEntriesList(
                  entries: entries,
                  isLoading: entriesAsync.isLoading,
                  actionsEnabled: !isProcessing,
                  showEditDelete: isAdmin,
                  showRaiseButton: hasOwnerProfile,
                  showLaunchButton: hasLockedMarinaFilter,
                  maskOtherOwnerBoats: shouldRestrictOwnerView,
                  currentUserId: currentUserId,
                  onRefresh: () async {
                    ref.invalidate(queueEntriesProvider);
                    await ref.read(queueEntriesProvider.future);
                  },
                  onLaunch: hasLockedMarinaFilter
                      ? (entry) => _startLaunch(context, ref, entry)
                      : null,
                  onLift: hasLockedMarinaFilter
                      ? (entry) => _startLift(context, ref, entry)
                      : null,
                  onCancel: hasLockedMarinaFilter
                      ? (entry) => _cancelInProgress(context, ref, entry)
                      : null,
                  onEdit: (entry) => _openForm(context, ref, entry: entry),
                  onDelete: (entry) => _deleteEntry(context, ref, entry),
                  onRaise: hasOwnerProfile
                      ? (entry) => _raiseBoat(context, ref, entry)
                      : null,
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => _QueueErrorState(
          error: error,
          onRetry: () => ref.invalidate(queueEntriesProvider),
        ),
      ),
    );
  }

  Future<void> _openForm(
    BuildContext context,
    WidgetRef ref, {
    LaunchQueueEntry? entry,
  }) async {
    if (ref.read(queueOperationInProgressProvider)) {
      return;
    }

    final profiles = ref.read(currentUserProfilesProvider);
    final hasMarinaProfile = profiles.maybeWhen(
      data: (profiles) =>
          profiles.any((profile) => profile.profileSlug == 'marina'),
      orElse: () => false,
    );
    final forcedMarinaId = ref.read(queueForcedMarinaIdProvider);
    final lockMarinaSelection = hasMarinaProfile &&
        forcedMarinaId != null &&
        forcedMarinaId.isNotEmpty;

    List<Marina> marinas;
    try {
      marinas = await ref.read(marinasProvider.future);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Não foi possível carregar as marinas: $error'),
          ),
        );
      }
      return;
    }

    if (marinas.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cadastre uma marina antes de criar a fila.'),
          ),
        );
      }
      return;
    }

    List<Boat> boats = const [];
    try {
      boats = await ref.read(queueBoatsProvider.future);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Não foi possível carregar as embarcações: $error'),
          ),
        );
      }
      return;
    }

    if (!context.mounted) return;

    final currentFilter = ref.read(queueAppliedFilterProvider);
    final selectedFilterMarina = currentFilter == queueNoMarinaFilterValue
        ? null
        : currentFilter;
    final initialMarinaId = entry != null && entry.marinaId.isNotEmpty
        ? entry.marinaId
        : (forcedMarinaId?.isNotEmpty == true
            ? forcedMarinaId
            : selectedFilterMarina);

    final result = await showDialog<_QueueEntryFormResult>(
      context: context,
      builder: (dialogContext) {
        return _QueueEntryFormDialog(
          marinas: marinas,
          boats: boats,
          entry: entry,
          initialMarinaId: initialMarinaId,
          showMarinaSelector: !lockMarinaSelection,
          fixedMarinaId: forcedMarinaId,
        );
      },
    );

    if (result == null) {
      return;
    }

    final notifier = ref.read(queueOperationInProgressProvider.notifier);
    notifier.state = true;

    final repository = ref.read(launchQueueRepositoryProvider);

    try {
      if (entry == null) {
        await repository.createEntry(
          marinaId: result.marinaId,
          boatId: result.boatId,
          genericBoatName: result.genericBoatName,
          status: result.status,
          photos: result.photos,
        );
      } else {
        await repository.updateEntry(
          entryId: entry.id,
          marinaId: result.clearMarina ? '' : result.marinaId,
          boatId: result.clearBoat ? '' : (result.boatId ?? entry.boatId),
          status: result.status,
          processedAt: result.status == 'pending' ? null : DateTime.now(),
          clearProcessedAt: result.status == 'pending',
          genericBoatName: result.genericBoatName ?? '',
          newPhotos: result.photos,
        );
      }

      ref.invalidate(queueEntriesProvider);
      await ref.read(queueEntriesProvider.future);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              entry == null
                  ? 'Entrada adicionada à fila.'
                  : 'Entrada atualizada com sucesso.',
            ),
          ),
        );
      }
    } on ArgumentError catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível salvar a entrada: $error')),
        );
      }
    } finally {
      notifier.state = false;
    }
  }

  void _cancelScheduledTransition(String entryId) {
    final timer = _scheduledStatusTimers.remove(entryId);
    timer?.cancel();
  }

  void _registerPreviousStatus(LaunchQueueEntry entry) {
    _inProgressPreviousStatuses[entry.id] = entry.status;
  }

  Future<void> _startLaunch(
    BuildContext context,
    WidgetRef ref,
    LaunchQueueEntry entry,
  ) async {
    if (ref.read(queueOperationInProgressProvider)) {
      return;
    }

    final minutes = await _askDuration(context, title: 'Tempo para descer');
    if (minutes == null) return;

    _registerPreviousStatus(entry);
    _cancelScheduledTransition(entry.id);

    final notifier = ref.read(queueOperationInProgressProvider.notifier);
    notifier.state = true;

    final repository = ref.read(launchQueueRepositoryProvider);

    try {
      await repository.updateEntry(entryId: entry.id, status: 'in_progress');

      ref.invalidate(queueEntriesProvider);
      await ref.read(queueEntriesProvider.future);

      unawaited(_scheduleMoveToInWater(ref, entry.id, minutes));

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '"${entry.displayBoatName}" em andamento por $minutes min.',
            ),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Não foi possível descer a embarcação: $error'),
          ),
        );
      }
    } finally {
      notifier.state = false;
    }
  }

  Future<void> _startLift(
    BuildContext context,
    WidgetRef ref,
    LaunchQueueEntry entry,
  ) async {
    if (ref.read(queueOperationInProgressProvider)) {
      return;
    }

    final minutes = await _askDuration(context, title: 'Tempo para subir');
    if (minutes == null) return;

    _registerPreviousStatus(entry);
    _cancelScheduledTransition(entry.id);

    final notifier = ref.read(queueOperationInProgressProvider.notifier);
    notifier.state = true;

    final repository = ref.read(launchQueueRepositoryProvider);

    try {
      await repository.updateEntry(entryId: entry.id, status: 'in_progress');

      ref.invalidate(queueEntriesProvider);
      await ref.read(queueEntriesProvider.future);

      unawaited(_scheduleMoveToCompleted(ref, entry.id, minutes));

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '"${entry.displayBoatName}" subindo por $minutes min.',
            ),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Não foi possível subir a embarcação: $error'),
          ),
        );
      }
    } finally {
      notifier.state = false;
    }
  }

  Future<void> _cancelInProgress(
    BuildContext context,
    WidgetRef ref,
    LaunchQueueEntry entry,
  ) async {
    if (ref.read(queueOperationInProgressProvider)) {
      return;
    }

    final previousStatus = _inProgressPreviousStatuses[entry.id] == 'in_water'
        ? 'in_water'
        : 'pending';

    final notifier = ref.read(queueOperationInProgressProvider.notifier);
    notifier.state = true;

    final repository = ref.read(launchQueueRepositoryProvider);
    _cancelScheduledTransition(entry.id);

    try {
      await repository.updateEntry(
        entryId: entry.id,
        status: previousStatus,
        clearProcessedAt: previousStatus == 'pending',
      );

      ref.invalidate(queueEntriesProvider);
      await ref.read(queueEntriesProvider.future);

      _inProgressPreviousStatuses.remove(entry.id);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Ação cancelada. Status retornou para "${_translateStatus(previousStatus)}".',
            ),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível cancelar a ação: $error')),
        );
      }
    } finally {
      notifier.state = false;
    }
  }

  Future<int?> _askDuration(
    BuildContext context, {
    required String title,
  }) async {
    final formKey = GlobalKey<FormState>();
    final controller = TextEditingController(text: '5');

    return showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Minutos',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            validator: (value) {
              final parsed = int.tryParse(value ?? '');
              if (parsed == null || parsed <= 0) {
                return 'Informe um tempo válido em minutos.';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              final parsed = int.parse(controller.text);
              Navigator.of(dialogContext).pop(parsed);
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
  }

  Future<void> _scheduleMoveToInWater(
    WidgetRef ref,
    String entryId,
    int minutes,
  ) async {
    _cancelScheduledTransition(entryId);
    late Timer timer;
    timer = Timer(Duration(minutes: minutes), () async {
      if (_scheduledStatusTimers[entryId] != timer) return;

      final repository = ref.read(launchQueueRepositoryProvider);
      try {
        await repository.updateEntry(
          entryId: entryId,
          status: 'in_water',
          processedAt: DateTime.now(),
        );
        ref.invalidate(queueEntriesProvider);
      } catch (_) {
        // Best-effort; user can refresh manually if update fails.
      } finally {
        _scheduledStatusTimers.remove(entryId);
        _inProgressPreviousStatuses.remove(entryId);
      }
    });

    _scheduledStatusTimers[entryId] = timer;
  }

  Future<void> _scheduleMoveToCompleted(
    WidgetRef ref,
    String entryId,
    int minutes,
  ) async {
    _cancelScheduledTransition(entryId);
    late Timer timer;
    timer = Timer(Duration(minutes: minutes), () async {
      if (_scheduledStatusTimers[entryId] != timer) return;

      final repository = ref.read(launchQueueRepositoryProvider);
      try {
        await repository.updateEntry(
          entryId: entryId,
          status: 'completed',
          processedAt: DateTime.now(),
        );
        ref.invalidate(queueEntriesProvider);
      } catch (_) {
        // Best-effort; user can refresh manually if update fails.
      } finally {
        _scheduledStatusTimers.remove(entryId);
        _inProgressPreviousStatuses.remove(entryId);
      }
    });

    _scheduledStatusTimers[entryId] = timer;
  }

  Future<void> _deleteEntry(
    BuildContext context,
    WidgetRef ref,
    LaunchQueueEntry entry,
  ) async {
    if (ref.read(queueOperationInProgressProvider)) {
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Remover entrada'),
          content: Text(
            'Tem certeza de que deseja remover "${entry.displayBoatName}" da fila?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Remover'),
            ),
          ],
        );
      },
    );

    if (confirm != true) {
      return;
    }

    final notifier = ref.read(queueOperationInProgressProvider.notifier);
    notifier.state = true;

    final repository = ref.read(launchQueueRepositoryProvider);

    try {
      await repository.cancelRequest(entry.id);
      ref.invalidate(queueEntriesProvider);
      await ref.read(queueEntriesProvider.future);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Entrada removida da fila.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível remover a entrada: $error')),
        );
      }
    } finally {
      notifier.state = false;
    }
  }

  Future<void> _raiseBoat(
    BuildContext context,
    WidgetRef ref,
    LaunchQueueEntry entry,
  ) async {
    if (ref.read(queueOperationInProgressProvider)) {
      return;
    }

    final notifier = ref.read(queueOperationInProgressProvider.notifier);
    notifier.state = true;

    final repository = ref.read(launchQueueRepositoryProvider);

    try {
      await repository.updateEntry(
        entryId: entry.id,
        status: 'completed',
        processedAt: DateTime.now(),
      );
      ref.invalidate(queueEntriesProvider);
      await ref.read(queueEntriesProvider.future);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Pedido de subida registrado para "${entry.displayBoatName}".',
            ),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Não foi possível registrar a subida: $error'),
          ),
        );
      }
    } finally {
      notifier.state = false;
    }
  }
}

List<LaunchQueueEntry> _filterEntriesForSelectedTab(
  List<LaunchQueueEntry> entries,
  _QueueStatusTab selectedTab,
) {
  switch (selectedTab) {
    case _QueueStatusTab.pending:
      return entries
          .where(
            (entry) =>
                entry.status == 'pending' || entry.status == 'in_progress',
          )
          .toList();
    case _QueueStatusTab.inWater:
      return entries.where((entry) => entry.status == 'in_water').toList();
    case _QueueStatusTab.completed:
      return entries.where((entry) => entry.status == 'completed').toList();
    case _QueueStatusTab.cancelled:
      return entries.where((entry) => entry.status == 'cancelled').toList();
  }
}

Map<_QueueStatusTab, int> _countEntriesByTab(
  List<LaunchQueueEntry> entries,
) {
  final counts = <_QueueStatusTab, int>{
    _QueueStatusTab.pending: 0,
    _QueueStatusTab.inWater: 0,
    _QueueStatusTab.completed: 0,
    _QueueStatusTab.cancelled: 0,
  };

  for (final entry in entries) {
    switch (entry.status) {
      case 'pending':
      case 'in_progress':
        counts[_QueueStatusTab.pending] =
            counts[_QueueStatusTab.pending]! + 1;
        break;
      case 'in_water':
        counts[_QueueStatusTab.inWater] =
            counts[_QueueStatusTab.inWater]! + 1;
        break;
      case 'completed':
        counts[_QueueStatusTab.completed] =
            counts[_QueueStatusTab.completed]! + 1;
        break;
      case 'cancelled':
        counts[_QueueStatusTab.cancelled] =
            counts[_QueueStatusTab.cancelled]! + 1;
        break;
    }
  }

  return counts;
}

class _QueueStatusSummary extends StatelessWidget {
  const _QueueStatusSummary({
    required this.counts,
    required this.selectedTab,
    required this.onTabSelected,
  });

  final Map<_QueueStatusTab, int> counts;
  final _QueueStatusTab selectedTab;
  final ValueChanged<_QueueStatusTab> onTabSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          children: _statusSummaryItems
              .map(
                (item) => _StatusCountChip(
                  icon: item.icon,
                  label: item.label,
                  count: counts[item.tab] ?? 0,
                  selected: selectedTab == item.tab,
                  onPressed: () => onTabSelected(item.tab),
                  colorScheme: colorScheme,
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _StatusCountChip extends StatelessWidget {
  const _StatusCountChip({
    required this.icon,
    required this.label,
    required this.count,
    required this.selected,
    required this.onPressed,
    required this.colorScheme,
  });

  final IconData icon;
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onPressed;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final background =
        selected ? colorScheme.primaryContainer : colorScheme.surfaceVariant;
    final foreground = selected
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant;

    return FilterChip(
      selected: selected,
      showCheckmark: false,
      avatar: Icon(icon, size: 18, color: foreground),
      label: Text('$label: $count'),
      onSelected: (_) => onPressed(),
      backgroundColor: background,
      selectedColor: background,
      side: BorderSide(
        color: selected ? colorScheme.primary : colorScheme.outlineVariant,
      ),
      labelStyle: Theme.of(context)
          .textTheme
          .bodyMedium
          ?.copyWith(color: foreground, fontWeight: FontWeight.w600),
    );
  }
}

class _StatusSummaryItem {
  const _StatusSummaryItem({
    required this.tab,
    required this.label,
    required this.icon,
  });

  final _QueueStatusTab tab;
  final String label;
  final IconData icon;
}

const _statusSummaryItems = <_StatusSummaryItem>[
  _StatusSummaryItem(
    tab: _QueueStatusTab.pending,
    label: 'Pendentes',
    icon: Icons.pending_actions_outlined,
  ),
  _StatusSummaryItem(
    tab: _QueueStatusTab.inWater,
    label: 'Na água',
    icon: Icons.water_drop_outlined,
  ),
  _StatusSummaryItem(
    tab: _QueueStatusTab.completed,
    label: 'Concluídos',
    icon: Icons.check_circle_outline,
  ),
  _StatusSummaryItem(
    tab: _QueueStatusTab.cancelled,
    label: 'Cancelados',
    icon: Icons.cancel_outlined,
  ),
];

class _QueueEntriesList extends StatelessWidget {
  const _QueueEntriesList({
    required this.entries,
    required this.isLoading,
    required this.actionsEnabled,
    required this.showEditDelete,
    required this.showRaiseButton,
    required this.showLaunchButton,
    required this.maskOtherOwnerBoats,
    required this.currentUserId,
    required this.onRefresh,
    required this.onEdit,
    required this.onDelete,
    this.onLaunch,
    this.onRaise,
    this.onLift,
    this.onCancel,
  });

  final List<LaunchQueueEntry> entries;
  final bool isLoading;
  final bool actionsEnabled;
  final bool showEditDelete;
  final bool showRaiseButton;
  final bool showLaunchButton;
  final bool maskOtherOwnerBoats;
  final String? currentUserId;
  final Future<void> Function() onRefresh;
  final void Function(LaunchQueueEntry entry) onEdit;
  final void Function(LaunchQueueEntry entry) onDelete;
  final void Function(LaunchQueueEntry entry)? onLaunch;
  final void Function(LaunchQueueEntry entry)? onRaise;
  final void Function(LaunchQueueEntry entry)? onLift;
  final void Function(LaunchQueueEntry entry)? onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (entries.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 80),
            Icon(
              Icons.directions_boat,
              size: 56,
              color: Theme.of(context).hintColor,
            ),
            const SizedBox(height: 12),
            const Text(
              'Nenhuma entrada encontrada na fila.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (isLoading) const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 80),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        itemBuilder: (context, index) {
          final entry = entries[index];
          final isDifferentUserRequest =
              currentUserId == null ||
              currentUserId!.isEmpty ||
              entry.requestedBy != currentUserId;
          final isMasked = maskOtherOwnerBoats && isDifferentUserRequest;
          final subtitleLines = _buildSubtitleLines(entry, masked: isMasked);
          final cardColor = _cardColor(entry.status, theme);
          final trailingChildren = <Widget>[];

          if (showRaiseButton &&
              onRaise != null &&
              entry.isOwnBoat &&
              entry.status == 'in_water') {
            trailingChildren.add(
              FilledButton.tonal(
                onPressed: actionsEnabled ? () => onRaise!(entry) : null,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Subir'),
              ),
            );
          }

          if (showLaunchButton) {
            if (entry.status == 'in_progress') {
              if (onCancel != null) {
                trailingChildren.add(
                  FilledButton.tonal(
                    onPressed: actionsEnabled ? () => onCancel!(entry) : null,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Cancelar'),
                  ),
                );
              }
            } else {
              final isInWater = entry.status == 'in_water';
              final action = isInWater ? onLift : onLaunch;
              if (action != null) {
                trailingChildren.add(
                  FilledButton.tonal(
                    onPressed: actionsEnabled ? () => action(entry) : null,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: Text(isInWater ? 'Subir' : 'Descer'),
                  ),
                );
              }
            }
          }

          if (showEditDelete) {
            trailingChildren.addAll([
              IconButton(
                tooltip: 'Editar entrada',
                icon: const Icon(Icons.edit),
                onPressed: actionsEnabled ? () => onEdit(entry) : null,
              ),
              IconButton(
                tooltip: 'Remover entrada',
                icon: const Icon(Icons.delete),
                onPressed: actionsEnabled ? () => onDelete(entry) : null,
              ),
            ]);
          }

          return Card(
            color: cardColor,
            child: ListTile(
              leading: _QueueEntryAvatar(entry: entry, forceBoatIcon: isMasked),
              title: Text(
                isMasked ? 'Embarcação' : entry.displayBoatName,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              subtitle: Text(
                subtitleLines.join('\n'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              trailing: trailingChildren.isEmpty
                  ? null
                  : Wrap(spacing: 8, children: trailingChildren),
            ),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemCount: entries.length,
      ),
    );
  }

  List<String> _buildSubtitleLines(
    LaunchQueueEntry entry, {
    required bool masked,
  }) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    if (masked) {
      return [
        'Status: ${_translateStatus(entry.status)}',
        'Entrada: ${dateFormat.format(entry.requestedAt)}',
      ];
    }

    final lines = <String>[
      'Marina: ${entry.displayMarinaName}',
      'Status: ${_translateStatus(entry.status)}',
      'Entrada: ${dateFormat.format(entry.requestedAt)}',
    ];

    if (entry.isGenericEntry) {
      lines.add('Tipo: Entrada genérica');
    }

    if (entry.genericBoatName != null &&
        entry.genericBoatName!.trim().isNotEmpty) {
      lines.add('Descrição: ${entry.genericBoatName}');
    }

    if (entry.requestedByName.isNotEmpty) {
      lines.add('Solicitado por: ${entry.requestedByName}');
    } else if (entry.requestedByEmail != null &&
        entry.requestedByEmail!.isNotEmpty) {
      lines.add('Solicitado por: ${entry.requestedByEmail}');
    }

    if (entry.visibleOwnerName != null &&
        entry.visibleOwnerName!.isNotEmpty &&
        entry.visibleOwnerName != entry.requestedByName) {
      lines.add('Proprietário: ${entry.visibleOwnerName}');
    }

    return lines;
  }

  Color? _cardColor(String status, ThemeData theme) {
    switch (status) {
      case 'in_progress':
        return Colors.orange.shade50;
      case 'in_water':
        return Colors.lightBlue.shade50;
      default:
        return null;
    }
  }
}

class _QueueEntryAvatar extends StatelessWidget {
  const _QueueEntryAvatar({required this.entry, this.forceBoatIcon = false});

  final LaunchQueueEntry entry;
  final bool forceBoatIcon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasPhoto = !forceBoatIcon && entry.hasBoatPhoto;
    final radius = 26.0;
    final placeholderColor = theme.colorScheme.primaryContainer;
    final placeholderForeground = theme.colorScheme.onPrimaryContainer;

    Widget avatarContent;

    if (forceBoatIcon) {
      avatarContent = CircleAvatar(
        radius: radius,
        backgroundColor: placeholderColor,
        foregroundColor: placeholderForeground,
        child: const Icon(Icons.directions_boat_filled),
      );
    } else if (hasPhoto) {
      avatarContent = CircleAvatar(
        radius: radius,
        backgroundImage: NetworkImage(entry.boatPhotoUrl!),
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
      );
    } else if (entry.isGenericEntry) {
      avatarContent = CircleAvatar(
        radius: radius,
        backgroundColor: placeholderColor,
        foregroundColor: placeholderForeground,
        child: const Icon(Icons.directions_boat_filled),
      );
    } else {
      final title = entry.displayBoatName.trim();
      final initials = title.isNotEmpty ? title[0].toUpperCase() : '?';
      avatarContent = CircleAvatar(
        radius: radius,
        backgroundColor: placeholderColor,
        foregroundColor: placeholderForeground,
        child: Text(initials),
      );
    }

    return SizedBox(
      width: radius * 2.4,
      height: radius * 2.4,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: avatarContent),
          if (entry.status == 'in_progress')
            Positioned(
              top: -2,
              right: -2,
              child: CircleAvatar(
                radius: 13,
                backgroundColor: theme.colorScheme.secondaryContainer,
                foregroundColor: theme.colorScheme.onSecondaryContainer,
                child: Icon(
                  _inProgressPreviousStatuses[entry.id] == 'in_water'
                      ? Icons.arrow_upward
                      : Icons.arrow_downward,
                  size: 16,
                ),
              ),
            ),
          if (entry.status != 'in_water')
            Positioned(
              bottom: -2,
              right: -2,
              child: CircleAvatar(
                radius: 14,
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
                child: Text(
                  entry.queuePosition.toString(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _QueueErrorState extends StatelessWidget {
  const _QueueErrorState({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
            const SizedBox(height: 12),
            Text(
              'Ocorreu um erro ao carregar a fila.\n${error.toString()}',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}

class _QueueMarinaFilter extends StatelessWidget {
  const _QueueMarinaFilter({
    required this.marinas,
    required this.selectedMarinaId,
    required this.onChanged,
  });

  final List<Marina> marinas;
  final String? selectedMarinaId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final hasSelectedMarina =
        selectedMarinaId != null &&
        (selectedMarinaId == queueNoMarinaFilterValue ||
            marinas.any((marina) => marina.id == selectedMarinaId));
    final effectiveSelected = hasSelectedMarina ? selectedMarinaId : null;

    return DropdownButtonFormField<String?>(
      initialValue: effectiveSelected,
      decoration: const InputDecoration(
        labelText: 'Filtrar por marina',
        border: OutlineInputBorder(),
      ),
      hint: const Text('Selecione uma opção'),
      isExpanded: true,
      items: [
        const DropdownMenuItem<String?>(
          value: queueNoMarinaFilterValue,
          child: Text('Sem marina'),
        ),
        ...marinas.map(
          (marina) => DropdownMenuItem<String?>(
            value: marina.id,
            child: Text(marina.name),
          ),
        ),
      ],
      onChanged: onChanged,
    );
  }
}

class _QueueEntryFormDialog extends StatefulWidget {
  const _QueueEntryFormDialog({
    required this.marinas,
    required this.boats,
    this.entry,
    this.initialMarinaId,
    required this.showMarinaSelector,
    this.fixedMarinaId,
  });

  final List<Marina> marinas;
  final List<Boat> boats;
  final LaunchQueueEntry? entry;
  final String? initialMarinaId;
  final bool showMarinaSelector;
  final String? fixedMarinaId;

  @override
  State<_QueueEntryFormDialog> createState() => _QueueEntryFormDialogState();
}

class _QueueEntryFormDialogState extends State<_QueueEntryFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _boatFieldKey = GlobalKey<FormFieldState<String?>>();

  late String? _selectedMarinaId;
  late String? _selectedBoatId;
  late String _selectedStatus;
  late TextEditingController _descriptionController;
  final List<XFile> _selectedPhotos = [];

  @override
  void initState() {
    super.initState();

    final entryMarinaId = widget.entry?.marinaId ?? '';
    if (entryMarinaId.isNotEmpty) {
      _selectedMarinaId = entryMarinaId;
    } else if (!widget.showMarinaSelector &&
        widget.fixedMarinaId != null &&
        widget.fixedMarinaId!.isNotEmpty) {
      _selectedMarinaId = widget.fixedMarinaId;
    } else {
      final initial = widget.initialMarinaId ?? '';
      _selectedMarinaId = initial.isNotEmpty ? initial : null;
    }

    final boatId = widget.entry?.boatId;
    _selectedBoatId = (boatId != null && boatId.isNotEmpty) ? boatId : null;

    _selectedStatus = widget.entry?.status ?? _statusOptions.first.value;
    if (!_statusOptions.any((option) => option.value == _selectedStatus)) {
      _selectedStatus = _statusOptions.first.value;
    }

    _descriptionController = TextEditingController(
      text: widget.entry?.genericBoatName ?? '',
    );
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final boats = _boatsForSelectedMarina();

    return AlertDialog(
      title: Text(widget.entry == null ? 'Nova entrada' : 'Editar entrada'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.showMarinaSelector) ...[
                DropdownButtonFormField<String?>(
                  initialValue: _selectedMarinaId,
                  decoration: const InputDecoration(
                    labelText: 'Marina',
                    border: OutlineInputBorder(),
                  ),
                  hint: const Text('Selecione uma marina'),
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Sem marina vinculada'),
                    ),
                    ...widget.marinas.map(
                      (marina) => DropdownMenuItem<String?>(
                        value: marina.id,
                        child: Text(marina.name),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedMarinaId = value;
                      if (!_boatBelongsToSelectedMarina(_selectedBoatId)) {
                        _selectedBoatId = null;
                        _boatFieldKey.currentState?.didChange(null);
                      }
                    });
                    _formKey.currentState?.validate();
                  },
                ),
                const SizedBox(height: 12),
              ],
              DropdownButtonFormField<String?>(
                key: _boatFieldKey,
                initialValue: _selectedBoatId,
                decoration: const InputDecoration(
                  labelText: 'Embarcação',
                  border: OutlineInputBorder(),
                ),
                hint: const Text('Selecione uma embarcação'),
                isExpanded: true,
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Sem embarcação vinculada'),
                  ),
                  ...boats.map(
                    (boat) => DropdownMenuItem<String?>(
                      value: boat.id,
                      child: Text(boat.name),
                    ),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedBoatId = value;
                  });
                  _formKey.currentState?.validate();
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _selectedStatus,
                decoration: const InputDecoration(
                  labelText: 'Status',
                  border: OutlineInputBorder(),
                ),
                isExpanded: true,
                items: _statusOptions
                    .map(
                      (option) => DropdownMenuItem<String>(
                        value: option.value,
                        child: Text(option.label),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _selectedStatus = value;
                  });
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Descrição',
                  helperText:
                      'Obrigatório quando nenhuma embarcação estiver selecionada.',
                  border: OutlineInputBorder(),
                ),
                maxLines: null,
                validator: (value) {
                  final hasBoat =
                      _selectedBoatId != null && _selectedBoatId!.isNotEmpty;
                  if (!hasBoat && (value == null || value.trim().isEmpty)) {
                    return 'Informe uma descrição ou selecione uma embarcação.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              _QueueEntryPhotosField(
                photos: _selectedPhotos,
                onAddFromGallery: _pickImagesFromGallery,
                onAddFromCamera: _pickImageFromCamera,
                onRemove: _removePhotoAt,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.entry == null ? 'Adicionar' : 'Salvar'),
        ),
      ],
    );
  }

  List<Boat> _boatsForSelectedMarina() {
    if (_selectedMarinaId == null || _selectedMarinaId!.isEmpty) {
      final all = List<Boat>.from(widget.boats)
        ..sort((a, b) => a.name.compareTo(b.name));
      return all;
    }
    final filtered =
        widget.boats
            .where((boat) => boat.marinaId == _selectedMarinaId)
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    return filtered;
  }

  bool _boatBelongsToSelectedMarina(String? boatId) {
    if (boatId == null || boatId.isEmpty) {
      return true;
    }
    if (_selectedMarinaId == null || _selectedMarinaId!.isEmpty) {
      return widget.boats.any((boat) => boat.id == boatId);
    }
    return widget.boats.any(
      (boat) => boat.id == boatId && boat.marinaId == _selectedMarinaId,
    );
  }

  Future<void> _pickImagesFromGallery() async {
    final remainingSlots = 5 - _selectedPhotos.length;
    if (remainingSlots <= 0) {
      _showMessage('É possível anexar no máximo 5 fotos.');
      return;
    }

    try {
      final picker = ImagePicker();
      final files = await picker.pickMultiImage(
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (files.isEmpty) return;
      if (!mounted) return;

      final toAdd = files.take(remainingSlots).toList();
      setState(() => _selectedPhotos.addAll(toAdd));

      if (files.length > remainingSlots) {
        _showMessage('Limite de 5 fotos atingido. Apenas as primeiras foram adicionadas.');
      }
    } catch (error) {
      _showMessage('Erro ao selecionar fotos: $error');
    }
  }

  Future<void> _pickImageFromCamera() async {
    if (_selectedPhotos.length >= 5) {
      _showMessage('É possível anexar no máximo 5 fotos.');
      return;
    }

    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (file == null) return;
      if (!mounted) return;

      setState(() => _selectedPhotos.add(file));
    } catch (error) {
      _showMessage('Erro ao tirar foto: $error');
    }
  }

  void _removePhotoAt(int index) {
    if (index < 0 || index >= _selectedPhotos.length) return;
    setState(() {
      _selectedPhotos.removeAt(index);
    });
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final description = _descriptionController.text.trim();
    final hasBoat = _selectedBoatId != null && _selectedBoatId!.isNotEmpty;
    final hasMarina =
        _selectedMarinaId != null && _selectedMarinaId!.isNotEmpty;
    if (!hasBoat && description.isEmpty) {
      _formKey.currentState!.validate();
      return;
    }

    final result = _QueueEntryFormResult(
      marinaId: hasMarina ? _selectedMarinaId : null,
      boatId: hasBoat ? _selectedBoatId : null,
      status: _selectedStatus,
      genericBoatName: description.isNotEmpty ? description : null,
      clearMarina: !hasMarina,
      clearBoat: !hasBoat,
      photos: List<XFile>.unmodifiable(_selectedPhotos),
    );

    Navigator.of(context).pop(result);
  }
}

class _QueueEntryPhotosField extends StatelessWidget {
  const _QueueEntryPhotosField({
    required this.photos,
    required this.onAddFromGallery,
    required this.onAddFromCamera,
    required this.onRemove,
  });

  final List<XFile> photos;
  final VoidCallback onAddFromGallery;
  final VoidCallback onAddFromCamera;
  final void Function(int index) onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Selecionar fotos'),
                onPressed: onAddFromGallery,
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              onPressed: onAddFromCamera,
              icon: const Icon(Icons.photo_camera_outlined),
              tooltip: 'Tirar foto',
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (photos.isEmpty)
          Text(
            'Anexe até 5 fotos (opcional).',
            style: theme.textTheme.bodySmall,
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(
              photos.length,
              (index) {
                final file = photos[index];
                return Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: FutureBuilder<Uint8List>(
                        future: file.readAsBytes(),
                        builder: (context, snapshot) {
                          if (snapshot.hasData) {
                            return Image.memory(
                              snapshot.data!,
                              width: 88,
                              height: 88,
                              fit: BoxFit.cover,
                            );
                          }
                          return Container(
                            width: 88,
                            height: 88,
                            color: theme.colorScheme.surfaceVariant,
                            alignment: Alignment.center,
                            child: const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          );
                        },
                      ),
                    ),
                    Positioned(
                      top: -8,
                      right: -8,
                      child: IconButton(
                        iconSize: 20,
                        visualDensity: VisualDensity.compact,
                        style: IconButton.styleFrom(
                          backgroundColor: theme.colorScheme.surface,
                        ),
                        icon: const Icon(Icons.close),
                        onPressed: () => onRemove(index),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
      ],
    );
  }
}

class _QueueEntryFormResult {
  _QueueEntryFormResult({
    this.marinaId,
    required this.status,
    this.boatId,
    this.genericBoatName,
    required this.clearMarina,
    required this.clearBoat,
    required this.photos,
  });

  final String? marinaId;
  final String status;
  final String? boatId;
  final String? genericBoatName;
  final bool clearMarina;
  final bool clearBoat;
  final List<XFile> photos;
}

class _QueueStatusOption {
  const _QueueStatusOption(this.value, this.label);

  final String value;
  final String label;
}

const _statusOptions = <_QueueStatusOption>[
  _QueueStatusOption('pending', 'Pendente'),
  _QueueStatusOption('in_progress', 'Em andamento'),
  _QueueStatusOption('in_water', 'Na água'),
  _QueueStatusOption('completed', 'Concluída'),
  _QueueStatusOption('cancelled', 'Cancelada'),
];

String _translateStatus(String status) {
  for (final option in _statusOptions) {
    if (option.value == status) return option.label;
  }
  return status;
}
