import 'package:alsamos_flutter/features/messages/presentation/widgets/media_gallery_viewer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MediaGalleryItem detects playable video types', () {
    expect(const MediaGalleryItem(url: 'u', type: 'image').isVideo, isFalse);
    expect(const MediaGalleryItem(url: 'u', type: 'video').isVideo, isTrue);
    expect(
        const MediaGalleryItem(url: 'u', type: 'video_note').isVideo, isTrue);
  });
}
