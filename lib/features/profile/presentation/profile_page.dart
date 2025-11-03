import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase_providers.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return authState.when(
      data: (session) {
        final user = session?.user;
        if (user == null) {
          return const Center(
            child: Text('Nenhum usuário autenticado.'),
          );
        }

        final metadata = user.userMetadata ?? {};
        final initials = _getInitials(user.email, metadata['full_name'] as String? ?? metadata['name'] as String?);
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
              radius: 36,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Text(
                initials,
                style: Theme.of(context).textTheme.headlineSmall,
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
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => Center(
        child: Text('Erro ao carregar perfil: $error'),
      ),
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
