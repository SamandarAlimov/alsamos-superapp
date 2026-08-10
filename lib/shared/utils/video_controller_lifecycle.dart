import 'dart:async';

import 'package:video_player/video_player.dart';

/// Best-effort cleanup for video controllers backed by native media engines.
///
/// Windows hot-restart can tear down native callbacks while Dart futures are
/// still completing, especially with media_kit-backed video_player. Pausing
/// before disposal gives the native backend a cleaner shutdown path without
/// changing playback behavior.
void disposeVideoControllerSafely(VideoPlayerController? controller) {
  if (controller == null) return;
  unawaited(_disposeVideoController(controller));
}

Future<void> _disposeVideoController(VideoPlayerController controller) async {
  try {
    if (controller.value.isInitialized) {
      await controller.pause();
    }
  } catch (_) {
    // Native backends may already be gone during hot restart.
  }

  try {
    await controller.dispose();
  } catch (_) {
    // Same as above: disposal is best-effort during dev hot restart.
  }
}
