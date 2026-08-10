/// Central place for Supabase + future api.alsamos.com config.
/// Pass at build time with:
///   flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
class ApiConstants {
  ApiConstants._();

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://mbhjganbihamoiqmankv.supabase.co',
  );

  // NOTE: This is the public anon/publishable key (safe for clients,
  // protected by RLS). Do NOT put service_role keys in the app.
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1iaGpnYW5iaWhhbW9pcW1hbmt2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjU0NjkwNDcsImV4cCI6MjA4MTA0NTA0N30.E080sOgNEw_7vU0c7_REt_uxwgE6fc4hIQhdUi4FCNw',
  );

  // Future custom backend
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.alsamos.com',
  );

  static void validate({
    String url = supabaseUrl,
    String anonKey = supabaseAnonKey,
  }) {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !uri.hasScheme ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        !uri.host.endsWith('.supabase.co')) {
      throw StateError(
        'Invalid SUPABASE_URL. Expected https://<project-ref>.supabase.co',
      );
    }

    final jwtParts = anonKey.split('.');
    if (jwtParts.length != 3 || anonKey.length < 80) {
      throw StateError(
        'Invalid SUPABASE_ANON_KEY. Provide the public anon key with --dart-define.',
      );
    }
  }
}
