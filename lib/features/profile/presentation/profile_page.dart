import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase_providers.dart';
import '../../admin/presentation/admin_user_management_page.dart';
import '../../boats/presentation/boat_list_page.dart';
import '../../marinas/presentation/marina_list_page.dart';
import '../../user_profiles/domain/profile_models.dart';
import '../../user_profiles/providers.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final profilesAsync = ref.watch(currentUserProfilesProvider);
    final isAdmin = ref.watch(isAdminProvider);
    final profileList =
        profilesAsync.asData?.value ?? const <UserProfileAssignment>[];
    final hasOwnerProfile = profileList.any(
      (profile) =>
          profile.profileSlug == 'proprietario' ||
          profile.profileSlug == 'cotista',
    );
    final hasMarinaProfile = profileList.any(
      (profile) => profile.profileSlug == 'marina',
    );

    return authState.when(
      data: (session) {
        final user = session?.user;
        if (user == null) {
          return const Center(child: Text('Nenhum usuário autenticado.'));
        }

        final metadata = user.userMetadata ?? {};
        final avatarUrl =
            metadata['avatar_url'] as String? ??
            user.appMetadata['avatar_url'] as String? ??
            user.userMetadata?['picture'] as String?;
        final initials = _getInitials(
          user.email,
          metadata['full_name'] as String? ?? metadata['name'] as String?,
        );
        final lastSignInRaw = user.lastSignInAt;
        final lastSignInDate = lastSignInRaw != null
            ? DateTime.tryParse(lastSignInRaw)?.toLocal()
            : null;
        final localizations = MaterialLocalizations.of(context);
        final lastSignInText = lastSignInDate != null
            ? '${localizations.formatShortDate(lastSignInDate)} '
                  '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(lastSignInDate), alwaysUse24HourFormat: true)}'
            : 'Ainda não acessou.';

        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: ClipOval(
                child: avatarUrl != null && avatarUrl.isNotEmpty
                    ? Image.network(
                        avatarUrl,
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                      )
                    : Center(
                        child: Text(
                          initials,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              metadata['full_name'] as String? ??
                  metadata['name'] as String? ??
                  user.email ??
                  user.id,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              user.email ?? 'Sem e-mail cadastrado',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            const Text(
              'Informações da conta',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.badge_outlined),
                    title: const Text('ID do usuário'),
                    subtitle: Text(user.id),
                  ),
                  if (user.phone != null && user.phone!.isNotEmpty)
                    ListTile(
                      leading: const Icon(Icons.call),
                      title: const Text('Telefone'),
                      subtitle: Text(user.phone!),
                    ),
                  ListTile(
                    leading: const Icon(Icons.lock_clock),
                    title: const Text('Último login'),
                    subtitle: Text(lastSignInText),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Perfis atribuídos',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            profilesAsync.when(
              data: (profiles) {
                if (profiles.isEmpty) {
                  return const Text(
                    'Nenhum perfil vinculado. Contate um administrador para solicitar acesso.',
                  );
                }
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final profile in profiles)
                      Chip(
                        label: Text(
                          profile.profileSlug == 'marina' &&
                                  profile.marinaName != null &&
                                  profile.marinaName!.isNotEmpty
                              ? '${profile.profileName} - ${profile.marinaName}'
                              : profile.profileName,
                        ),
                      ),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => Text(
                'Erro ao carregar perfis: $error',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
            if (!isAdmin && (hasOwnerProfile || hasMarinaProfile)) ...[
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const BoatListPage(),
                    ),
                  );
                },
                icon: const Icon(Icons.directions_boat),
                label: Text(
                  hasOwnerProfile
                      ? 'Minhas embarcações'
                      : 'Embarcações da minha marina',
                ),
              ),
            ],
            if (isAdmin) ...[
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const BoatListPage(),
                    ),
                  );
                },
                icon: const Icon(Icons.directions_boat),
                label: const Text('Gerenciar embarcações'),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AdminUserManagementPage(),
                    ),
                  );
                },
                icon: const Icon(Icons.manage_accounts),
                label: const Text('Gerenciar perfis de usuários'),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const MarinaListPage(),
                    ),
                  );
                },
                icon: const Icon(Icons.sailing),
                label: const Text('Gerenciar marinas'),
              ),
            ],
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) =>
          Center(child: Text('Erro ao carregar perfil: $error')),
    );
  }
}

String _getInitials(String? email, String? fullName) {
  final source = fullName?.trim();
  if (source != null && source.isNotEmpty) {
    final parts = source.split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return source.substring(0, 1).toUpperCase();
  }
  if (email != null && email.isNotEmpty) {
    return email.substring(0, 2).toUpperCase();
  }
  return '--';
}
