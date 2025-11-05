import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/app_config.dart';
import '../../../core/supabase_providers.dart';

class AuthController {
  AuthController(this._client);

  final SupabaseClient _client;

  Future<void> signInWithGoogle() async {
    await _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: kIsWeb ? null : AppConfig.oauthRedirectUri,
      authScreenLaunchMode:
          kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
    );
  }

  Future<void> signInWithApple() async {
    await _client.auth.signInWithOAuth(
      OAuthProvider.apple,
      redirectTo: kIsWeb ? null : AppConfig.oauthRedirectUri,
      authScreenLaunchMode:
          kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
    );
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }
}

final authControllerProvider = Provider<AuthController>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return AuthController(client);
});
