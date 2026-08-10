import 'package:alsamos_flutter/features/messages/data/services/media_settings_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('auto-download policy separates wifi and mobile media types', () {
    const policy = MediaDownloadPolicy(
      imagesWifi: true,
      imagesMobile: false,
      videosWifi: false,
      videosMobile: true,
      filesWifi: false,
      filesMobile: false,
    );

    expect(policy.allows('image', [ConnectivityResult.wifi]), isTrue);
    expect(policy.allows('image', [ConnectivityResult.mobile]), isFalse);
    expect(policy.allows('video', [ConnectivityResult.mobile]), isTrue);
    expect(policy.allows('file', [ConnectivityResult.wifi]), isFalse);
  });

  test('albums follow image auto-download policy', () {
    const policy = MediaDownloadPolicy(imagesWifi: true, imagesMobile: false);

    expect(policy.allows('album', [ConnectivityResult.ethernet]), isTrue);
    expect(policy.allows('album', [ConnectivityResult.mobile]), isFalse);
  });
}
