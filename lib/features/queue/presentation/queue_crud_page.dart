import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_providers.dart';
import '../data/launch_queue_repository.dart';
import '../domain/launch_queue_entry.dart';
import '../providers.dart';
import 'widgets/queue_marina_selector.dart';

class QueueCrudPage extends ConsumerWidget {
  const QueueCrudPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queueStateAsync = ref.watch(queueStateProvider);

    return queueStateAsync.when(
      data: (state) {
        if (state.audience == QueueAudience.none) {
          return Scaffold(
            appBar: AppBar(title: const Text('Fila de embarcações')),
            body: const _QueueCrudInfoMessage(
              message:
                  'Você não possui acesso às filas de embarcações neste momento.',
            ),
          );
        }

        final user = ref.watch(userProvider);
        final selectionConfig = QueueSelectionConfig(
          userId: user?.id,
          audience: state.audience,
        );

        Widget bodyContent;
        String? selectedMarinaId;

        if (!state.hasSelection) {
          bodyContent = const _QueueCrudInfoMessage(
            message: 'Nenhuma marina disponível para exibir a fila.',
          );
        } else {
          selectedMarinaId = state.selectedMarinaId!;
          final queueEntriesAsync = ref.watch(
            launchQueueProvider(selectedMarinaId),
          );

          bodyContent = queueEntriesAsync.when(
            data: (entries) => _QueueCrudList(
              entries: entries,
              isLoading: queueEntriesAsync.isLoading,
              canManageQueue: state.audience == QueueAudience.marina,
              currentUserId: user?.id,
              onRefresh: () async {
                ref.invalidate(launchQueueProvider(selectedMarinaId!));
                await ref.read(launchQueueProvider(selectedMarinaId).future);
              },
              onMarkCompleted: (entry) => _markEntryStatus(
                context,
                ref,
                entry: entry,
                status: 'completed',
              ),
              onMarkCancelled: (entry) => _markEntryStatus(
                context,
                ref,
                entry: entry,
                status: 'cancelled',
              ),
              onEditGenericName: (entry) =>
                  _editGenericEntryName(context, ref, entry),
              onDelete: (entry) => _deleteEntry(context, ref, entry),
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) => _QueueCrudErrorState(
              error: error,
              onRetry: () {
                if (selectedMarinaId != null) {
                  ref.invalidate(launchQueueProvider(selectedMarinaId));
                }
              },
            ),
          );
        }

        final actionInProgress = ref.watch(queueActionInProgressProvider);

        return Scaffold(
          appBar: AppBar(title: const Text('Fila de embarcações')),
          body: Column(
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
              Expanded(child: bodyContent),
            ],
          ),
          floatingActionButton:
              selectedMarinaId != null && state.audience == QueueAudience.marina
              ? FloatingActionButton.extended(
                  onPressed: actionInProgress
                      ? null
                      : () => _addGenericEntry(
                          context,
                          ref,
                          marinaId: selectedMarinaId!,
                        ),
                  icon: actionInProgress
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add),
                  label: const Text('Adicionar entrada genérica'),
                )
              : null,
        );
      },
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Fila de embarcações')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, stackTrace) => Scaffold(
        appBar: AppBar(title: const Text('Fila de embarcações')),
        body: _QueueCrudErrorState(
          error: error,
          onRetry: () => ref.invalidate(queueStateProvider),
        ),
      ),
    );
  }

  Future<void> _addGenericEntry(
    BuildContext context,
    WidgetRef ref, {
    required String marinaId,
  }) async {
    final label = await _promptGenericEntryLabel(context);
    if (label == null) {
      return;
    }

    if (ref.read(queueActionInProgressProvider)) {
      return;
    }

    final notifier = ref.read(queueActionInProgressProvider.notifier);
    notifier.state = true;

    final repository = ref.read(launchQueueRepositoryProvider);

    try {
      await repository.enqueueGenericEntry(
        marinaId: marinaId,
        label: label.trim().isEmpty ? null : label,
      );
      ref.invalidate(launchQueueProvider(marinaId));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Entrada genérica adicionada à fila.')),
        );
      }
    } on PostgrestException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_mapPostgrestError(error))));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Não foi possível adicionar a entrada: $error'),
          ),
        );
      }
    } finally {
      notifier.state = false;
    }
  }

  Future<void> _markEntryStatus(
    BuildContext context,
    WidgetRef ref, {
    required LaunchQueueEntry entry,
    required String status,
  }) async {
    if (ref.read(queueActionInProgressProvider)) {
      return;
    }

    final notifier = ref.read(queueActionInProgressProvider.notifier);
    notifier.state = true;

    final repository = ref.read(launchQueueRepositoryProvider);

    try {
      await repository.updateEntry(
        entryId: entry.id,
        status: status,
        processedAt: DateTime.now(),
      );
      ref.invalidate(launchQueueProvider(entry.marinaId));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              status == 'completed'
                  ? 'Entrada marcada como concluída.'
                  : 'Entrada marcada como cancelada.',
            ),
          ),
        );
      }
    } on PostgrestException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_mapPostgrestError(error))));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Não foi possível atualizar a entrada: $error'),
          ),
        );
      }
    } finally {
      notifier.state = false;
    }
  }

  Future<void> _editGenericEntryName(
    BuildContext context,
    WidgetRef ref,
    LaunchQueueEntry entry,
  ) async {
    if (!entry.isGenericEntry) {
      return;
    }

    final newLabel = await _promptGenericEntryEdit(
      context,
      initialValue: entry.genericBoatName ?? '',
    );

    if (newLabel == null || newLabel.trim().isEmpty) {
      return;
    }

    if (ref.read(queueActionInProgressProvider)) {
      return;
    }

    final notifier = ref.read(queueActionInProgressProvider.notifier);
    notifier.state = true;

    final repository = ref.read(launchQueueRepositoryProvider);

    try {
      await repository.updateEntry(
        entryId: entry.id,
        genericBoatName: newLabel.trim(),
      );
      ref.invalidate(launchQueueProvider(entry.marinaId));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Descrição atualizada com sucesso.')),
        );
      }
    } on PostgrestException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_mapPostgrestError(error))));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Não foi possível atualizar a entrada: $error'),
          ),
        );
      }
    } finally {
      notifier.state = false;
    }
  }

  Future<void> _deleteEntry(
    BuildContext context,
    WidgetRef ref,
    LaunchQueueEntry entry,
  ) async {
    final confirm = await _confirmDeletion(context, entry);
    if (confirm != true) {
      return;
    }

    if (ref.read(queueActionInProgressProvider)) {
      return;
    }

    final notifier = ref.read(queueActionInProgressProvider.notifier);
    notifier.state = true;
    final repository = ref.read(launchQueueRepositoryProvider);

    try {
      await repository.cancelRequest(entry.id);
      ref.invalidate(launchQueueProvider(entry.marinaId));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Entrada removida da fila.')),
        );
      }
    } on PostgrestException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_mapPostgrestError(error))));
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
}

