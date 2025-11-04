import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_providers.dart';
import '../../user_profiles/providers.dart';
import '../domain/chat_group.dart';
import '../domain/chat_message.dart';
import '../providers.dart';

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  String? _selectedGroupId;

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(chatGroupsProvider);
    final membershipAsync = ref.watch(chatGroupMembershipProvider);
    final isAdmin = ref.watch(isAdminProvider);

    return groupsAsync.when(
      data: (groups) {
        if (groups.isEmpty) {
          return _EmptyChatState(isAdmin: isAdmin);
        }

        final membership = membershipAsync.maybeWhen(
          data: (value) => value,
          orElse: () => <String>{},
        );

        final selectedGroup = _resolveSelectedGroup(groups, membership, isAdmin);
        final isMember = isAdmin || membership.contains(selectedGroup.id);

        return Column(
          children: [
            _GroupSelector(
              groups: groups,
              selectedGroup: selectedGroup,
              onChanged: (groupId) {
                setState(() {
                  _selectedGroupId = groupId;
                });
              },
              onCreateGroup: isAdmin ? _createGroup : null,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _GroupInfoBanner(
                group: selectedGroup,
                isMember: isMember,
                onJoin: isMember ? null : () => _joinGroup(selectedGroup.id),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _MessagesList(
                groupId: selectedGroup.id,
                isMember: isMember,
                scrollController: _scrollController,
              ),
            ),
            _MessageComposer(
              controller: _messageController,
              enabled: isMember,
              onSend: () => _handleSend(selectedGroup.id),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.chat_bubble_outline, size: 56),
              const SizedBox(height: 12),
              const Text('Não foi possível carregar os grupos.'),
              const SizedBox(height: 8),
              Text('$error', textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  ChatGroup _resolveSelectedGroup(
    List<ChatGroup> groups,
    Set<String> membership,
    bool isAdmin,
  ) {
    if (groups.isEmpty) {
      throw StateError('Lista de grupos vazia.');
    }
    if (_selectedGroupId != null) {
      final match = groups.where((g) => g.id == _selectedGroupId).toList();
      if (match.isNotEmpty) {
        return match.first;
      }
    }

    // Prefer grupos em que o usuário já é membro; caso contrário, pega o primeiro da lista.
    if (membership.isNotEmpty) {
      final firstMember = groups.firstWhere(
        (group) => membership.contains(group.id),
        orElse: () => groups.first,
      );
      _selectedGroupId = firstMember.id;
      return firstMember;
    }

    _selectedGroupId = groups.first.id;
    return groups.first;
  }

  Future<void> _joinGroup(String groupId) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(chatRepositoryProvider).joinGroup(groupId);
      ref.invalidate(chatGroupMembershipProvider);
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Não foi possível ingressar: $error')),
      );
    }
  }

  Future<void> _createGroup() async {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Novo grupo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Nome do grupo'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descriptionController,
              decoration: const InputDecoration(labelText: 'Descrição (opcional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Criar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final name = nameController.text.trim();
    if (name.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Informe um nome para o grupo.')),
      );
      return;
    }

    try {
      await ref.read(chatRepositoryProvider).createGroup(
            name: name,
            description: descriptionController.text.trim().isEmpty
                ? null
                : descriptionController.text.trim(),
          );
      ref.invalidate(chatGroupsProvider);
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Não foi possível criar o grupo: $error')),
      );
    }
  }

  Future<void> _handleSend(String? groupId) async {
    if (groupId == null) return;
    final content = _messageController.text.trim();
    if (content.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);

    try {
      await ref.read(chatRepositoryProvider).sendMessage(
            groupId: groupId,
            content: content,
          );
      _messageController.clear();
      ref.invalidate(chatMessagesProvider(groupId));
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Mensagem não enviada: $error')),
      );
    }
  }
}

class _GroupSelector extends StatelessWidget {
  const _GroupSelector({
    required this.groups,
    required this.selectedGroup,
    required this.onChanged,
    this.onCreateGroup,
  });

  final List<ChatGroup> groups;
  final ChatGroup? selectedGroup;
  final ValueChanged<String> onChanged;
  final VoidCallback? onCreateGroup;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: selectedGroup?.id,
              decoration: const InputDecoration(
                labelText: 'Grupo de conversa',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final group in groups)
                  DropdownMenuItem(
                    value: group.id,
                    child: Text(group.name),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  onChanged(value);
                }
              },
            ),
          ),
          if (onCreateGroup != null) ...[
            const SizedBox(width: 12),
            IconButton(
              tooltip: 'Criar novo grupo',
              onPressed: onCreateGroup,
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ],
      ),
    );
  }
}

