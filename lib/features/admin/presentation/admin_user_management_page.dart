import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../user_profiles/data/user_profile_repository.dart';
import '../../user_profiles/domain/profile_models.dart';
import '../../user_profiles/providers.dart';

class AdminUserManagementPage extends ConsumerWidget {
  const AdminUserManagementPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(adminUsersWithProfilesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gerenciar usuários'),
      ),
      body: usersAsync.when(
        data: (users) {
          if (users.isEmpty) {
            return const _EmptyState();
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: users.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final item = users[index];
              return _UserCard(item: item);
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => _ErrorState(
          error: error,
          onRetry: () => ref.invalidate(adminUsersWithProfilesProvider),
        ),
      ),
    );
  }
}

class _UserCard extends ConsumerWidget {
  const _UserCard({required this.item});

  final AppUserWithProfiles item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(userProfileRepositoryProvider);

    Future<void> openEditor() async {
      try {
        final profileTypes = await ref.read(profileTypesProvider.future);
        if (!context.mounted) return;
        await _showEditProfilesSheet(
          context: context,
          ref: ref,
          user: item.user,
          availableProfiles: profileTypes,
          initialSelection: item.profiles.map((e) => e.profileSlug).toSet(),
          repository: repository,
        );
      } catch (error) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível carregar os perfis: $error')),
        );
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor:
                      Theme.of(context).colorScheme.primaryContainer,
                  child: ClipOval(
                    child: item.user.avatarUrl != null &&
                            item.user.avatarUrl!.isNotEmpty
                        ? Image.network(
                            item.user.avatarUrl!,
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                          )
                        : Center(
                            child: Text(
                              _initialsFromDisplayName(
                                item.user.displayName,
                                item.user.email,
                              ),
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
                        item.user.displayName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (item.user.email != null)
                        Text(
                          item.user.email!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit),
                  tooltip: 'Editar perfis',
                  onPressed: openEditor,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (item.profiles.isEmpty)
              const Text('Nenhum perfil atribuído.')
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final profile in item.profiles)
                    Chip(
                      label: Text(profile.profileName),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showEditProfilesSheet({
  required BuildContext context,
  required WidgetRef ref,
  required AppUser user,
  required Set<String> initialSelection,
  required List<ProfileType> availableProfiles,
  required UserProfileRepository repository,
}) async {
  final selected = {...initialSelection};

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      return Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
        ),
        child: StatefulBuilder(
          builder: (context, setState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Perfis de ${user.displayName}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                ...availableProfiles.map(
                  (profile) => CheckboxListTile(
                    value: selected.contains(profile.slug),
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          selected.add(profile.slug);
                        } else {
                          selected.remove(profile.slug);
                        }
                      });
                    },
                    title: Text(profile.name),
                    subtitle: profile.description != null
                        ? Text(profile.description!)
                        : null,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      try {
                        await repository.adminSetUserProfiles(
                          userId: user.id,
                          profileSlugs: selected.toList(),
                        );
                        if (context.mounted) {
                          Navigator.of(context).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Perfis atualizados com sucesso.'),
                            ),
                          );
                        }
                        ref.invalidate(adminUsersWithProfilesProvider);
                        ref.invalidate(currentUserProfilesProvider);
                      } catch (error) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Erro ao salvar perfis: $error')),
                          );
                        }
                      }
                    },
                    child: const Text('Salvar alterações'),
                  ),
                ),
              ],
            );
          },
        ),
      );
    },
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.group_outlined,
              size: 72,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Nenhum usuário encontrado.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Convide usuários e atribua perfis para controlar permissões.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.error,
    required this.onRetry,
  });

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
              'Não foi possível carregar os usuários.',
              style: Theme.of(context).textTheme.titleMedium,
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

String _initialsFromDisplayName(String displayName, String? email) {
  final parts = displayName.trim().split(RegExp(r'\s+'));
  if (parts.length >= 2) {
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
  if (parts.isNotEmpty && parts.first.isNotEmpty) {
    return parts.first.substring(0, 1).toUpperCase();
  }
  if (email != null && email.isNotEmpty) {
    return email.substring(0, 2).toUpperCase();
  }
  return '--';
}
