import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase_providers.dart';
import '../../user_profiles/domain/profile_models.dart';
import '../../user_profiles/providers.dart';
import '../domain/boat.dart';
import '../providers.dart';
import 'boat_detail_page.dart';
import 'boat_form_page.dart';
import 'boat_gallery_page.dart';

class BoatListPage extends ConsumerWidget {
  const BoatListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boatsAsync = ref.watch(boatsProvider);
    final profilesAsync = ref.watch(currentUserProfilesProvider);
    final user = ref.watch(userProvider);

    final profileInfo =
        profilesAsync.asData?.value ?? const <UserProfileAssignment>[];
    final isAdmin = profileInfo.any(
      (profile) => profile.profileSlug == 'administrador',
    );
    final hasOwnerProfile = profileInfo.any(
      (profile) =>
          profile.profileSlug == 'proprietario' ||
          profile.profileSlug == 'cotista',
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isAdmin
              ? 'Embarcações cadastradas'
              : hasOwnerProfile
                  ? 'Minhas embarcações'
                  : 'Embarcações',
        ),
      ),
      floatingActionButton: hasOwnerProfile
          ? FloatingActionButton.extended(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const BoatFormPage()),
                );
                ref.invalidate(boatsProvider);
              },
              icon: const Icon(Icons.add),
              label: const Text('Nova embarcação'),
            )
          : null,
      body: boatsAsync.when(
        data: (boats) {
          if (boats.isEmpty) {
            return _EmptyState(
              isAdmin: isAdmin,
              hasOwnerProfile: hasOwnerProfile,
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(boatsProvider);
              await ref.read(boatsProvider.future);
            },
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: boats.length,
              itemBuilder: (context, index) {
                final boat = boats[index];
                return _BoatCard(
                  boat: boat,
                  currentUserId: user?.id,
                  isAdmin: isAdmin,
                  onUpdated: () {
                    ref.invalidate(boatsProvider);
                  },
                );
              },
              separatorBuilder: (context, index) => const SizedBox(height: 12),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => _ErrorState(
          error: error,
          onRetry: () => ref.invalidate(boatsProvider),
        ),
      ),
    );
  }
}

class _BoatCard extends StatelessWidget {
  const _BoatCard({
    required this.boat,
    required this.currentUserId,
    required this.isAdmin,
    required this.onUpdated,
  });

  final Boat boat;
  final String? currentUserId;
  final bool isAdmin;
  final VoidCallback onUpdated;

  @override
  Widget build(BuildContext context) {
    final subtitle = <String>[
      if (boat.registrationNumber != null &&
          boat.registrationNumber!.isNotEmpty)
        'Inscrição: ${boat.registrationNumber}',
      if (boat.marinaName != null && boat.marinaName!.isNotEmpty)
        'Marina: ${boat.marinaName}',
      'Finalidade: ${boat.usageType.label}',
      if (boat.coOwners.isNotEmpty) 'Coproprietários: ${boat.coOwners.length}',
    ].join(' • ');

    final preview = boat.photos.isNotEmpty ? boat.photos.first : null;

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        leading: preview == null
            ? CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: const Icon(Icons.directions_boat_filled),
              )
            : GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          BoatGalleryPage(photos: boat.photos, initialIndex: 0),
                    ),
                  );
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    preview.publicUrl,
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => CircleAvatar(
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.primaryContainer,
                      child: const Icon(Icons.directions_boat_filled),
                    ),
                  ),
                ),
              ),
        title: Text(boat.name, style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => BoatDetailPage(boatId: boat.id),
            ),
          );
          onUpdated();
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isAdmin, required this.hasOwnerProfile});

  final bool isAdmin;
  final bool hasOwnerProfile;

  @override
  Widget build(BuildContext context) {
    final title = isAdmin
        ? 'Nenhuma embarcação cadastrada.'
        : hasOwnerProfile
            ? 'Você ainda não cadastrou embarcações.'
            : 'Nenhuma embarcação disponível.';

    final description = isAdmin
        ? 'Cadastre novas embarcações para acompanhar o inventário.'
        : hasOwnerProfile
            ? 'Utilize o botão acima para registrar sua embarcação.'
            : 'Assim que forem vinculadas embarcações você poderá visualizá-las aqui.';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.directions_boat_outlined,
              size: 72,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.warning_amber_rounded,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Não foi possível carregar as embarcações.',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
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
