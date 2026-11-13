/// Supplied at build/run time:
///   flutter run --dart-define-from-file=env.json
/// Only the publishable (anon) key belongs here. Never the service_role key.
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  static const redirectUrl = 'com.aadav.sareedesk://login-callback';
  static const appName = 'Aadav Saree Desk';
  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;
}
