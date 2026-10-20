/// Build-time settings, passed with:
///
///   flutter run --dart-define-from-file=env.json
///   flutter build apk --release --split-per-abi --dart-define-from-file=env.json
///
/// env.json (not committed — see env.example.json):
///   {
///     "SUPABASE_URL": "https://xxxx.supabase.co",
///     "SUPABASE_ANON_KEY": "eyJ...",          (the public anon key, never the service-role key)
///     "SMARTSPEND_WEB_URL": "https://your-site.vercel.app"
///   }
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const webUrl = String.fromEnvironment('SMARTSPEND_WEB_URL');

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty && webUrl.isNotEmpty;

  /// Base URL without a trailing slash.
  static String get webBase =>
      webUrl.endsWith('/') ? webUrl.substring(0, webUrl.length - 1) : webUrl;
}
