import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player_media_kit/video_player_media_kit.dart';

import 'app/app.dart';
import 'core/supabase/supabase_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  VideoPlayerMediaKit.ensureInitialized(
    linux: !kIsWeb && defaultTargetPlatform == TargetPlatform.linux,
    windows: !kIsWeb && defaultTargetPlatform == TargetPlatform.windows,
  );

  // Global Flutter framework error handler
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    if (kDebugMode) {
      debugPrint('FlutterError: ${details.exception}\n${details.stack}');
    }
  };

  // Global isolate / platform error handler (uncaught async errors)
  PlatformDispatcher.instance.onError = (error, stack) {
    if (kDebugMode) {
      debugPrint('PlatformError: $error\n$stack');
    }
    return true; // swallowed - app keeps running
  };

  try {
    await SupabaseService.init();
  } catch (e, st) {
    debugPrint('Supabase init failed: $e\n$st');
  }

  runApp(const ProviderScope(child: AlsamosApp()));
}
