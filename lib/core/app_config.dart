/// Application-wide configuration loaded from compile-time environment values.
class AppConfig {
  AppConfig._();

  static const supabaseUrl =
      String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://buykphfcdyjwotzsgprr.supabase.co');
  static const supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJ1eWtwaGZjZHlqd290enNncHJyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjIxODIxNzksImV4cCI6MjA3Nzc1ODE3OX0.Y6LbH0Td-h2qfcVPN_BsSD0Ixf7q55fEn1iIkntHHqM');
  static const oauthRedirectUri = String.fromEnvironment(
    'SUPABASE_OAUTH_REDIRECT',
    defaultValue: 'zapnautico://auth-callback',
  );

  /// Ensures required configuration values are provided before bootstrapping.
  static void validate() {
    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      throw StateError(
        'Supabase credentials missing. Provide SUPABASE_URL and SUPABASE_ANON_KEY '
        'using --dart-define when launching the app.',
      );
    }
  }
}

