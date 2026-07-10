import '../../../core/supabase/supabase_client.dart';
import 'notification_model.dart';

/// Ported 1:1 from web useNotifications.ts.
class NotificationsRepository {
  const NotificationsRepository();

  String? _actorId(Map<dynamic, dynamic> data) {
    final id = data['liker_id'] ??
        data['commenter_id'] ??
        data['follower_id'] ??
        data['mentioner_id'] ??
        data['actor_id'] ??
        data['inviter_id'] ??
        data['collaborator_id'];
    return id?.toString();
  }

  Future<List<AppNotification>> fetch(String userId) async {
    final data = await supabase
        .from('notifications')
        .select('*')
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(50);

    final actorIds = <String>{};
    final postIds = <String>{};
    for (final n in data) {
      final d = (n['data'] as Map?) ?? {};
      final actorId = _actorId(d);
      if (actorId != null) actorIds.add(actorId);
      final postId = d['post_id'];
      if (postId != null) postIds.add(postId.toString());
    }

    final profileMap = <String, NotificationActor>{};
    if (actorIds.isNotEmpty) {
      final profiles = await supabase
          .from('profiles')
          .select('id, username, display_name, avatar_url')
          .inFilter('id', actorIds.toList());
      for (final p in profiles) {
        profileMap[p['id'] as String] = NotificationActor.fromMap(p);
      }
    }

    final postMap = <String,
        ({
      List<String> urls,
      String? thumb,
      String? mediaType,
      String? postType,
      String? content,
    })>{};
    if (postIds.isNotEmpty) {
      final posts = await supabase
          .from('posts')
          .select('id, media_urls, media_type, content')
          .inFilter('id', postIds.toList());
      for (final p in posts) {
        final urls =
            (p['media_urls'] as List?)?.map((e) => e.toString()).toList() ??
                const <String>[];
        final mediaType = p['media_type'] as String?;
        final content = p['content'] as String?;
        postMap[p['id'] as String] = (
          urls: urls,
          thumb: urls.isNotEmpty ? urls.first : null,
          mediaType: mediaType,
          postType: mediaType,
          content: content,
        );
      }
    }

    return data.map<AppNotification>((n) {
      final d = (n['data'] as Map?) ?? {};
      final actorId = _actorId(d);
      final postId = d['post_id']?.toString();
      final postData = postId != null ? postMap[postId] : null;
      return AppNotification(
        id: n['id'] as String,
        type: n['type'] as String,
        title: n['title'] as String,
        body: n['body'] as String?,
        isRead: (n['is_read'] as bool?) ?? false,
        createdAt: DateTime.parse(n['created_at'] as String).toLocal(),
        actor: actorId != null ? profileMap[actorId] : null,
        postThumb: postData?.thumb,
        postMediaUrls: postData?.urls ?? const <String>[],
        mediaType: postData?.mediaType,
        postId: postId,
        postType: d['post_type']?.toString() ?? postData?.postType,
        postContent: postData?.content,
        postExists: postId == null || postData != null,
      );
    }).toList();
  }

  Future<void> markAsRead(String id) async {
    await supabase.from('notifications').update({'is_read': true}).eq('id', id);
  }

  Future<void> markAllAsRead(String userId) async {
    await supabase
        .from('notifications')
        .update({'is_read': true})
        .eq('user_id', userId)
        .eq('is_read', false);
  }

  Future<void> delete(String id) async {
    await supabase.from('notifications').delete().eq('id', id);
  }
}
