import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../boats/domain/boat.dart';
import '../../boats/providers.dart';
import '../../../core/supabase_providers.dart';
import '../data/launch_queue_repository.dart';
import '../domain/launch_queue_entry.dart';
import '../providers.dart';
import 'widgets/queue_marina_selector.dart';

class QueuePage extends ConsumerWidget {
  const QueuePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queueStateAsync = ref.watch(queueStateProvider);

    return queueStateAsync.when(
      data: (state) {
        if (state.audience == QueueAudience.none) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Você não possui acesso à fila de embarcações. Contate um administrador para solicitar permissão.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        if (!state.hasSelection) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Nenhuma marina disponível para exibir a fila.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        final user = ref.watch(userProvider);
        final actionInProgress = ref.watch(queueActionInProgressProvider);
        final selectedMarinaId = state.selectedMarinaId!;
        final queueEntriesAsync = ref.watch(
          launchQueueProvider(selectedMarinaId),
        );
        final queueEntries =
            queueEntriesAsync.asData?.value ?? const <LaunchQueueEntry>[];
        final isQueueLoading = queueEntriesAsync.isLoading;
        final selectionConfig = QueueSelectionConfig(
          userId: user?.id,
          audience: state.audience,
        );

        final queueError = queueEntriesAsync.asError;
        final queueContent = queueError != null
            ? _QueueErrorState(
                error: queueError.error,
                onRetry: () =>
                    ref.invalidate(launchQueueProvider(selectedMarinaId)),
              )
            : _QueueEntriesList(
                entries: queueEntries,
                audience: state.audience,
                isLoading: isQueueLoading,
                onRefresh: () async {
                  ref.invalidate(launchQueueProvider(selectedMarinaId));
                  await ref.read(launchQueueProvider(selectedMarinaId).future);
                },
              );

        Widget? actionBar;
        if (state.audience == QueueAudience.proprietario) {
          final boatsAsync = ref.watch(boatsProvider);
          actionBar = _OwnerActionBar(
            marinaId: selectedMarinaId,
            entries: queueEntries,
            boatsAsync: boatsAsync,
            isProcessing: actionInProgress,
            onRequest: (boat) async {
              final notifier = ref.read(queueActionInProgressProvider.notifier);
              if (ref.read(queueActionInProgressProvider)) {
                return;
              }
              notifier.state = true;
              final repository = ref.read(launchQueueRepositoryProvider);
              try {
                await repository.enqueueBoat(
                  boatId: boat.id,
                  marinaId: selectedMarinaId,
                );
                await repository.notifyMarinaLaunchRequest(
                  marinaId: selectedMarinaId,
                  boatId: boat.id,
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Solicitação registrada para ${boat.name}.',
                      ),
                    ),
                  );
                }
                ref.invalidate(launchQueueProvider(selectedMarinaId));
              } on PostgrestException catch (error) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(_mapPostgrestError(error))),
                  );
                }
              } catch (error) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Não foi possível registrar a solicitação. Tente novamente.',
                      ),
                    ),
                  );
                }
              } finally {
                notifier.state = false;
              }
            },
          );
        } else if (state.audience == QueueAudience.marina) {
          actionBar = _MarinaActionBar(
            isProcessing: actionInProgress,
            onAddGeneric: () async {
              final notifier = ref.read(queueActionInProgressProvider.notifier);
              if (ref.read(queueActionInProgressProvider)) {
                return;
              }
              notifier.state = true;
              final repository = ref.read(launchQueueRepositoryProvider);
              try {
                await repository.enqueueGenericEntry(
                  marinaId: selectedMarinaId,
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Embarcação genérica adicionada à fila.'),
                    ),
                  );
                }
                ref.invalidate(launchQueueProvider(selectedMarinaId));
              } on PostgrestException catch (error) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(_mapPostgrestError(error))),
                  );
                }
              } catch (error) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Falha ao adicionar a embarcação genérica. Tente novamente.',
                      ),
                    ),
                  );
                }
              } finally {
                notifier.state = false;
              }
            },
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (state.options.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: QueueMarinaSelector(
                  state: state,
                  onChanged: (value) async {
                    await ref
                        .read(
                          queueSelectionControllerProvider(
                            selectionConfig,
                          ).notifier,
                        )
                        .setSelection(value);
                    if (value != null) {
                      ref.invalidate(launchQueueProvider(value));
                    }
                  },
                ),
              ),
            Expanded(child: queueContent),
            if (actionBar != null) actionBar,
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => _QueueErrorState(
        error: error,
        onRetry: () => ref.invalidate(queueStateProvider),
      ),
    );
  }
}

class _QueueEntriesList extends StatelessWidget {
  const _QueueEntriesList({
    required this.entries,
    required this.audience,
    required this.onRefresh,
    required this.isLoading,
  });

