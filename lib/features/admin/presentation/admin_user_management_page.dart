import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../marinas/domain/marina.dart';
import '../../marinas/providers.dart';
import '../../user_profiles/data/user_profile_repository.dart';
import '../../user_profiles/domain/marina_roles.dart';
import '../../user_profiles/domain/profile_models.dart';
import '../../user_profiles/providers.dart';

class AdminUserManagementPage extends ConsumerWidget {
  const AdminUserManagementPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(adminUsersWithProfilesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Gerenciar usuários')),
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
        final marinas = await ref.read(marinasProvider.future);
        String? initialMarinaId;
        for (final profile in item.profiles) {
          if (isMarinaRoleSlug(profile.profileSlug) &&
              profile.marinaId != null) {
            initialMarinaId = profile.marinaId;
            break;
          }
        }
        if (!context.mounted) return;
        await _showEditProfilesSheet(
          context: context,
          ref: ref,
          user: item.user,
          availableProfiles: profileTypes,
          initialSelection: item.profiles.map((e) => e.profileSlug).toSet(),
          marinas: marinas,
          initialMarinaId: initialMarinaId,
          repository: repository,
        );
      } catch (error) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Não foi possível carregar os perfis: $error'),
          ),
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
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.primaryContainer,
                  child: ClipOval(
                    child:
                        item.user.avatarUrl != null &&
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
                      label: Text(
                        isMarinaRoleSlug(profile.profileSlug) &&
                                profile.marinaName != null &&
                                profile.marinaName!.isNotEmpty
                            ? '${profile.profileName} - ${profile.marinaName}'
                            : profile.profileName,
                      ),
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
  required List<Marina> marinas,
  String? initialMarinaId,
  required UserProfileRepository repository,
}) async {
  final selected = {...initialSelection};
  var selectedMarinaId = initialMarinaId;
  if (selectedMarinaId != null &&
      !marinas.any((marina) => marina.id == selectedMarinaId)) {
    selectedMarinaId = null;
  }
  String? marinaSelectionError;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
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
                ...availableProfiles.map((profile) {
                  final isSelected = selected.contains(profile.slug);
                  final isMarinaProfile = marinaRoleSlugs.contains(profile.slug);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CheckboxListTile(
                        value: isSelected,
                        onChanged: (value) {
                          if (value == true &&
                              isMarinaProfile &&
                              marinas.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Cadastre uma marina antes de atribuir este perfil.',
                                ),
                              ),
                            );
                            return;
                          }
                          setState(() {
                            if (value == true) {
                              selected.add(profile.slug);
                              if (isMarinaProfile) {
                                marinaSelectionError = null;
                              }
                            } else {
                              selected.remove(profile.slug);
                              if (isMarinaProfile) {
                                selectedMarinaId = null;
                                marinaSelectionError = null;
                              }
                            }
                          });
                        },
                        title: Text(profile.name),
                        subtitle: profile.description != null
                            ? Text(profile.description!)
                            : null,
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      if (isMarinaProfile && isSelected && marinas.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(
                            left: 16,
                            right: 16,
                            bottom: 8,
                          ),
                          child: Text(
                            'Nenhuma marina cadastrada. Cadastre uma marina antes de atribuir este perfil.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                          ),
                        ),
                      if (isMarinaProfile && isSelected && marinas.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(
                            left: 16,
                            right: 16,
                            bottom: 8,
                          ),
                          child: DropdownButtonFormField<String>(
                            initialValue: selectedMarinaId,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: 'Selecione a marina',
                              hintText: 'Escolha a marina responsável',
                              errorText: marinaSelectionError,
                            ),
                            items: [
                              for (final marina in marinas)
                                DropdownMenuItem(
                                  value: marina.id,
                                  child: Text(marina.name),
                                ),
                            ],
                            onChanged: (value) {
                              setState(() {
                                selectedMarinaId = value;
                                marinaSelectionError = null;
                              });
                            },
                          ),
                        ),
                      const SizedBox(height: 8),
                    ],
                  );
                }),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      final requiresMarinaSelection =
                          selected.any(marinaRoleSlugs.contains);
                      if (requiresMarinaSelection) {
                        if (marinas.isEmpty) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Cadastre uma marina antes de atribuir este perfil.',
                                ),
                              ),
                            );
                          }
                          return;
                        }
                        if (selectedMarinaId == null) {
                          setState(() {
                            marinaSelectionError =
                                'Selecione uma marina para este perfil.';
                          });
                          return;
                        }
                      }

                      final payloads = <Map<String, dynamic>>[];
                      for (final profile in availableProfiles) {
                        if (selected.contains(profile.slug)) {
                          final payload = <String, dynamic>{
                            'slug': profile.slug,
                          };
                          if (marinaRoleSlugs.contains(profile.slug)) {
                            payload['marina_id'] = selectedMarinaId;
                          }
                          payloads.add(payload);
                        }
                      }

                      try {
                        await repository.adminSetUserProfiles(
                          userId: user.id,
                          profilePayloads: payloads,
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
                            SnackBar(
                              content: Text('Erro ao salvar perfis: $error'),
                            ),
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
