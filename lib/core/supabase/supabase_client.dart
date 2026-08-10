import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/api_constants.dart';

/// Ported from web `src/integrations/supabase/client.ts`.
/// Initialize once in main() before runApp.
class SupabaseService {
  SupabaseService._();

  static Future<void> init() async {
    ApiConstants.validate();
    await Supabase.initialize(
      url: ApiConstants.supabaseUrl,
      // ignore: deprecated_member_use
      anonKey: ApiConstants.supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
  }

  static SupabaseClient get client => Supabase.instance.client;
}

/// Convenient global accessor (mirrors `import { supabase }` on web).
SupabaseClient get supabase => SupabaseService.client;
