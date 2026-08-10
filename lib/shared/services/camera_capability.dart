import 'package:flutter/foundation.dart';

class CameraCapability {
  const CameraCapability._();

  static bool get supportsImagePickerCapture {
    if (kIsWeb) return true;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  static bool get supportsCameraPreview {
    if (kIsWeb) return true;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  static bool get shouldUseFilePickerForGallery {
    return !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.macOS);
  }

  static String get unsupportedCaptureMessage =>
      'Bu qurilmada kamera to\'g\'ridan-to\'g\'ri qo\'llanmaydi. Gallery yoki fayldan tanlang.';

  static String get unsupportedLivePreviewMessage =>
      'Bu platformada kamera preview qo\'llanmaydi. Live uchun Android, iOS yoki Web’dan foydalaning.';
}
