import 'package:flutter_test/flutter_test.dart';
import 'package:alsamos_flutter/shared/content/models/content_item.dart';
import 'package:alsamos_flutter/shared/content/models/content_media.dart';

void main() {
  group('ContentItem.fromPostMap', () {
    test('maps legacy posts media_urls and tags into unified content fields',
        () {
      final item = ContentItem.fromPostMap({
        'id': 'post-1',
        'user_id': 'user-1',
        'content': 'Hello #alsamos',
        'media_urls': ['https://cdn.test/a.jpg', 'https://cdn.test/b.jpg'],
        'media_type': 'image',
        'tags': ['alsamos'],
        'likes_count': 4,
        'comments_count': 2,
        'shares_count': 1,
        'views_count': 9,
        'visibility': 'public',
        'created_at': '2026-07-18T09:00:00Z',
      });

      expect(item.id, 'post-1');
      expect(item.authorId, 'user-1');
      expect(item.mediaUrl, 'https://cdn.test/a.jpg');
      expect(item.media, hasLength(2));
      expect(item.media.first.type, ContentMediaType.image);
      expect(item.hashtags, ['alsamos']);
      expect(item.likesCount, 4);
      expect(item.commentsCount, 2);
      expect(item.sharesCount, 1);
      expect(item.viewsCount, 9);
    });

    test('maps embedded product tag rows to product id list', () {
      final item = ContentItem.fromPostMap({
        'id': 'post-2',
        'user_id': 'user-1',
        'content': 'Shoppable post',
        'post_product_tags': [
          {
            'product_id': 'product-1',
            'position': {'x': 0.4, 'y': 0.7}
          },
          {'product_id': 'product-2'},
        ],
        'created_at': '2026-07-18T09:00:00Z',
      });

      expect(item.productTags, ['product-1', 'product-2']);
    });
  });
}
