import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../boats/domain/boat.dart';
import '../../boats/providers.dart';
import '../../../core/supabase_providers.dart';
import '../../financial/presentation/financial_management_page.dart';
import '../../marinas/domain/marina.dart';
import '../../marinas/providers.dart';
import '../../queue/data/launch_queue_repository.dart';
import '../../queue/presentation/marina_queue_dashboard_page.dart';
import '../../user_profiles/domain/profile_models.dart';
import '../../user_profiles/providers.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final Set<String> _launchingBoatIds = {};

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
      MaterialPageRoute<void>(
        builder: (_) => const MarinaQueueDashboardPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profilesAsync = ref.watch(currentUserProfilesProvider);
    final boatsAsync = ref.watch(boatsProvider);
    final userId = ref.watch(userProvider)?.id;

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
            Image.asset(
              'assets/images/logo.png',
              height: 96,
            ),
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
                label: const Text('Dashboard da marina'),
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
              isLaunching: _launchingBoatIds.contains,
              onLaunch: (boat) => _requestBoatLaunch(context, boat),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _requestBoatLaunch(BuildContext context, Boat boat) async {
    if (_launchingBoatIds.contains(boat.id)) return;

    final repository = ref.read(launchQueueRepositoryProvider);
    final userId = ref.read(userProvider)?.id;
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
              content: Text(
                'Não foi possível carregar as marinas: $error',
              ),
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

    final isBoatOwner = boat.canEdit(userId);
    if (isBoatOwner) {
      try {
        final hasEntryToday = await repository.hasActiveEntryForBoatOnDate(
          boatId: boat.id,
          referenceDate: DateTime.now(),
        );

        if (hasEntryToday) {
          if (mounted) {
            messenger.showSnackBar(
              const SnackBar(
                content: Text(
                  'Você já possui um registro na fila para hoje.',
                ),
              ),
            );
          }
          return;
        }
      } catch (error) {
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                'Não foi possível verificar registros anteriores: $error',
              ),
            ),
          );
        }
        return;
      }
    }

    setState(() => _launchingBoatIds.add(boat.id));

    try {
      await repository.createEntry(
        marinaId: marinaId,
        boatId: boat.id,
      );

      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('${boat.name} adicionada à fila.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Não foi possível descer a embarcação: $error'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _launchingBoatIds.remove(boat.id));
      }
    }
  }
}

class _OwnedBoatsSection extends StatelessWidget {
  const _OwnedBoatsSection({
    required this.boatsAsync,
    required this.userId,
    required this.isLaunching,
    required this.onLaunch,
  });

  final AsyncValue<List<Boat>> boatsAsync;
  final String? userId;
  final bool Function(String boatId) isLaunching;
  final Future<void> Function(Boat boat) onLaunch;

  @override
  Widget build(BuildContext context) {
    return boatsAsync.when(
      data: (boats) {
        final ownedBoats =
            boats.where((boat) => boat.canEdit(userId)).toList();
        if (ownedBoats.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Suas embarcações',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            for (final boat in ownedBoats) ...[
              _BoatCard(
                boat: boat,
                isLaunching: isLaunching(boat.id),
                onLaunch: () => onLaunch(boat),
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
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 4),
            Text(
              '$error',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _BoatCard extends StatelessWidget {
  const _BoatCard({
    required this.boat,
    required this.isLaunching,
    required this.onLaunch,
  });

  final Boat boat;
  final bool isLaunching;
  final VoidCallback onLaunch;

  @override
  Widget build(BuildContext context) {
    final preview = boat.photos.isNotEmpty ? boat.photos.first.publicUrl : null;

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
                          color:
                              Theme.of(context).colorScheme.primaryContainer,
                        ),
                        child: const Icon(Icons.directions_boat_filled),
                      )
                    : Image.network(
                        preview,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => DecoratedBox(
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .primaryContainer,
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
                    onPressed: isLaunching ? null : onLaunch,
                    child: isLaunching
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Descer a embarcação'),
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
