import 'package:alsamos_flutter/features/home/data/models/post_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Post parses basic fields from map', () {
    final post = Post.fromMap({
      'id': 'post-1',
      'user_id': 'user-1',
      'content': 'Assalomu alaykum',
      'created_at': '2026-07-11T00:00:00Z',
      'likes_count': 10,
      'comments_count': 5,
    });

    expect(post.id, 'post-1');
    expect(post.content, 'Assalomu alaykum');
    expect(post.likesCount, 10);
    expect(post.copyWith(likesCount: 3).likesCount, 3);
  });
}
