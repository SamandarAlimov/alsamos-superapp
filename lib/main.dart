import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:video_player_media_kit/video_player_media_kit.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app/app.dart';
import 'core/services/app_analytics_service.dart';
import 'core/services/app_lifecycle_service.dart';
import 'core/services/crash_reporting_service.dart';
import 'core/supabase/supabase_client.dart';
import 'features/messages/data/services/message_notifications_service.dart';

import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize sqflite FFI for desktop platforms (Windows/Linux/macOS)
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  await _configureDesktopWindow();
  VideoPlayerMediaKit.ensureInitialized(
    linux: !kIsWeb && defaultTargetPlatform == TargetPlatform.linux,
    windows: !kIsWeb && defaultTargetPlatform == TargetPlatform.windows,
  );
  JustAudioMediaKit.ensureInitialized(
    linux: !kIsWeb && defaultTargetPlatform == TargetPlatform.linux,
    windows: !kIsWeb && defaultTargetPlatform == TargetPlatform.windows,
  );

  // Global Flutter framework error handler
  FlutterError.onError = (FlutterErrorDetails details) {
    if (_shouldIgnoreFrameworkNoise(details.exception)) return;
    FlutterError.presentError(details);
    crashReporting.record(details.exception, details.stack,
        context: 'FlutterError');
    if (kDebugMode) {
      debugPrint('FlutterError: ${details.exception}\n${details.stack}');
    }
  };

  // Global isolate / platform error handler (uncaught async errors)
  PlatformDispatcher.instance.onError = (error, stack) {
    if (_shouldIgnoreFrameworkNoise(error)) return true;
    crashReporting.record(error, stack, context: 'PlatformDispatcher');
    if (kDebugMode) {
      debugPrint('PlatformError: $error\n$stack');
    }
    return true; // swallowed - app keeps running
  };

  try {
    await _initializeFirebase();
    await SupabaseService.init();
    appAnalytics.init();
    appLifecycle.init();
    await MessageNotificationsService.init();
  } catch (e, st) {
    debugPrint('App services init failed: $e\n$st');
  }

  runApp(const ProviderScope(child: AlsamosApp()));
}

bool _shouldIgnoreFrameworkNoise(Object error) {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return false;
  final message = error.toString();
  return message.contains('raw_keyboard.dart') &&
      message.contains('Attempted to send a key down event') &&
      message.contains('keysPressed');
}

Future<void> _initializeFirebase() async {
  if (!_firebaseCoreSupported) {
    // Firebase not supported on this platform - silent skip
    return;
  }
  if (Firebase.apps.isNotEmpty) return;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    // Firebase initialization failed - continue without it
    if (kDebugMode) {
      debugPrint('[Firebase] Initialization failed: $e');
    }
  }
}

bool get _firebaseCoreSupported {
  if (kIsWeb) return true;
  return switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => true,
    _ => false,
  };
}

Future<void> _configureDesktopWindow() async {
  if (kIsWeb) return;
  final desktop = switch (defaultTargetPlatform) {
    TargetPlatform.windows ||
    TargetPlatform.linux ||
    TargetPlatform.macOS =>
      true,
    _ => false,
  };
  if (!desktop) return;

  await windowManager.ensureInitialized();
  const options = WindowOptions(
    size: Size(1200, 800),
    minimumSize: Size(320, 480),
    center: true,
    title: 'Alsamos',
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.setMinimumSize(const Size(320, 480));
    await windowManager.show();
    await windowManager.focus();
  });
}
