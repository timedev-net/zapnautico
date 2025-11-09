import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../boats/domain/boat.dart';
import '../../marinas/domain/marina.dart';
import '../../marinas/providers.dart';
import '../data/launch_queue_repository.dart';
import '../domain/launch_queue_entry.dart';
import '../providers.dart';

class QueueCrudPage extends ConsumerWidget {
  const QueueCrudPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(queueEntriesProvider);
    final marinasAsync = ref.watch(marinasProvider);
    final isProcessing = ref.watch(queueOperationInProgressProvider);
    final selectedMarinaId = ref.watch(queueFilterProvider);

    final marinas = marinasAsync.asData?.value ?? const <Marina>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Fila de embarcações')),
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
        data: (entries) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: _QueueMarinaFilter(
                marinas: marinas,
                selectedMarinaId: selectedMarinaId,
                onChanged: (value) {
                  ref.read(queueFilterProvider.notifier).state = value;
                  ref.invalidate(queueEntriesProvider);
                },
              ),
            ),
            Expanded(
              child: _QueueEntriesList(
                entries: entries,
                isLoading: entriesAsync.isLoading,
                actionsEnabled: !isProcessing,
                onRefresh: () async {
                  ref.invalidate(queueEntriesProvider);
                  await ref.read(queueEntriesProvider.future);
                },
                onEdit: (entry) => _openForm(context, ref, entry: entry),
                onDelete: (entry) => _deleteEntry(context, ref, entry),
              ),
            ),
          ],
        ),
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

    final currentFilter = ref.read(queueFilterProvider);
    final selectedFilterMarina =
        currentFilter == queueNoMarinaFilterValue ? null : currentFilter;

    final result = await showDialog<_QueueEntryFormResult>(
      context: context,
      builder: (dialogContext) {
        return _QueueEntryFormDialog(
          marinas: marinas,
          boats: boats,
          entry: entry,
          initialMarinaId: entry != null && entry.marinaId.isNotEmpty
              ? entry.marinaId
              : selectedFilterMarina,
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
        );
      } else {
        await repository.updateEntry(
          entryId: entry.id,
          marinaId: result.clearMarina ? '' : result.marinaId,
          boatId: result.clearBoat
              ? ''
              : (result.boatId ?? entry.boatId),
          status: result.status,
          processedAt:
              result.status == 'pending' ? null : DateTime.now(),
          clearProcessedAt: result.status == 'pending',
          genericBoatName: result.genericBoatName ?? '',
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Não foi possível salvar a entrada: $error'),
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
          SnackBar(
            content: Text('Não foi possível remover a entrada: $error'),
          ),
        );
      }
    } finally {
      notifier.state = false;
    }
  }
}

class _QueueEntriesList extends StatelessWidget {
  const _QueueEntriesList({
    required this.entries,
    required this.isLoading,
    required this.actionsEnabled,
    required this.onRefresh,
    required this.onEdit,
    required this.onDelete,
  });

  final List<LaunchQueueEntry> entries;
  final bool isLoading;
  final bool actionsEnabled;
  final Future<void> Function() onRefresh;
  final void Function(LaunchQueueEntry entry) onEdit;
  final void Function(LaunchQueueEntry entry) onDelete;

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

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        itemBuilder: (context, index) {
          final entry = entries[index];
          final subtitleLines = _buildSubtitleLines(entry);

          return Card(
            child: ListTile(
              leading: _QueueEntryAvatar(entry: entry),
              title: Text(
                entry.displayBoatName,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              subtitle: Text(
                subtitleLines.join('\n'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                ],
              ),
            ),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemCount: entries.length,
      ),
    );
  }

  List<String> _buildSubtitleLines(LaunchQueueEntry entry) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
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
}

class _QueueEntryAvatar extends StatelessWidget {
  const _QueueEntryAvatar({required this.entry});

  final LaunchQueueEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasPhoto = entry.hasBoatPhoto;
    final radius = 26.0;
    final placeholderColor = theme.colorScheme.primaryContainer;
    final placeholderForeground = theme.colorScheme.onPrimaryContainer;

    Widget avatarContent;

    if (hasPhoto) {
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
    return DropdownButtonFormField<String?>(
      initialValue: selectedMarinaId,
      decoration: const InputDecoration(
        labelText: 'Filtrar por marina',
        border: OutlineInputBorder(),
      ),
      hint: const Text('Selecione uma opção'),
      isExpanded: true,
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('Todas as marinas'),
        ),
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
  });

  final List<Marina> marinas;
  final List<Boat> boats;
  final LaunchQueueEntry? entry;
  final String? initialMarinaId;

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

  @override
  void initState() {
    super.initState();

    final entryMarinaId = widget.entry?.marinaId ?? '';
    if (entryMarinaId.isNotEmpty) {
      _selectedMarinaId = entryMarinaId;
    } else {
      final initial = widget.initialMarinaId ?? '';
      _selectedMarinaId = initial.isNotEmpty ? initial : null;
    }

    final boatId = widget.entry?.boatId;
    _selectedBoatId =
        (boatId != null && boatId.isNotEmpty) ? boatId : null;

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
      title: Text(
        widget.entry == null ? 'Nova entrada' : 'Editar entrada',
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
    final filtered = widget.boats
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

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final description = _descriptionController.text.trim();
    final hasBoat =
        _selectedBoatId != null && _selectedBoatId!.isNotEmpty;
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
    );

    Navigator.of(context).pop(result);
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
  });

  final String? marinaId;
  final String status;
  final String? boatId;
  final String? genericBoatName;
  final bool clearMarina;
  final bool clearBoat;
}

class _QueueStatusOption {
  const _QueueStatusOption(this.value, this.label);

  final String value;
  final String label;
}

const _statusOptions = <_QueueStatusOption>[
  _QueueStatusOption('pending', 'Pendente'),
  _QueueStatusOption('completed', 'Concluída'),
  _QueueStatusOption('cancelled', 'Cancelada'),
];

String _translateStatus(String status) {
  for (final option in _statusOptions) {
    if (option.value == status) return option.label;
  }
  return status;
}
