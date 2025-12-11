import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../boats/domain/boat.dart';
import '../../boats/providers.dart';
import '../../../core/supabase_providers.dart';
import '../../financial/presentation/financial_management_page.dart';
import '../../marinas/domain/marina.dart';
import '../../marinas/providers.dart';
import '../../queue/data/launch_queue_repository.dart';
import '../../queue/domain/launch_queue_entry.dart';
import '../../queue/providers.dart';
import '../../queue/presentation/marina_queue_dashboard_page.dart';
import '../../user_profiles/domain/profile_models.dart';
import '../../user_profiles/providers.dart';

final ownedBoatsLatestQueueStreamProvider =
    StreamProvider<Map<String, LaunchQueueEntry>>((ref) async* {
      final boats = await ref.watch(boatsProvider.future);
      final userId = ref.watch(userProvider)?.id;
      final ownedBoatIds = boats
          .where((boat) => boat.canEdit(userId))
          .map((boat) => boat.id)
          .where((id) => id.isNotEmpty)
          .toList();

      if (ownedBoatIds.isEmpty) {
        yield {};
        return;
      }

      final client = ref.watch(supabaseClientProvider);
      var stream = client
          .from('boat_launch_queue_view')
          .stream(primaryKey: ['id'])
          .inFilter('boat_id', ownedBoatIds);

      await for (final rows in stream) {
        final entries =
            rows
                .cast<Map<String, dynamic>>()
                .map(LaunchQueueEntry.fromMap)
                .toList()
              ..sort((a, b) => b.requestedAt.compareTo(a.requestedAt));

        final latestByBoat = <String, LaunchQueueEntry>{};
        for (final entry in entries) {
          if (entry.boatId.isEmpty) continue;
          latestByBoat.putIfAbsent(entry.boatId, () => entry);
        }

        yield latestByBoat;
      }
    });

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final Set<String> _boatActionInProgress = {};

  Future<void> _openMarinaDashboard(
    BuildContext context,
    UserProfileAssignment profile,
  ) async {
    final marinaId = profile.marinaId;
    if (marinaId == null || marinaId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Associe uma marina ao perfil de gestor para acessar o dashboard.',
          ),
        ),
      );
      return;
    }

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const MarinaQueueDashboardPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profilesAsync = ref.watch(currentUserProfilesProvider);
    final boatsAsync = ref.watch(boatsProvider);
    final userId = ref.watch(userProvider)?.id;
    final latestQueueEntriesAsync = ref.watch(
      ownedBoatsLatestQueueStreamProvider,
    );

    final canAccessFinancial = profilesAsync.maybeWhen(
      data: (profiles) => profiles.any(
        (profile) =>
            profile.profileSlug == 'proprietario' ||
            profile.profileSlug == 'cotista',
      ),
      orElse: () => false,
    );
    final profiles =
        profilesAsync.asData?.value ?? const <UserProfileAssignment>[];
    UserProfileAssignment? marinaManagerProfile;
    for (final profile in profiles) {
      if (profile.profileSlug == 'gestor_marina') {
        marinaManagerProfile = profile;
        break;
      }
    }

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Image.asset('assets/images/logo.png', height: 96),
            const SizedBox(height: 24),
            Text(
              'Bem-vindo ao ZapNáutico',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Navegue com confiança: organize embarcações, equipes e experiências náuticas em um só lugar.',
              style: theme.textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            if (marinaManagerProfile != null) ...[
              FilledButton.icon(
                onPressed: () =>
                    _openMarinaDashboard(context, marinaManagerProfile!),
                icon: const Icon(Icons.analytics_outlined),
                label: const Text('Dashboard'),
              ),
              const SizedBox(height: 12),
            ],
            if (canAccessFinancial) ...[
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const FinancialManagementPage(),
                  ),
                ),
                icon: const Icon(Icons.receipt_long),
                label: const Text('Gestão financeira'),
              ),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 32),
            _OwnedBoatsSection(
              boatsAsync: boatsAsync,
              userId: userId,
              queueEntriesAsync: latestQueueEntriesAsync,
              isBusy: _boatActionInProgress.contains,
              onRequestLaunch: (boat, latestEntry) =>
                  _requestBoatLaunch(context, boat, latestEntry: latestEntry),
              onCancelPending: (entry) => _cancelQueueEntry(context, entry),
              onCompleteFromWater: (entry) => _completeLaunch(context, entry),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _requestBoatLaunch(
    BuildContext context,
    Boat boat, {
    LaunchQueueEntry? latestEntry,
  }) async {
    if (_boatActionInProgress.contains(boat.id)) return;

    final repository = ref.read(launchQueueRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);

    String? marinaId = boat.marinaId;

    if (marinaId == null || marinaId.isEmpty) {
      List<Marina> marinas = const [];
      try {
        marinas = await ref.read(marinasProvider.future);
      } catch (error) {
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text('Não foi possível carregar as marinas: $error'),
            ),
          );
        }
        return;
      }

      if (!mounted) return;

      if (marinas.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Nenhuma marina disponível. Cadastre uma marina.'),
          ),
        );
        return;
      }

      if (!context.mounted) return;

      marinaId = await showDialog<String>(
        context: context,
        builder: (_) => _SelectMarinaDialog(marinas: marinas),
      );

      if (marinaId == null || marinaId.isEmpty || !context.mounted) {
        return;
      }
    }

    LaunchQueueEntry? latest;
    try {
      latest = await repository.fetchLatestEntryForBoat(boat.id);
    } catch (_) {
      latest = latestEntry;
    }

    latest ??= latestEntry;

    if (latest != null &&
        latest.status != 'cancelled' &&
        latest.status != 'completed') {
      final statusLabel = _translateStatus(latest.status);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Já existe um registro $statusLabel para esta embarcação.',
          ),
        ),
      );
      return;
    }

    setState(() => _boatActionInProgress.add(boat.id));

    try {
      await repository.createEntry(marinaId: marinaId, boatId: boat.id);

      ref.invalidate(ownedBoatsLatestQueueStreamProvider);
      ref.invalidate(queueEntriesProvider);

      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('${boat.name} adicionada à fila.')),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Não foi possível descer a embarcação: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _boatActionInProgress.remove(boat.id));
      }
    }
  }

  Future<void> _cancelQueueEntry(
    BuildContext context,
    LaunchQueueEntry entry,
  ) async {
    final busyKey = entry.boatId.isNotEmpty ? entry.boatId : entry.id;
    if (_boatActionInProgress.contains(busyKey)) return;

    if (entry.status == 'cancelled' || entry.status == 'completed') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Registro já finalizado.')),
        );
      }
      return;
    }

    setState(() => _boatActionInProgress.add(busyKey));
    final repository = ref.read(launchQueueRepositoryProvider);

    try {
      await repository.updateEntry(
        entryId: entry.id,
        status: 'cancelled',
        processedAt: DateTime.now(),
        clearScheduledTransition: true,
      );

      ref.invalidate(ownedBoatsLatestQueueStreamProvider);
      ref.invalidate(queueEntriesProvider);

      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Descida cancelada com sucesso.')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível cancelar: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _boatActionInProgress.remove(busyKey));
      }
    }
  }

  Future<void> _completeLaunch(
    BuildContext context,
    LaunchQueueEntry entry,
  ) async {
    final busyKey = entry.boatId.isNotEmpty ? entry.boatId : entry.id;
    if (_boatActionInProgress.contains(busyKey)) return;

    if (entry.status == 'completed' || entry.status == 'cancelled') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Registro já finalizado.')),
        );
      }
      return;
    }

    setState(() => _boatActionInProgress.add(busyKey));
    final repository = ref.read(launchQueueRepositoryProvider);

    try {
      await repository.updateEntry(
        entryId: entry.id,
        status: 'completed',
        processedAt: DateTime.now(),
        clearScheduledTransition: true,
      );

      ref.invalidate(ownedBoatsLatestQueueStreamProvider);
      ref.invalidate(queueEntriesProvider);

      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Subida registrada com sucesso.')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível concluir o registro: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _boatActionInProgress.remove(busyKey));
      }
    }
  }

  String _translateStatus(String status) {
    switch (status) {
      case 'pending':
        return 'pendente';
      case 'in_progress':
        return 'em andamento';
      case 'in_water':
        return 'na água';
      case 'completed':
        return 'concluído';
      case 'cancelled':
        return 'cancelado';
      default:
        return status;
    }
  }
}