  final List<LaunchQueueEntry> entries;
  final QueueAudience audience;
  final Future<void> Function() onRefresh;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    Widget listView;
    if (entries.isEmpty) {
      listView = RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            const SizedBox(height: 80),
            Icon(
              Icons.directions_boat_filled,
              size: 48,
              color: Theme.of(context).hintColor,
            ),
            const SizedBox(height: 12),
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'Nenhuma embarcação na fila no momento.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            if (isLoading) ...[
              const SizedBox(height: 24),
              const Center(child: CircularProgressIndicator()),
            ],
            const SizedBox(height: 80),
          ],
        ),
      );
    } else {
      listView = RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemBuilder: (context, index) {
            final entry = entries[index];
            return _QueueEntryTile(entry: entry, audience: audience);
          },
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemCount: entries.length,
        ),
      );
    }

    return Stack(
      children: [
        listView,
        if (isLoading && entries.isNotEmpty)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(minHeight: 3),
          ),
      ],
    );
  }
}

class _QueueEntryTile extends StatelessWidget {
  const _QueueEntryTile({required this.entry, required this.audience});

  final LaunchQueueEntry entry;
  final QueueAudience audience;

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final subtitleLines = <String>[];

    if (audience == QueueAudience.marina) {
      if (entry.isGenericEntry) {
        subtitleLines.add('Registro criado pela marina');
      }
      if (entry.visibleOwnerName != null &&
          entry.visibleOwnerName!.isNotEmpty) {
        subtitleLines.add('Proprietário: ${entry.visibleOwnerName}');
      }
      if (entry.requestedByName.isNotEmpty) {
        subtitleLines.add('Solicitado por: ${entry.requestedByName}');
      }
    } else {
      if (entry.isOwnBoat && entry.visibleOwnerName != null) {
        subtitleLines.add('Sua embarcação');
      } else if (entry.isGenericEntry) {
        subtitleLines.add('Embarcação genérica na fila');
      } else {
        subtitleLines.add('Outra embarcação na fila');
      }
    }

    subtitleLines.add('Entrada: ${dateFormat.format(entry.requestedAt)}');

    final showDetails = entry.userCanSeeDetails || entry.isGenericEntry;
    final title = entry.displayBoatName;
    final trailingIcon = entry.isGenericEntry
        ? Icons.directions_boat
        : Icons.directions_boat_filled;

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
          child: Text(entry.queuePosition.toString()),
        ),
        title: Text(title, style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text(
          subtitleLines.join('\n'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: Icon(
          trailingIcon,
          color: showDetails
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).hintColor,
        ),
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

class _OwnerActionBar extends StatelessWidget {
  const _OwnerActionBar({
    required this.marinaId,
    required this.entries,
    required this.boatsAsync,
    required this.isProcessing,
    required this.onRequest,
  });

  final String marinaId;
  final List<LaunchQueueEntry> entries;
  final AsyncValue<List<Boat>> boatsAsync;
  final bool isProcessing;
  final Future<void> Function(Boat boat) onRequest;

  @override
  Widget build(BuildContext context) {
    final boats = boatsAsync.asData?.value ?? const <Boat>[];
    final isLoadingBoats = boatsAsync.isLoading;

    final boatsInMarina =
        boats.where((boat) => boat.marinaId == marinaId).toList()
          ..sort((a, b) => a.name.compareTo(b.name));

    final boatsAlreadyQueued = entries
        .map((entry) => entry.boatId)
        .where((id) => id.isNotEmpty)
        .toSet();
    final availableBoats = boatsInMarina
        .where((boat) => !boatsAlreadyQueued.contains(boat.id))
        .toList();

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: FilledButton.icon(
        onPressed: isProcessing
            ? null
            : () => _handleTap(
                context,
                availableBoats: availableBoats,
                boatsInMarina: boatsInMarina,
                isLoadingBoats: isLoadingBoats,
              ),
        icon: isProcessing
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.sailing),
        label: const Text('Descer minha embarcação'),
      ),
    );
  }

  Future<void> _handleTap(
    BuildContext context, {
    required List<Boat> availableBoats,
    required List<Boat> boatsInMarina,
    required bool isLoadingBoats,
  }) async {
    if (isLoadingBoats) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Carregando suas embarcações. Tente novamente em instantes.',
          ),
        ),
      );
      return;
    }

    if (boatsInMarina.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Você ainda não possui embarcações vinculadas a esta marina.',
          ),
        ),
      );
      return;
    }

    if (availableBoats.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Suas embarcações já estão na fila desta marina.'),
        ),
      );
      return;
    }

    if (availableBoats.length == 1) {
      await onRequest(availableBoats.first);
      return;
    }

    if (!context.mounted) return;

    final selectedBoat = await showModalBottomSheet<Boat>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Escolha a embarcação que deseja descer:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              for (final boat in availableBoats)
                ListTile(
                  leading: const Icon(Icons.directions_boat_filled),
                  title: Text(boat.name),
                  onTap: () => Navigator.of(context).pop(boat),
                ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );

    if (selectedBoat != null) {
      await onRequest(selectedBoat);
    }
  }
}

class _MarinaActionBar extends StatelessWidget {
  const _MarinaActionBar({
    required this.isProcessing,
    required this.onAddGeneric,
  });

  final bool isProcessing;
  final Future<void> Function() onAddGeneric;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: FilledButton.icon(
        onPressed: isProcessing ? null : () => onAddGeneric(),
        icon: isProcessing
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add),
        label: const Text('Adicionar embarcação à fila'),
      ),
    );
  }
}

String _mapPostgrestError(PostgrestException error) {
  if (error.code == '23505') {
    return 'Esta embarcação já está na fila.';
  }
  return 'Falha ao processar a solicitação: ${error.message}';
}
