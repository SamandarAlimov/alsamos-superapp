import '../../../core/data/base_repository.dart';
import '../../../core/data/supabase_data_source.dart';

/// A single item saved into a highlight (a snapshot of a former story).
class HighlightItem {
  final String id;
  final String highlightId;
  final String storyId;
  final String mediaUrl;
  final String mediaType;
  final String? caption;
  final DateTime createdAt;

  HighlightItem({
    required this.id,
    required this.highlightId,
    required this.storyId,
    required this.mediaUrl,
    required this.mediaType,
    this.caption,
    required this.createdAt,
  });

  factory HighlightItem.fromMap(Map<String, dynamic> m) => HighlightItem(
        id: m['id'] as String,
        highlightId: m['highlight_id'] as String? ?? '',
        storyId: m['story_id'] as String? ?? '',
        mediaUrl: m['media_url'] as String? ?? '',
        mediaType: m['media_type'] as String? ?? 'image',
        caption: m['caption'] as String?,
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
      );
}

/// A saved story highlight (web `useStoryHighlights` parity).
class StoryHighlight {
  final String id;
  final String userId;
  final String name;
  final String? coverUrl;
  final List<HighlightItem> items;
  final DateTime createdAt;

  StoryHighlight({
    required this.id,
    required this.userId,
    required this.name,
    this.coverUrl,
    this.items = const [],
    required this.createdAt,
  });

  int get itemCount => items.length;

  StoryHighlight copyWith({
    String? name,
    String? coverUrl,
    List<HighlightItem>? items,
  }) =>
      StoryHighlight(
        id: id,
        userId: userId,
        name: name ?? this.name,
        coverUrl: coverUrl ?? this.coverUrl,
        items: items ?? this.items,
        createdAt: createdAt,
      );

  factory StoryHighlight.fromMap(
    Map<String, dynamic> m, {
    List<HighlightItem>? items,
  }) =>
      StoryHighlight(
        id: m['id'] as String,
        userId: m['user_id'] as String? ?? '',
        name: m['name'] as String? ?? '',
        coverUrl: m['cover_url'] as String?,
        items: items ?? const [],
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
      );
}

/// Highlights data access, ported from web `useStoryHighlights.ts`.
class StoryHighlightsRepository extends BaseRepository {
  final SupabaseDataSource _db;

  const StoryHighlightsRepository({
    SupabaseDataSource db = const SupabaseDataSource(),
  }) : _db = db;

  /// Fetch all highlights for a user plus their items (single round trip via nested select).
  Future<List<StoryHighlight>> fetchHighlights(String userId) =>
      guard('fetchHighlights', () async {
        final data = await _db
            .table('story_highlights')
            .select('*, items:story_highlight_items(*)')
            .eq('user_id', userId)
            .order('created_at', ascending: false);
        return (data as List).map<StoryHighlight>((row) {
          final m = Map<String, dynamic>.from(row as Map);
          final rawItems = (m['items'] as List?) ?? const [];
          final items = rawItems
              .map(
                (it) => HighlightItem.fromMap(
                  Map<String, dynamic>.from(it as Map),
                ),
              )
              .toList()
            ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
          return StoryHighlight.fromMap(m, items: items);
        }).toList();
      });

  Future<StoryHighlight?> createHighlight({
    required String userId,
    required String name,
    String? coverUrl,
  }) =>
      guard('createHighlight', () async {
        final data = await _db
            .table('story_highlights')
            .insert({
              'user_id': userId,
              'name': name,
              'cover_url': coverUrl,
            })
            .select()
            .maybeSingle();
        return data != null
            ? StoryHighlight.fromMap(Map<String, dynamic>.from(data))
            : null;
      });

  Future<void> updateHighlight(
    String highlightId, {
    String? name,
    String? coverUrl,
  }) =>
      guard('updateHighlight', () async {
        final updates = <String, dynamic>{};
        if (name != null) updates['name'] = name;
        if (coverUrl != null) updates['cover_url'] = coverUrl;
        if (updates.isEmpty) return;
        await _db
            .table('story_highlights')
            .update(updates)
            .eq('id', highlightId);
      });

  Future<void> deleteHighlight(String highlightId) =>
      guard('deleteHighlight', () async {
        await _db.table('story_highlights').delete().eq('id', highlightId);
      });

  Future<void> addStoryToHighlight({
    required String highlightId,
    required String storyId,
    required String mediaUrl,
    required String mediaType,
    String? caption,
  }) =>
      guard('addStoryToHighlight', () async {
        await _db.table('story_highlight_items').insert({
          'highlight_id': highlightId,
          'story_id': storyId,
          'media_url': mediaUrl,
          'media_type': mediaType,
          'caption': caption,
        });
      });

  Future<void> removeHighlightItem(String itemId) =>
      guard('removeHighlightItem', () async {
        await _db.table('story_highlight_items').delete().eq('id', itemId);
      });

  Future<List<Map<String, dynamic>>> fetchArchivedStories(String userId) =>
      guard('fetchArchivedStories', () async {
        final data = await _db
            .table('stories')
            .select('*')
            .eq('user_id', userId)
            .order('created_at', ascending: false);
        final now = DateTime.now();
        return (data as List)
            .map((m) => Map<String, dynamic>.from(m as Map))
            .where((m) {
          final exp = DateTime.tryParse(m['expires_at'] as String? ?? '');
          return exp != null && exp.isBefore(now);
        }).toList();
      });
}