class _OwnedBoatsSection extends StatelessWidget {
  const _OwnedBoatsSection({
    required this.boatsAsync,
    required this.userId,
    required this.queueEntriesAsync,
    required this.isBusy,
    required this.onRequestLaunch,
    required this.onCancelPending,
    required this.onCompleteFromWater,
  });

  final AsyncValue<List<Boat>> boatsAsync;
  final String? userId;
  final AsyncValue<Map<String, LaunchQueueEntry>> queueEntriesAsync;
  final bool Function(String boatId) isBusy;
  final Future<void> Function(Boat boat, LaunchQueueEntry? latestEntry)
  onRequestLaunch;
  final Future<void> Function(LaunchQueueEntry entry) onCancelPending;
  final Future<void> Function(LaunchQueueEntry entry) onCompleteFromWater;

  @override
  Widget build(BuildContext context) {
    return boatsAsync.when(
      data: (boats) {
        final ownedBoats = boats.where((boat) => boat.canEdit(userId)).toList();
        if (ownedBoats.isEmpty) {
          return const SizedBox.shrink();
        }

        final latestEntries =
            queueEntriesAsync.asData?.value ??
            const <String, LaunchQueueEntry>{};
        final isStatusLoading =
            queueEntriesAsync.isLoading || queueEntriesAsync.hasError;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Suas embarcações',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (queueEntriesAsync.hasError) ...[
              const SizedBox(height: 8),
              Text(
                'Não foi possível atualizar o status da fila agora.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 12),
            for (final boat in ownedBoats) ...[
              _BoatCard(
                boat: boat,
                latestEntry: latestEntries[boat.id],
                isBusy: isBusy(boat.id),
                isStatusLoading: isStatusLoading,
                onLaunch: () => onRequestLaunch(boat, latestEntries[boat.id]),
                onCancelPending: latestEntries[boat.id] != null
                    ? () => onCancelPending(latestEntries[boat.id]!)
                    : null,
                onCompleteFromWater:
                    latestEntries[boat.id]?.status == 'in_water'
                    ? () => onCompleteFromWater(latestEntries[boat.id]!)
                    : null,
              ),
              const SizedBox(height: 12),
            ],
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Não foi possível carregar suas embarcações.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
            const SizedBox(height: 4),
            Text('$error', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _BoatCard extends StatelessWidget {
  const _BoatCard({
    required this.boat,
    required this.latestEntry,
    required this.isBusy,
    required this.isStatusLoading,
    required this.onLaunch,
    required this.onCancelPending,
    required this.onCompleteFromWater,
  });

  final Boat boat;
  final LaunchQueueEntry? latestEntry;
  final bool isBusy;
  final bool isStatusLoading;
  final VoidCallback onLaunch;
  final VoidCallback? onCancelPending;
  final VoidCallback? onCompleteFromWater;

  @override
  Widget build(BuildContext context) {
    final preview = boat.photos.isNotEmpty ? boat.photos.first.publicUrl : null;
    final status = latestEntry?.status;

    String buttonText = 'Descer a embarcação';
    VoidCallback? action = onLaunch;

    if (status == 'pending') {
      buttonText = 'Cancelar descida';
      action = onCancelPending;
    } else if (status == 'in_progress') {
      buttonText = 'Em andamento';
      action = null;
    } else if (status == 'in_water') {
      buttonText = 'Subir embarcação';
      action = onCompleteFromWater;
    }

    final bool disableButton = isStatusLoading || isBusy || action == null;
    final bool showProgress = isBusy && action != null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 72,
                height: 72,
                child: preview == null || preview.isEmpty
                    ? DecoratedBox(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                        ),
                        child: const Icon(Icons.directions_boat_filled),
                      )
                    : Image.network(
                        preview,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => DecoratedBox(
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.primaryContainer,
                          ),
                          child: const Icon(Icons.directions_boat_filled),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    boat.name,
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: disableButton ? null : action,
                    child: showProgress
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(buttonText),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectMarinaDialog extends StatefulWidget {
  const _SelectMarinaDialog({required this.marinas});

  final List<Marina> marinas;

  @override
  State<_SelectMarinaDialog> createState() => _SelectMarinaDialogState();
}

class _SelectMarinaDialogState extends State<_SelectMarinaDialog> {
  late String _selectedMarinaId;

  @override
  void initState() {
    super.initState();
    _selectedMarinaId = widget.marinas.first.id;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Selecione a marina'),
      content: DropdownButtonFormField<String>(
        initialValue: _selectedMarinaId,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Marina',
          border: OutlineInputBorder(),
        ),
        items: widget.marinas
            .map(
              (marina) => DropdownMenuItem<String>(
                value: marina.id,
                child: Text(marina.name),
              ),
            )
            .toList(),
        onChanged: (value) {
          if (value == null) return;
          setState(() {
            _selectedMarinaId = value;
          });
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_selectedMarinaId),
          child: const Text('Confirmar'),
        ),
      ],
    );
  }
}
