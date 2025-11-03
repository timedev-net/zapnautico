/// Application-wide configuration loaded from compile-time environment values.
class AppConfig {
  AppConfig._();

  static const supabaseUrl =
      String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  static const supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');
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

