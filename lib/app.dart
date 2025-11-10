import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/push_notifications/push_token_registrar.dart';
import 'core/supabase_providers.dart';
import 'core/theme.dart';
import 'features/auth/presentation/auth_gate.dart';

/// Root widget for the ZapNautico application.
class ZapNauticoApp extends ConsumerWidget {
  const ZapNauticoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AsyncValue<Session?>>(
      authStateProvider,
      (_, next) {
        next.whenData(
          (session) =>
              ref.read(pushTokenRegistrarProvider).handleSession(session),
        );
      },
    );

    return MaterialApp(
      title: 'ZapNáutico',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      builder: (context, child) {
        if (child == null) {
          return const SizedBox.shrink();
        }
        return SafeArea(
          top: false,
          left: false,
          right: false,
          bottom: true,
          child: child,
        );
      },
      home: const AuthGate(),
    );
  }
}
