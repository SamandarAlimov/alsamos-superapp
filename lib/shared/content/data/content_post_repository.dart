import 'dart:async';
import 'dart:developer' as developer;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/data/base_repository.dart';
import '../../../core/data/supabase_data_source.dart';
import 'content_posts_cache.dart';
import '../models/content_item.dart';

class ContentFeedPage {
  final List<ContentItem> items;
  final bool fromCache;
  final bool hasMore;

  const ContentFeedPage({
    required this.items,
    required this.fromCache,
    required this.hasMore,
  });
}

class ContentRealtimeEvent {
  final PostgresChangeEvent event;
  final ContentItem? item;
  final String? id;

  const ContentRealtimeEvent({
    required this.event,
    this.item,
    this.id,
  });
}

class ContentRealtimeSubscription {
  final SupabaseDataSource _db;
  final RealtimeChannel _channel;

  const ContentRealtimeSubscription(this._db, this._channel);

  Future<void> dispose() => _db.removeChannel(_channel);
}

class ContentPostRepository extends BaseRepository {
  static const defaultPageSize = 20;

  // Keep this profile join byte-for-byte aligned with current PostsRepository.
  static const postSelect = '''
    *,
    profile:profiles!posts_user_id_fkey (id, username, display_name, avatar_url, is_verified)
  ''';

  final SupabaseDataSource _db;
  final ContentPostsCache _cache;

  ContentPostRepository({
    SupabaseDataSource db = const SupabaseDataSource(),
    ContentPostsCache? cache,
  })  : _db = db,
        _cache = cache ?? ContentPostsCache();

  Future<ContentFeedPage> fetchPublicFeed({
    int page = 0,
    int pageSize = defaultPageSize,
    bool preferCache = true,
  }) =>
      guard('fetchPublicFeed', () async {
        final offset = page * pageSize;
        if (preferCache && page == 0) {
          final cached = await _cache.loadFeed(limit: pageSize, offset: offset);
          if (cached.isNotEmpty) {
            unawaited(_refreshPublicFeed(page: page, pageSize: pageSize));
            return ContentFeedPage(
              items: cached,
              fromCache: true,
              hasMore: cached.length == pageSize,
            );
          }
        }

        final items = await _loadPublicFeed(page: page, pageSize: pageSize);
        await _cache.saveFeed(items);
        return ContentFeedPage(
          items: items,
          fromCache: false,
          hasMore: items.length == pageSize,
        );
      });

  Future<ContentItem?> fetchPostById(String id) =>
      guard('fetchPostById', () async {
        final row = await _db
            .table('posts')
            .select(postSelect)
            .eq('id', id)
            .maybeSingle();
        if (row == null) return null;
        final item = ContentItem.fromPostMap(Map<String, dynamic>.from(row));
        final enriched = (await _attachCollaborators(
          await _attachProductTags([item]),
        ))
            .first;
        await _trySavePost(enriched);
        return enriched;
      });

  Future<ContentItem> createPost(ContentItem draft) =>
      guard('createPost', () async {
        final authorId =
            draft.authorId.isEmpty ? requireUserId() : draft.authorId;
        final normalizedDraft = draft.copyWith(authorId: authorId);
        final insert = normalizedDraft.toPostInsertMap();
        final publishHashtags =
            _stringList(insert['hashtags'] ?? insert['tags']);
        final row = await _insertPost(insert);
        final created =
            ContentItem.fromPostMap(Map<String, dynamic>.from(row)).copyWith(
          hashtags: publishHashtags,
          productTags: normalizedDraft.productTags,
        );
        await _trySyncSideTables(
          created.id,
          publishHashtags,
          normalizedDraft.productTags,
        );
        await _trySavePost(created);
        return created;
      });

  Future<ContentItem?> updatePost(
    String id, {
    String? text,
    List<String>? hashtags,
    List<String>? productTags,
    List<String>? effectsUsed,
    ContentLocation? location,
  }) =>
      guard('updatePost', () async {
        final update = <String, dynamic>{
          if (text != null) 'content': text,
          if (hashtags != null) 'hashtags': hashtags,
          if (hashtags != null) 'tags': hashtags,
          if (effectsUsed != null) 'effects_used': effectsUsed,
          if (location != null) ...location.toPostMap(),
          'updated_at': DateTime.now().toIso8601String(),
        };
        final row = await _db
            .table('posts')
            .update(update)
            .eq('id', id)
            .select(postSelect)
            .maybeSingle();
        if (row == null) return null;
        final item = ContentItem.fromPostMap(Map<String, dynamic>.from(row));
        await _trySyncSideTables(
            id, hashtags ?? item.hashtags, productTags ?? item.productTags);
        await _trySavePost(item);
        return item;
      });

  Future<void> deletePost(String id) => guard('deletePost', () async {
        await _db.table('posts').delete().eq('id', id);
        await _cache.removePost(id);
      });

