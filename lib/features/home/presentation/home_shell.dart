import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../../core/push_notifications/push_navigation_intent.dart';
import '../../mural/presentation/marina_wall_post_detail_page.dart';
import '../../mural/presentation/mural_page.dart';
import '../../notifications/presentation/notifications_page.dart';
import '../../notifications/providers.dart';
import '../../profile/presentation/profile_page.dart';
import '../../queue/providers.dart';
import '../../queue/presentation/queue_crud_page.dart';
import 'home_page.dart';
import 'home_tab_provider.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  late final ProviderSubscription<PushNavigationIntent?>
  _pushIntentSubscription;
  late final ProviderSubscription<int> _tabSubscription;
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    final initialIntent = ref.read(pushNavigationIntentProvider);
    if (initialIntent != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _handlePushIntent(initialIntent);
        }
      });
    }
    _pushIntentSubscription = ref.listenManual<PushNavigationIntent?>(
      pushNavigationIntentProvider,
      (previous, next) {
        if (next != null) {
          _handlePushIntent(next);
        }
      },
    );

    _tabSubscription = ref.listenManual<int>(homeTabIndexProvider, (
      previous,
      next,
    ) {
      if (next == homeTabHomeIndex) {
        _refreshHomeState();
      }
    });

    _lifecycleListener = AppLifecycleListener(
      onStateChange: (state) {
        if (state == AppLifecycleState.resumed) {
          _refreshHomeState();
          _refreshNotifications();
        }
      },
    );
  }

  @override
  void dispose() {
    _pushIntentSubscription.close();
    _tabSubscription.close();
    _lifecycleListener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(notificationsRealtimeSyncProvider);
    final pendingNotifications = ref.watch(pendingNotificationsCountProvider);
    final selectedIndex = ref.watch(homeTabIndexProvider);
    final pages = [
      const _HomePageConfig(
        title: 'Inicio',
        icon: Icons.home,
        body: HomePage(),
      ),
      const _HomePageConfig(
        title: 'Fila',
        icon: Icons.directions_boat_filled,
        body: QueueCrudPage(showAppBar: false),
      ),
      const _HomePageConfig(
        title: 'Mural',
        icon: Icons.dashboard_customize_outlined,
        body: MuralPage(),
      ),
      const _HomePageConfig(
        title: 'Perfil',
        icon: Icons.person,
        body: ProfilePage(),
      ),
    ];

    final currentPage = pages[selectedIndex.clamp(0, pages.length - 1).toInt()];
    final authController = ref.watch(authControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(currentPage.title),
        actions: [
          _NotificationsAction(pendingNotifications: pendingNotifications),
          IconButton(
            tooltip: 'Sair',
            icon: const Icon(Icons.logout),
            onPressed: () => authController.signOut(),
          ),
        ],
      ),
      body: SafeArea(child: currentPage.body),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (value) =>
            ref.read(homeTabIndexProvider.notifier).state = value,
        destinations: [
          for (final page in pages)
            NavigationDestination(icon: Icon(page.icon), label: page.title),
        ],
      ),
    );
  }

  Future<void> _handlePushIntent(PushNavigationIntent intent) async {
    ref.read(pushNavigationIntentProvider.notifier).state = null;
    if (!mounted) return;

    switch (intent.type) {
      case PushNavigationType.queueStatus:
        _goToQueue(intent);
        break;
      case PushNavigationType.muralPost:
        await _goToMuralDetail(intent);
        break;
    }
  }

  void _goToQueue(PushNavigationIntent intent) {
    ref.read(homeTabIndexProvider.notifier).state = homeTabQueueIndex;

    final marinaId = intent.marinaId;
    if (marinaId != null && marinaId.isNotEmpty) {
      ref.read(queueFilterProvider.notifier).state = marinaId;
      ref.invalidate(queueEntriesProvider);
    }

    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _refreshHomeState() {
    ref.invalidate(ownedBoatsLatestQueueEntriesProvider);
    ref.invalidate(queueEntriesProvider);
  }

  void _refreshNotifications() {
    ref.invalidate(pendingNotificationsCountProvider);
    ref.invalidate(userNotificationsProvider);
    ref.invalidate(notificationsRealtimeSyncProvider);
  }

  Future<void> _goToMuralDetail(PushNavigationIntent intent) async {
    ref.read(homeTabIndexProvider.notifier).state = homeTabMuralIndex;
    if (!mounted) return;

    Navigator.of(context).popUntil((route) => route.isFirst);
    final postId = intent.postId;
    if (postId == null || postId.isEmpty) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MarinaWallPostDetailPage(postId: postId),
      ),
    );
  }
}

class _HomePageConfig {
  const _HomePageConfig({
    required this.title,
    required this.icon,
    required this.body,
  });

  final String title;
  final IconData icon;
  final Widget body;
}

class _NotificationsAction extends ConsumerWidget {
  const _NotificationsAction({required this.pendingNotifications});

  final AsyncValue<int> pendingNotifications;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = pendingNotifications.asData?.value ?? 0;
    final isLoading = pendingNotifications.isLoading;
    final icon = isLoading
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Badge(
            isLabelVisible: count > 0,
            label: Text('$count'),
            child: const Icon(Icons.notifications_none_outlined),
          );

    return IconButton(
      tooltip: 'Notificações',
      icon: icon,
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const NotificationsPage()),
        );
      },
    );
  }
}
