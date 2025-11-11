import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase_providers.dart';
import '../../admin/presentation/admin_push_notification_page.dart';
import '../../admin/presentation/admin_user_management_page.dart';
import '../../boats/presentation/boat_list_page.dart';
import '../../marinas/presentation/marina_list_page.dart';
import '../../user_profiles/domain/profile_models.dart';
import '../../user_profiles/providers.dart';
import '../data/user_contact_repository.dart';
import '../domain/user_contact_channel.dart';
import '../providers.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final profilesAsync = ref.watch(currentUserProfilesProvider);
    final isAdmin = ref.watch(isAdminProvider);
    final contactsAsync = ref.watch(userContactsProvider);
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
              'Contatos preferenciais',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            contactsAsync.when(
              data: (contacts) => _ContactPreferencesSection(
                contacts: contacts,
              ),
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (error, stackTrace) => Text(
                'Erro ao carregar contatos: $error',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
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
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AdminPushNotificationPage(),
                    ),
                  );
                },
                icon: const Icon(Icons.notifications_active_outlined),
                label: const Text('Enviar push para todos'),
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

class _ContactPreferencesSection extends ConsumerWidget {
  const _ContactPreferencesSection({required this.contacts});

  final List<UserContactChannel> contacts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final whatsappContacts = contacts
        .where((contact) => contact.isWhatsapp)
        .toList()
      ..sort((a, b) => a.position.compareTo(b.position));

    UserContactChannel? instagramContact;
    for (final contact in contacts) {
      if (contact.isInstagram) {
        instagramContact = contact;
        break;
      }
    }

