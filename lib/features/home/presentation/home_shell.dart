import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../mural/presentation/mural_page.dart';
import '../../profile/presentation/profile_page.dart';
import '../../queue/presentation/queue_crud_page.dart';
import 'home_page.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  var _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
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

    final currentPage = pages[_selectedIndex];
    final authController = ref.watch(authControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(currentPage.title),
        actions: [
          IconButton(
            tooltip: 'Sair',
            icon: const Icon(Icons.logout),
            onPressed: () => authController.signOut(),
          ),
        ],
      ),
      body: SafeArea(child: currentPage.body),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (value) {
          setState(() {
            _selectedIndex = value;
          });
        },
        destinations: [
          for (final page in pages)
            NavigationDestination(icon: Icon(page.icon), label: page.title),
        ],
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
