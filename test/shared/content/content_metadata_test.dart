import 'package:alsamos_flutter/shared/content/utils/content_metadata.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('stripPostMetadata', () {
    test('removes music metadata and keeps the caption', () {
      const content =
          '[MUSIC]{"title":"Track","audioUrl":"https://example.com/a.mp3"}[/MUSIC]\nCaption';

      expect(stripPostMetadata(content), 'Caption');
    });

    test('removes poll metadata and keeps the caption', () {
      const content =
          '[POLL]{"question":"Choose","options":["A","B"]}[/POLL]\nCaption';

      expect(stripPostMetadata(content), 'Caption');
    });

    test('removes mixed metadata blocks in any supported order', () {
      const content =
          '[POLL]{"question":"Choose"}[/POLL]\n[MUSIC]{"title":"Track"}[/MUSIC]\nCaption';

      expect(stripPostMetadata(content), 'Caption');
    });

    test('returns empty text for metadata-only content', () {
      const content = '[MUSIC]{"title":"Track"}[/MUSIC]';

      expect(stripPostMetadata(content), isEmpty);
    });

    test('removes aspect metadata from reel captions', () {
      const content = '[ASPECT:9:16]\nReel caption';

      expect(stripPostMetadata(content), 'Reel caption');
    });
  });
}