    return Card(
      child: Column(
        children: [
          if (whatsappContacts.isEmpty)
            const ListTile(
              leading: Icon(Icons.chat_bubble_outline),
              title: Text('Nenhum WhatsApp cadastrado'),
              subtitle: Text(
                'Adicione um ou mais contatos para facilitar o atendimento via app.',
              ),
            )
          else
            for (final contact in whatsappContacts)
              ListTile(
                leading: const Icon(Icons.chat_bubble_outline),
                title: Text(contact.label),
                subtitle: Text(contact.normalizedWhatsapp),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Editar contato',
                      onPressed: () => _openWhatsappForm(
                        context,
                        ref,
                        existing: contact,
                      ),
                      icon: const Icon(Icons.edit),
                    ),
                    IconButton(
                      tooltip: 'Remover contato',
                      onPressed: () => _confirmDeleteContact(
                        context,
                        ref,
                        contact,
                      ),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: OutlinedButton.icon(
                onPressed: () => _openWhatsappForm(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('Adicionar WhatsApp'),
              ),
            ),
          ),
          const Divider(height: 0),
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined),
            title: const Text('Instagram'),
            subtitle: Text(
              instagramContact?.instaHandle ?? 'Nenhum perfil informado',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: instagramContact == null
                      ? 'Cadastrar Instagram'
                      : 'Editar Instagram',
                  onPressed: () => _openInstagramForm(
                    context,
                    ref,
                    existing: instagramContact,
                  ),
                  icon: const Icon(Icons.edit),
                ),
                if (instagramContact != null)
                  IconButton(
                    tooltip: 'Remover Instagram',
                    onPressed: () => _confirmDeleteContact(
                      context,
                      ref,
                      instagramContact!,
                    ),
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _openWhatsappForm(
  BuildContext context,
  WidgetRef ref, {
  UserContactChannel? existing,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final formKey = GlobalKey<FormState>();
  final segments = _WhatsappSegments.fromValue(existing?.value);
  final nameController = TextEditingController(text: existing?.label ?? '');
  final dddController = TextEditingController(text: segments.ddd);
  final numberController = TextEditingController(text: segments.number);

  String previewNumber() {
    final ddd = dddController.text;
    final number = numberController.text;
    if (ddd.length < 2 || number.length < 8) {
      return 'Informe DDD e número para gerar o link.';
    }
    final formatted = '+55$ddd$number';
    return 'Link gerado: $formatted';
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      final navigator = Navigator.of(sheetContext);
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: StatefulBuilder(
          builder: (stateContext, setState) {
            String? errorText;

            Future<void> submit() async {
              if (!formKey.currentState!.validate()) {
                return;
              }
              final ddd = dddController.text;
              final number = numberController.text;
              try {
                await ref.read(userContactRepositoryProvider).upsertContact(
                      id: existing?.id,
                      channel: 'whatsapp',
                      label: nameController.text.trim(),
                      value: '+55$ddd$number',
                    );
                ref.invalidate(userContactsProvider);
                navigator.pop();
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      existing == null
                          ? 'Contato salvo com sucesso.'
                          : 'Contato atualizado.',
                    ),
                  ),
                );
              } catch (error) {
                setState(() {
                  errorText = '$error';
                });
              }
            }

            return Padding(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      existing == null
                          ? 'Novo contato WhatsApp'
                          : 'Editar contato WhatsApp',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Nome do contato',
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Informe o nome para identificação.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: dddController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(2),
                            ],
                            decoration: const InputDecoration(
                              labelText: 'DDD',
                            ),
                            onChanged: (_) => setState(() {}),
                            validator: (value) {
                              if (value == null || value.length != 2) {
                                return 'Informe o DDD';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 5,
                          child: TextFormField(
                            controller: numberController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(9),
                            ],
                            decoration: const InputDecoration(
                              labelText: 'Número',
                              hintText: '987654321',
                            ),
                            onChanged: (_) => setState(() {}),
                            validator: (value) {
                              if (value == null || value.length < 8) {
                                return 'Informe o número com 8 ou 9 dígitos.';
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      previewNumber(),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        errorText!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.error,
                            ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        icon: const Icon(Icons.save),
                        label: Text(existing == null ? 'Salvar contato' : 'Atualizar'),
                        onPressed: submit,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    },
  );

  nameController.dispose();
  dddController.dispose();
  numberController.dispose();
}

Future<void> _openInstagramForm(
  BuildContext context,
  WidgetRef ref, {
  UserContactChannel? existing,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final controller = TextEditingController(text: existing?.value ?? '');
  String? errorText;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      final navigator = Navigator.of(sheetContext);
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: StatefulBuilder(
          builder: (stateContext, setState) {
            Future<void> submit() async {
              if (controller.text.trim().isEmpty) {
                setState(() => errorText = 'Informe o usuário do Instagram.');
                return;
              }
              try {
                await ref.read(userContactRepositoryProvider).upsertContact(
                      id: existing?.id,
                      channel: 'instagram',
                      label: 'Instagram',
                      value: controller.text.trim(),
                    );
                ref.invalidate(userContactsProvider);
                navigator.pop();
                messenger.showSnackBar(
                  const SnackBar(content: Text('Instagram atualizado.')),
                );
              } catch (error) {
                setState(() => errorText = '$error');
              }
            }

            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    existing == null
                        ? 'Adicionar Instagram'
                        : 'Editar Instagram',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      labelText: 'Usuário',
                      prefixText: '@',
                    ),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      errorText!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.error,
                          ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.save),
                      label: const Text('Salvar'),
                      onPressed: submit,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
    },
  );

  controller.dispose();
}

Future<void> _confirmDeleteContact(
  BuildContext context,
  WidgetRef ref,
  UserContactChannel contact,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Remover contato'),
        content: Text(
          'Deseja remover "${contact.label}"? Esta ação não pode ser desfeita.',
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

  if (confirmed != true) {
    return;
  }

  await ref.read(userContactRepositoryProvider).deleteContact(contact.id);
  ref.invalidate(userContactsProvider);
  messenger.showSnackBar(
    SnackBar(content: Text('"${contact.label}" foi removido.')),
  );
}

class _WhatsappSegments {
  _WhatsappSegments({this.ddd = '', this.number = ''});

  final String ddd;
  final String number;

  factory _WhatsappSegments.fromValue(String? value) {
    if (value == null) {
      return _WhatsappSegments();
    }
    final digits = value.replaceAll(RegExp(r'\D'), '');
    var normalized = digits.startsWith('55') ? digits.substring(2) : digits;
    if (normalized.length > 11) {
      normalized = normalized.substring(normalized.length - 11);
    }
    if (normalized.length < 10) {
      return _WhatsappSegments();
    }
    final ddd = normalized.substring(0, 2);
    final number = normalized.substring(2);
    return _WhatsappSegments(ddd: ddd, number: number);
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
