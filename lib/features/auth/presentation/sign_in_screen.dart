import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../application/auth_controller.dart';

class SignInScreen extends ConsumerWidget {
  const SignInScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(authControllerProvider);
    final colorScheme = Theme.of(context).colorScheme;

    Future<void> handleSignIn(Future<void> Function() action) async {
      final messenger = ScaffoldMessenger.of(context);
      try {
        await action();
      } catch (error) {
        messenger.showSnackBar(
          SnackBar(content: Text('Falha ao autenticar: $error')),
        );
      }
    }

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFFEAF4FF),
              Color(0xFFD9FBF7),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: brandBlue.withValues(alpha: 0.12),
                          blurRadius: 20,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Image.asset(
                      'assets/images/logo.png',
                      width: 160,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'ZapNáutico',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: brandBlue,
                          fontSize: 30,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Gerencie cotas, publique anúncios e converse em tempo real com outros cotistas.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: brandNavy.withValues(alpha: 0.8),
                        ),
                  ),
                  const SizedBox(height: 40),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.login),
                      label: const Text('Entrar com Google'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: brandTeal,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => handleSignIn(controller.signInWithGoogle),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Ao continuar, você concorda com os termos e políticas de uso do ZapNáutico.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