class _GroupInfoBanner extends StatelessWidget {
  const _GroupInfoBanner({
    required this.group,
    required this.isMember,
    this.onJoin,
  });

  final ChatGroup group;
  final bool isMember;
  final VoidCallback? onJoin;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (group.description != null && group.description!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(group.description!),
          ),
        if (!isMember && onJoin != null)
          ElevatedButton.icon(
            onPressed: onJoin,
            icon: const Icon(Icons.group_add),
            label: const Text('Ingressar no grupo'),
          ),
      ],
    );
  }
}

class _MessagesList extends ConsumerWidget {
  const _MessagesList({
    required this.groupId,
    required this.isMember,
    required this.scrollController,
  });

  final String groupId;
  final bool isMember;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messagesAsync = ref.watch(chatMessagesProvider(groupId));
    final currentUser =
        ref.watch(userProvider) ?? Supabase.instance.client.auth.currentSession?.user;

    return messagesAsync.when(
      data: (messages) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (scrollController.hasClients) {
            scrollController.jumpTo(scrollController.position.maxScrollExtent);
          }
        });

        if (!isMember) {
          return const Center(
            child: Text('Entre no grupo para visualizar as mensagens.'),
          );
        }

        if (messages.isEmpty) {
          return const Center(
            child: Text('Ainda não há mensagens neste grupo.'),
          );
        }

        final orderedMessages = messages.toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));

        return ListView.builder(
          controller: scrollController,
          padding: const EdgeInsets.all(16),
          itemCount: orderedMessages.length,
          itemBuilder: (context, index) {
            final message = orderedMessages[index];
            final isMine = message.senderId == currentUser?.id;
            return _MessageBubble(message: message, isMine: isMine);
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.chat_bubble_outline, size: 56),
              const SizedBox(height: 12),
              const Text('Não foi possível carregar as mensagens.'),
              const SizedBox(height: 8),
              Text('$error', textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.isMine});

  final ChatMessage message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bubble = Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isMine
            ? theme.colorScheme.primary
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment:
            isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isMine)
            Text(
              message.senderName ?? 'Cotista',
              style:
                  theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          if (!isMine) const SizedBox(height: 4),
          Text(
            message.content,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isMine
                  ? theme.colorScheme.onPrimary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            MaterialLocalizations.of(context).formatTimeOfDay(
              TimeOfDay.fromDateTime(message.createdAt),
              alwaysUse24HourFormat: true,
            ),
            style: theme.textTheme.labelSmall?.copyWith(
              color: isMine
                  ? theme.colorScheme.onPrimary.withValues(alpha: 0.8)
                  : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );

    if (isMine) {
      return Align(
        alignment: Alignment.centerRight,
        child: bubble,
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: theme.colorScheme.primaryContainer,
          child: ClipOval(
            child: message.senderAvatarUrl != null &&
                    message.senderAvatarUrl!.isNotEmpty
                ? Image.network(
                    message.senderAvatarUrl!,
                    width: 36,
                    height: 36,
                    fit: BoxFit.cover,
                  )
                : Center(
                    child: Text(
                      _initialsFromName(message.senderName),
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: bubble),
      ],
    );
  }

  String _initialsFromName(String? name) {
    if (name == null || name.isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return parts.first.substring(0, 1).toUpperCase();
  }
}

class _MessageComposer extends StatelessWidget {
  const _MessageComposer({
    required this.controller,
    required this.enabled,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final Future<void> Function() onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                enabled: enabled,
                decoration: InputDecoration(
                  hintText: enabled
                      ? 'Escreva uma mensagem...'
                      : 'Entre no grupo para enviar mensagens',
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              icon: const Icon(Icons.send),
              onPressed: enabled ? onSend : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyChatState extends StatelessWidget {
  const _EmptyChatState({required this.isAdmin});

  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.groups_outlined, size: 72),
            const SizedBox(height: 16),
            Text(
              'Nenhum grupo de conversa disponível.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              isAdmin
                  ? 'Crie um grupo para iniciar as conversas entre os cotistas.'
                  : 'Aguarde um administrador criar grupos para participar.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