  ContentRealtimeSubscription subscribePublicFeed(
    void Function(ContentRealtimeEvent event) onEvent,
  ) {
    final channel = _db.channel('content-posts-public');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'posts',
          callback: (payload) {
            final newRecord = payload.newRecord;
            final oldRecord = payload.oldRecord;
            final item = newRecord.isEmpty
                ? null
                : ContentItem.fromPostMap(Map<String, dynamic>.from(newRecord));
            final id = item?.id ?? oldRecord['id']?.toString();
            if (item != null) {
              unawaited(_trySavePost(item));
            } else if (id != null) {
              unawaited(_cache.removePost(id));
            }
            onEvent(ContentRealtimeEvent(
                event: payload.eventType, item: item, id: id));
          },
        )
        .subscribe();
    return ContentRealtimeSubscription(_db, channel);
  }

  Future<void> _refreshPublicFeed({
    required int page,
    required int pageSize,
  }) async {
    try {
      final items = await _loadPublicFeed(page: page, pageSize: pageSize);
      await _cache.saveFeed(items);
    } catch (_) {
      // Cache-first refresh is best-effort; foreground fetches surface errors.
    }
  }

  Future<List<ContentItem>> _loadPublicFeed({
    required int page,
    required int pageSize,
  }) async {
    final from = page * pageSize;
    final to = from + pageSize - 1;
    final rows = await _db
        .table('posts')
        .select(postSelect)
        .eq('visibility', 'public')
        .order('is_pinned', ascending: false)
        .order('created_at', ascending: false)
        .range(from, to);
    final items = (rows as List)
        .map((row) =>
            ContentItem.fromPostMap(Map<String, dynamic>.from(row as Map)))
        .toList(growable: false);
    return _attachCollaborators(await _attachProductTags(items));
  }

  Future<List<ContentItem>> _attachProductTags(List<ContentItem> items) async {
    if (items.isEmpty) return items;
    try {
      final rows = await _db
          .table('post_product_tags')
          .select('post_id, product_id')
          .inFilter('post_id', items.map((item) => item.id).toList());
      final tagsByPost = <String, List<String>>{};
      for (final row in rows as List) {
        final map = Map<String, dynamic>.from(row as Map);
        final postId = map['post_id']?.toString();
        final productId = map['product_id']?.toString();
        if (postId == null || productId == null || productId.isEmpty) {
          continue;
        }
        tagsByPost.putIfAbsent(postId, () => <String>[]).add(productId);
      }
      return items
          .map((item) => item.copyWith(
                productTags: tagsByPost[item.id] ?? item.productTags,
              ))
          .toList(growable: false);
    } on PostgrestException catch (error) {
      if (_isOptionalContentSchemaError(error)) return items;
      rethrow;
    }
  }

  Future<List<ContentItem>> _attachCollaborators(
    List<ContentItem> items,
  ) async {
    if (items.isEmpty) return items;
    try {
      final itemIds = items.map((item) => item.id).toList(growable: false);
      final rows = await _db
          .table('post_collaborators')
          .select('post_id, user_id')
          .inFilter('post_id', itemIds)
          .eq('status', 'accepted');

      final userIdsByPost = <String, List<String>>{};
      final userIds = <String>{};
      for (final row in rows as List) {
        final map = Map<String, dynamic>.from(row as Map);
        final postId = map['post_id']?.toString();
        final userId = map['user_id']?.toString();
        if (postId == null ||
            userId == null ||
            postId.isEmpty ||
            userId.isEmpty) {
          continue;
        }
        userIdsByPost.putIfAbsent(postId, () => <String>[]).add(userId);
        userIds.add(userId);
      }
      if (userIds.isEmpty) return items;

      final profileRows = await _db
          .table('profiles')
          .select('id, username, display_name, avatar_url, is_verified')
          .inFilter('id', userIds.toList(growable: false));
      final collaboratorsByUser = <String, ContentCollaborator>{};
      for (final row in profileRows as List) {
        final collaborator = ContentCollaborator.fromMap(
          Map<String, dynamic>.from(row as Map),
        );
        if (collaborator.id.isNotEmpty) {
          collaboratorsByUser[collaborator.id] = collaborator;
        }
      }

      return items.map((item) {
        final collaborators = (userIdsByPost[item.id] ?? const <String>[])
            .map((userId) => collaboratorsByUser[userId])
            .whereType<ContentCollaborator>()
            .toList(growable: false);
        if (collaborators.isEmpty) return item;

        final raw = Map<String, dynamic>.from(item.raw);
        raw['post_collaborators'] =
            collaborators.map((item) => item.toMap()).toList(growable: false);
        return item.copyWith(collaborators: collaborators, raw: raw);
      }).toList(growable: false);
    } on PostgrestException catch (error) {
      if (_isOptionalContentSchemaError(error)) return items;
      rethrow;
    }
  }

  Future<void> _syncSideTables(
    String postId,
    List<String> hashtags,
    List<String> productTags,
  ) async {
    await _db.table('post_hashtags').delete().eq('post_id', postId);
    if (hashtags.isNotEmpty) {
      await _db.table('post_hashtags').insert(
            hashtags
                .map((tag) => {
                      'post_id': postId,
                      'hashtag': _normalizeHashtag(tag),
                    })
                .where((row) => (row['hashtag'] as String).isNotEmpty)
                .toList(growable: false),
          );
    }

    await _db.table('post_product_tags').delete().eq('post_id', postId);
    if (productTags.isNotEmpty) {
      await _db.table('post_product_tags').insert(
            productTags
                .map((productId) => {
                      'post_id': postId,
                      'product_id': productId,
                      'tagged_by': requireUserId(),
                    })
                .toList(growable: false),
          );
    }
  }

  String _normalizeHashtag(String tag) {
    return tag.trim().replaceFirst(RegExp(r'^#'), '').toLowerCase();
  }

  List<String> _stringList(dynamic value) {
    if (value is List) {
      return value
          .map((item) => item.toString())
          .where((item) => item.trim().isNotEmpty)
          .toList(growable: false);
    }
    if (value is String && value.trim().isNotEmpty) {
      return [value.trim()];
    }
    return const [];
  }

  Future<Map<String, dynamic>> _insertPost(Map<String, dynamic> insert) async {
    final payload = Map<String, dynamic>.from(insert);
    final removed = <String>{};
    var select = postSelect;
    for (var attempt = 0; attempt < 12; attempt++) {
      try {
        _logInsertAttempt(payload: payload, select: select, attempt: attempt);
        final row =
            await _db.table('posts').insert(payload).select(select).single();
        return Map<String, dynamic>.from(row as Map);
      } on PostgrestException catch (error) {
        _logPostgrestError('insertPost', error);
        final column = _missingSchemaColumn(error);
        if (column == null || removed.contains(column)) {
          if (select != '*' && _isProfileEmbedSchemaError(error)) {
            select = '*';
            developer.log(
              '[ContentPostRepository.insertPost] profile embed unavailable; retrying with select(*)',
              name: 'repository',
              level: 900,
            );
            continue;
          }
          rethrow;
        }
        _removeOptionalColumn(payload, column);
        removed.add(column);
      }
    }
    throw StateError('Unable to create post after schema fallback');
  }

  Future<void> _trySyncSideTables(
    String postId,
    List<String> hashtags,
    List<String> productTags,
  ) async {
    try {
      await _syncSideTables(postId, hashtags, productTags);
    } catch (error, stackTrace) {
      developer.log(
        '[ContentPostRepository.syncSideTables] skipped post=$postId hashtags=${hashtags.length} products=${productTags.length}: $error',
        name: 'repository',
        error: error,
        stackTrace: stackTrace,
        level: 1000,
      );
    }
  }

  Future<void> _trySavePost(ContentItem item) async {
    try {
      await _cache.savePost(item);
    } catch (error, stackTrace) {
      developer.log(
        '[ContentPostRepository.cache] savePost skipped: $error',
        name: 'repository',
        error: error,
        stackTrace: stackTrace,
        level: 900,
      );
    }
  }

  String? _missingSchemaColumn(PostgrestException error) {
    if (error.code != 'PGRST204') return null;
    return RegExp(r"Could not find the '([^']+)' column")
        .firstMatch(error.message)
        ?.group(1);
  }

  bool _isOptionalContentSchemaError(PostgrestException error) {
    return error.code == '42P01' ||
        error.code == 'PGRST204' ||
        error.message.contains('post_hashtags') ||
        error.message.contains('post_product_tags') ||
        error.message.contains('post_collaborators');
  }

  bool _isProfileEmbedSchemaError(PostgrestException error) {
    final value =
        '${error.code} ${error.message} ${error.details}'.toLowerCase();
    return value.contains('relationship') ||
        value.contains('posts_user_id_fkey') ||
        value.contains('profiles') ||
        value.contains('schema cache');
  }

  void _logInsertAttempt({
    required Map<String, dynamic> payload,
    required String select,
    required int attempt,
  }) {
    developer.log(
      '[ContentPostRepository.insertPost] attempt=$attempt select=${select == '*' ? '*' : 'postSelect'} keys=${payload.keys.toList()} visibility=${payload['visibility']} mediaType=${payload['media_type']}',
      name: 'repository',
      level: 800,
    );
  }

  void _logPostgrestError(String op, PostgrestException error) {
    developer.log(
      '[ContentPostRepository.$op] PostgrestException code=${error.code} message=${error.message} details=${error.details} hint=${error.hint}',
      name: 'repository',
      error: error,
      level: 1000,
    );
  }

  void _removeOptionalColumn(Map<String, dynamic> payload, String column) {
    if (column.startsWith('location_')) {
      payload
        ..remove('location_lat')
        ..remove('location_lng')
        ..remove('location_name')
        ..remove('location_address')
        ..remove('location_geohash');
      return;
    }
    payload.remove(column);
  }
}
