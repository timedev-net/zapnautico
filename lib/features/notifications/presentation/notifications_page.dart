import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/notification_repository.dart';
import '../domain/user_notification.dart';
import '../providers.dart';

class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key});

  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  bool _markAllInProgress = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _refresh(ref));
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(notificationsRealtimeSyncProvider);
    final notificationsAsync = ref.watch(userNotificationsProvider);
    final repository = ref.watch(notificationRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificações'),
        actions: [
          IconButton(
            tooltip: 'Marcar tudo como lido',
            icon: _markAllInProgress
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.done_all),
            onPressed: notificationsAsync.maybeWhen(
              data: (list) => list.any((n) => n.isPending)
                  ? () async {
                      await _markAll(ref, repository);
                    }
                  : null,
              orElse: () => null,
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _refresh(ref),
        child: notificationsAsync.when(
          data: (notifications) {
            if (notifications.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 160),
                  Center(child: Text('Nenhuma notificação no momento.')),
                ],
              );
            }
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              itemBuilder: (_, index) {
                final notification = notifications[index];
                return _NotificationTile(
                  notification: notification,
                  onRead: () async {
                    if (!notification.isPending) return;
                    await repository.markAsRead(notification.id);
                    await _refresh(ref);
                  },
                );
              },
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemCount: notifications.length,
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Não foi possível carregar notificações: $error'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(userNotificationsProvider);
    ref.invalidate(pendingNotificationsCountProvider);
    await ref.read(userNotificationsProvider.future);
  }

  Future<void> _markAll(
    WidgetRef ref,
    NotificationRepository repository,
  ) async {
    if (_markAllInProgress) return;
    setState(() => _markAllInProgress = true);
    try {
      await repository.markAllAsRead();
      await _refresh(ref);
    } finally {
      if (mounted) {
        setState(() => _markAllInProgress = false);
      }
    }
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onRead});

  final UserNotification notification;
  final VoidCallback onRead;

  @override
  Widget build(BuildContext context) {
    final createdAt = DateFormat(
      'dd/MM/yyyy HH:mm',
    ).format(notification.createdAt.toLocal());
    final theme = Theme.of(context);
    final isPending = notification.isPending;
    final pendingColor = theme.colorScheme.primaryContainer;

    return Card(
      color: isPending ? pendingColor.withAlpha(64) : null,
      child: ListTile(
        title: Text(notification.title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(notification.body),
            const SizedBox(height: 4),
            Text(createdAt, style: theme.textTheme.bodySmall),
          ],
        ),
        trailing: isPending
            ? IconButton(
                tooltip: 'Marcar como lida',
                icon: const Icon(Icons.mark_email_read_outlined),
                onPressed: onRead,
              )
            : const Icon(Icons.check, color: Colors.green),
      ),
    );
  }
}
