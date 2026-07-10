import '../../../core/supabase/supabase_client.dart';

/// Ported from web pages/CreatePage.tsx + useCreatePost.
class CreateRepository {
  const CreateRepository();

  Future<void> createPost({
    required String userId,
    required String content,
    List<String> mediaUrls = const [],
    String? mediaType,
    String visibility = 'public',
  }) async {
    await supabase.from('posts').insert({
      'user_id': userId,
      'content': content,
      'media_urls': mediaUrls,
      'media_type': mediaType,
      'visibility': visibility,
    });
  }
}