class _QueueCrudList extends StatelessWidget {
  const _QueueCrudList({
    required this.entries,
    required this.isLoading,
    required this.canManageQueue,
    required this.currentUserId,
    required this.onRefresh,
    required this.onMarkCompleted,
    required this.onMarkCancelled,
    required this.onEditGenericName,
    required this.onDelete,
  });

  final List<LaunchQueueEntry> entries;
  final bool isLoading;
  final bool canManageQueue;
  final String? currentUserId;
  final Future<void> Function() onRefresh;
  final Future<void> Function(LaunchQueueEntry entry) onMarkCompleted;
  final Future<void> Function(LaunchQueueEntry entry) onMarkCancelled;
  final Future<void> Function(LaunchQueueEntry entry) onEditGenericName;
  final Future<void> Function(LaunchQueueEntry entry) onDelete;

  @override
  Widget build(BuildContext context) {
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

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            itemBuilder: (context, index) {
              final entry = entries[index];
              final subtitleLines = _buildSubtitleLines(entry);
              final availableActions = _availableActions(entry);

              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primaryContainer,
                    foregroundColor: Theme.of(
                      context,
                    ).colorScheme.onPrimaryContainer,
                    child: Text(entry.queuePosition.toString()),
                  ),
                  title: Text(
                    entry.displayBoatName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  subtitle: Text(
                    subtitleLines.join('\n'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  trailing: availableActions.isEmpty
                      ? null
                      : PopupMenuButton<_QueueCrudAction>(
                          onSelected: (action) async {
                            switch (action) {
                              case _QueueCrudAction.markCompleted:
                                await onMarkCompleted(entry);
                                break;
                              case _QueueCrudAction.markCancelled:
                                await onMarkCancelled(entry);
                                break;
                              case _QueueCrudAction.editGenericName:
                                await onEditGenericName(entry);
                                break;
                              case _QueueCrudAction.delete:
                                await onDelete(entry);
                                break;
                            }
                          },
                          itemBuilder: (_) => availableActions
                              .map(
                                (action) => PopupMenuItem<_QueueCrudAction>(
                                  value: action,
                                  child: Text(_labelForAction(action)),
                                ),
                              )
                              .toList(),
                        ),
                ),
              );
            },
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemCount: entries.length,
          ),
        ),
        if (isLoading)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(minHeight: 3),
          ),
      ],
    );
  }

  List<String> _buildSubtitleLines(LaunchQueueEntry entry) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final lines = <String>[
      'Status: ${_translateStatus(entry.status)}',
      'Entrada: ${dateFormat.format(entry.requestedAt)}',
    ];

    if (entry.isGenericEntry && (entry.genericBoatName?.isNotEmpty ?? false)) {
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

  List<_QueueCrudAction> _availableActions(LaunchQueueEntry entry) {
    final isOwnRequest =
        currentUserId != null &&
        currentUserId!.isNotEmpty &&
        entry.requestedBy == currentUserId;

    final actions = <_QueueCrudAction>[];

    if (canManageQueue) {
      actions.add(_QueueCrudAction.markCompleted);
      actions.add(_QueueCrudAction.markCancelled);
    }

    if (canManageQueue && entry.isGenericEntry) {
      actions.add(_QueueCrudAction.editGenericName);
    }

    if (canManageQueue || isOwnRequest) {
      actions.add(_QueueCrudAction.delete);
    }

    return actions;
  }
}

