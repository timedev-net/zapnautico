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
        final userDisplayName =
            metadata['full_name'] as String? ??
            metadata['name'] as String? ??
            user.email ??
            user.id;

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
              userDisplayName,
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
                userDisplayName: userDisplayName,
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
  const _ContactPreferencesSection({
    required this.contacts,
    required this.userDisplayName,
  });

  final List<UserContactChannel> contacts;
  final String userDisplayName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final whatsappContacts =
        contacts.where((contact) => contact.isWhatsapp).toList()
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
                        defaultLabel: userDisplayName,
                        existing: contact,
                      ),
                      icon: const Icon(Icons.edit),
                    ),
                    IconButton(
                      tooltip: 'Remover contato',
                      onPressed: () =>
                          _confirmDeleteContact(context, ref, contact),
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
                onPressed: () =>
                    _openWhatsappForm(context, defaultLabel: userDisplayName),
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
                  onPressed: () =>
                      _openInstagramForm(context, existing: instagramContact),
                  icon: const Icon(Icons.edit),
                ),
                if (instagramContact != null)
                  IconButton(
                    tooltip: 'Remover Instagram',
                    onPressed: () =>
                        _confirmDeleteContact(context, ref, instagramContact!),
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
  BuildContext context, {
  required String defaultLabel,
  UserContactChannel? existing,
}) async {
  final messenger = ScaffoldMessenger.of(context);

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _WhatsappFormSheet(
      defaultLabel: defaultLabel,
      existing: existing,
      messenger: messenger,
    ),
  );
}

Future<void> _openInstagramForm(
  BuildContext context, {
  UserContactChannel? existing,
}) async {
  final messenger = ScaffoldMessenger.of(context);

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) =>
        _InstagramFormSheet(existing: existing, messenger: messenger),
  );
}

class _WhatsappFormSheet extends ConsumerStatefulWidget {
  const _WhatsappFormSheet({
    required this.defaultLabel,
    required this.messenger,
    this.existing,
  });

  final String defaultLabel;
  final ScaffoldMessengerState messenger;
  final UserContactChannel? existing;

  @override
  ConsumerState<_WhatsappFormSheet> createState() => _WhatsappFormSheetState();
}

class _WhatsappFormSheetState extends ConsumerState<_WhatsappFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _dddController;
  late final TextEditingController _numberController;
  late final String _resolvedLabel;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final segments = _WhatsappSegments.fromValue(widget.existing?.value);
    _dddController = TextEditingController(text: segments.ddd);
    _numberController = TextEditingController(text: segments.number);
    _resolvedLabel = _resolveLabel();
  }

  String _resolveLabel() {
    final existing = widget.existing;
    if (existing != null && existing.label.trim().isNotEmpty) {
      return existing.label.trim();
    }
    final defaultLabel = widget.defaultLabel.trim();
    if (defaultLabel.isNotEmpty) {
      return defaultLabel;
    }
    return 'Contato WhatsApp';
  }

  String _previewNumber() {
    final ddd = _dddController.text;
    final number = _numberController.text;
    if (ddd.length < 2 || number.length < 8) {
      return 'Informe DDD e número para gerar o link.';
    }
    final formatted = '+55$ddd$number';
    return 'Link gerado: $formatted';
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final ddd = _dddController.text;
    final number = _numberController.text;
    try {
      await ref
          .read(userContactRepositoryProvider)
          .upsertContact(
            id: widget.existing?.id,
            channel: 'whatsapp',
            label: _resolvedLabel,
            value: '+55$ddd$number',
          );
      ref.invalidate(userContactsProvider);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      widget.messenger.showSnackBar(
        SnackBar(
          content: Text(
            widget.existing == null
                ? 'Contato salvo com sucesso.'
                : 'Contato atualizado.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorText = '$error';
      });
    }
  }

  @override
  void dispose() {
    _dddController.dispose();
    _numberController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom + 24;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 24, 24, bottomPadding),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.existing == null
                  ? 'Novo contato WhatsApp'
                  : 'Editar contato WhatsApp',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Este contato sera exibido como "$_resolvedLabel".',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _dddController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(2),
                    ],
                    decoration: const InputDecoration(labelText: 'DDD'),
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
                    controller: _numberController,
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
              _previewNumber(),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorText!,
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
                label: Text(
                  widget.existing == null ? 'Salvar contato' : 'Atualizar',
                ),
                onPressed: _submit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InstagramFormSheet extends ConsumerStatefulWidget {
  const _InstagramFormSheet({required this.messenger, this.existing});

  final ScaffoldMessengerState messenger;
  final UserContactChannel? existing;

  @override
  ConsumerState<_InstagramFormSheet> createState() =>
      _InstagramFormSheetState();
}

class _InstagramFormSheetState extends ConsumerState<_InstagramFormSheet> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.existing?.value ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final value = _controller.text.trim();
    if (value.isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() => _errorText = 'Informe o usuário do Instagram.');
      return;
    }
    try {
      await ref
          .read(userContactRepositoryProvider)
          .upsertContact(
            id: widget.existing?.id,
            channel: 'instagram',
            label: 'Instagram',
            value: value,
          );
      ref.invalidate(userContactsProvider);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      widget.messenger.showSnackBar(
        SnackBar(
          content: Text(
            widget.existing == null
                ? 'Instagram cadastrado.'
                : 'Instagram atualizado.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _errorText = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom + 24;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 24, 24, bottomPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.existing == null
                ? 'Adicionar Instagram'
                : 'Editar Instagram',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            decoration: const InputDecoration(
              labelText: 'Usuário',
              prefixText: '@',
            ),
          ),
          if (_errorText != null) ...[
            const SizedBox(height: 8),
            Text(
              _errorText!,
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
              onPressed: _submit,
            ),
          ),
        ],
      ),
    );
  }
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
