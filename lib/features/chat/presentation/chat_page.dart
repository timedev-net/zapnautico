import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_providers.dart';
import '../../user_profiles/providers.dart';
import '../domain/chat_group.dart';
import '../domain/chat_message.dart';
import '../domain/typing_user.dart';
import '../providers.dart';

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> with WidgetsBindingObserver {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final FocusNode _composerFocusNode = FocusNode();
  double _lastViewInsetsBottom = 0;
  String? _selectedGroupId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _composerFocusNode.addListener(_handleComposerFocusChange);
    _lastViewInsetsBottom = _currentViewInsetsBottom;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _composerFocusNode.removeListener(_handleComposerFocusChange);
    _composerFocusNode.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    final currentBottom = _currentViewInsetsBottom;
    if (currentBottom > _lastViewInsetsBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _scrollToBottom(animated: true);
        }
      });
    }
    _lastViewInsetsBottom = currentBottom;
  }

  void _handleComposerFocusChange() {
    if (_composerFocusNode.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _scrollToBottom(animated: true);
        }
      });
    }
  }

  void _scrollToBottom({bool animated = false}) {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position.maxScrollExtent;
    if (animated) {
      _scrollController.animateTo(
        position,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(position);
    }
  }

  double get _currentViewInsetsBottom {
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    ui.FlutterView? view;
    if (dispatcher.views.isNotEmpty) {
      view = dispatcher.views.first;
    } else {
      view = dispatcher.implicitView;
    }
    if (view == null) return 0;
    return view.viewInsets.bottom / view.devicePixelRatio;
  }

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(chatGroupsProvider);
    final membershipAsync = ref.watch(chatGroupMembershipProvider);
    final isAdmin = ref.watch(isAdminProvider);
    final currentUser =
        ref.watch(userProvider) ?? Supabase.instance.client.auth.currentSession?.user;

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
        final onlineCountAsync = ref.watch(
          chatGroupOnlineCountProvider(
            (groupId: selectedGroup.id, trackSelf: isMember),
          ),
        );
        final typingAsync = ref.watch(
          chatGroupTypingProvider(
            (
              groupId: selectedGroup.id,
              excludeUserId: currentUser?.id,
            ),
          ),
        );

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
                onlineCount: onlineCountAsync,
                onJoin: isMember ? null : () => _joinGroup(selectedGroup.id),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => FocusScope.of(context).unfocus(),
                child: _MessagesList(
                  groupId: selectedGroup.id,
                  isMember: isMember,
                  scrollController: _scrollController,
                ),
              ),
            ),
            _TypingIndicator(typing: typingAsync, isMember: isMember),
            _MessageComposer(
              groupId: selectedGroup.id,
              controller: _messageController,
              enabled: isMember,
              onSend: () => _handleSend(selectedGroup.id),
              focusNode: _composerFocusNode,
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
    required this.onlineCount,
    this.onJoin,
  });

  final ChatGroup group;
  final bool isMember;
  final VoidCallback? onJoin;
  final AsyncValue<int> onlineCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onlineText = onlineCount.when(
      data: (count) => count == 1 ? '1 usuário online' : '$count usuários online',
      loading: () => 'Carregando usuários...',
      error: (_, __) => 'Usuários online indisponível',
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (group.description != null && group.description!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(group.description!),
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, size: 10, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Text(
              onlineText,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        if (!isMember && onJoin != null) ...[
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: onJoin,
            icon: const Icon(Icons.group_add),
            label: const Text('Ingressar no grupo'),
          ),
        ],
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
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
              TimeOfDay.fromDateTime(message.createdAt.toLocal()),
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

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator({
    required this.typing,
    required this.isMember,
  });

  final AsyncValue<Set<TypingUser>> typing;
  final bool isMember;

  @override
  Widget build(BuildContext context) {
    if (!isMember) {
      return const SizedBox.shrink();
    }
    return typing.when(
      data: (users) {
        if (users.isEmpty) {
          return const SizedBox.shrink();
        }
        final names = users.map((user) => user.name).toList();
        final text = names.length == 1
            ? '${names.first} está digitando...'
            : '${names.join(', ')} estão digitando...';

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              text,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(fontStyle: FontStyle.italic),
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _MessageComposer extends ConsumerStatefulWidget {
  const _MessageComposer({
    required this.groupId,
    required this.controller,
    required this.enabled,
    required this.onSend,
    required this.focusNode,
  });

  final String groupId;
  final TextEditingController controller;
  final bool enabled;
  final Future<void> Function() onSend;
  final FocusNode focusNode;

  @override
  ConsumerState<_MessageComposer> createState() => _MessageComposerState();
}

class _MessageComposerState extends ConsumerState<_MessageComposer> {
  Timer? _typingTimer;
  bool _isTyping = false;

  @override
  void dispose() {
    _stopTyping();
    super.dispose();
  }

  void _updateTyping(bool value) {
    if (_isTyping == value) return;
    _isTyping = value;
    unawaited(ref.read(chatRepositoryProvider).notifyTyping(
          groupId: widget.groupId,
          isTyping: value,
        ));
  }

  void _scheduleTypingStop() {
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () {
      _updateTyping(false);
    });
  }

  void _handleChanged(String value) {
    if (!widget.enabled) return;
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      _typingTimer?.cancel();
      _updateTyping(false);
      return;
    }
    _updateTyping(true);
    _scheduleTypingStop();
  }

  void _stopTyping() {
    _typingTimer?.cancel();
    _typingTimer = null;
    _updateTyping(false);
  }

  Future<void> _handleSend() async {
    if (!widget.enabled) return;
    await widget.onSend();
    _stopTyping();
  }

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
                controller: widget.controller,
                focusNode: widget.focusNode,
                minLines: 1,
                maxLines: 4,
                enabled: widget.enabled,
                onChanged: _handleChanged,
                onEditingComplete: _stopTyping,
                onSubmitted: (_) => unawaited(_handleSend()),
                decoration: InputDecoration(
                  hintText: widget.enabled
                      ? 'Escreva uma mensagem...'
                      : 'Entre no grupo para enviar mensagens',
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              icon: const Icon(Icons.send),
              onPressed:
                  widget.enabled ? () => unawaited(_handleSend()) : null,
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