class _QueueCrudInfoMessage extends StatelessWidget {
  const _QueueCrudInfoMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}

class _QueueCrudErrorState extends StatelessWidget {
  const _QueueCrudErrorState({required this.error, required this.onRetry});

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

enum _QueueCrudAction { markCompleted, markCancelled, editGenericName, delete }

Future<String?> _promptGenericEntryLabel(BuildContext context) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Nova entrada genérica'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Descrição (opcional)',
            hintText: 'Ex.: Embarcação de apoio',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop(controller.text.trim());
            },
            child: const Text('Adicionar'),
          ),
        ],
      );
    },
  );
  controller.dispose();
  return result;
}

Future<String?> _promptGenericEntryEdit(
  BuildContext context, {
  required String initialValue,
}) async {
  final controller = TextEditingController(text: initialValue);
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Editar descrição'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Descrição'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop(controller.text.trim());
            },
            child: const Text('Salvar'),
          ),
        ],
      );
    },
  );
  controller.dispose();
  return result;
}

Future<bool?> _confirmDeletion(BuildContext context, LaunchQueueEntry entry) {
  return showDialog<bool>(
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
}

String _labelForAction(_QueueCrudAction action) {
  switch (action) {
    case _QueueCrudAction.markCompleted:
      return 'Marcar como concluída';
    case _QueueCrudAction.markCancelled:
      return 'Marcar como cancelada';
    case _QueueCrudAction.editGenericName:
      return 'Editar descrição';
    case _QueueCrudAction.delete:
      return 'Remover da fila';
  }
}

String _translateStatus(String status) {
  switch (status) {
    case 'completed':
      return 'Concluída';
    case 'cancelled':
      return 'Cancelada';
    default:
      return 'Pendente';
  }
}

String _mapPostgrestError(PostgrestException error) {
  if (error.code == '23505') {
    return 'Esta embarcação já está na fila.';
  }
  return 'Falha ao processar a solicitação: ${error.message}';
}
