import 'dart:convert';

import '../data/content_adapter.dart';
import 'content_media.dart';

enum ContentType {
  text,
  image,
  video,
  album,
  reel,
  live,
  marketplace,
  location
}

class ContentLocation {
  final double latitude;
  final double longitude;
  final String? name;
  final String? address;
  final String? geohash;

  const ContentLocation({
    required this.latitude,
    required this.longitude,
    this.name,
    this.address,
    this.geohash,
  });

  factory ContentLocation.fromPostMap(Map<String, dynamic> map) {
    final latitude = _doubleOrNull(
      map['location_lat'] ?? map['latitude'] ?? map['lat'],
    );
    final longitude = _doubleOrNull(
      map['location_lng'] ??
          map['location_lon'] ??
          map['longitude'] ??
          map['lng'],
    );
    if (latitude == null || longitude == null) {
      return const ContentLocation(latitude: 0, longitude: 0);
    }
    return ContentLocation(
      latitude: latitude,
      longitude: longitude,
      name: map['location_name']?.toString(),
      address: map['location_address']?.toString(),
      geohash: map['location_geohash']?.toString(),
    );
  }

  bool get isEmpty => latitude == 0 && longitude == 0 && name == null;

  Map<String, dynamic> toPostMap() {
    return {
      'location_lat': latitude,
      'location_lng': longitude,
      if (name != null) 'location_name': name,
      if (address != null) 'location_address': address,
      if (geohash != null) 'location_geohash': geohash,
    };
  }
}

class ContentCollaborator {
  final String id;
  final String? username;
  final String? displayName;
  final String? avatarUrl;
  final bool isVerified;

  const ContentCollaborator({
    required this.id,
    this.username,
    this.displayName,
    this.avatarUrl,
    this.isVerified = false,
  });

  factory ContentCollaborator.fromMap(Map<String, dynamic> map) =>
      ContentCollaborator(
        id: map['id']?.toString() ?? map['user_id']?.toString() ?? '',
        username: map['username']?.toString(),
        displayName: map['display_name']?.toString(),
        avatarUrl: map['avatar_url']?.toString(),
        isVerified: map['is_verified'] == true,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        if (username != null) 'username': username,
        if (displayName != null) 'display_name': displayName,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
        'is_verified': isVerified,
      };
}

class ContentItem {
  final String id;
  final String authorId;
  final ContentType type;
  final String? text;
  final String? mediaUrl;
  final String? thumbnailUrl;
  final List<ContentMedia> media;
  final ContentLocation? location;
  final List<String> hashtags;
  final List<String> productTags;
  final List<ContentCollaborator> collaborators;
  final List<String> effectsUsed;
  final String visibility;
  final int likesCount;
  final int commentsCount;
  final int sharesCount;
  final int viewsCount;
  final bool isPinned;
  final bool isLikedByMe;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final Map<String, dynamic> raw;

  const ContentItem({
    required this.id,
    required this.authorId,
    required this.type,
    required this.createdAt,
    this.text,
    this.mediaUrl,
    this.thumbnailUrl,
    this.media = const [],
    this.location,
    this.hashtags = const [],
    this.productTags = const [],
    this.collaborators = const [],
    this.effectsUsed = const [],
    this.visibility = 'public',
    this.likesCount = 0,
    this.commentsCount = 0,
    this.sharesCount = 0,
    this.viewsCount = 0,
    this.isPinned = false,
    this.isLikedByMe = false,
    this.updatedAt,
    this.raw = const {},
  });

  factory ContentItem.fromPostMap(Map<String, dynamic> map) {
    map = normalizePostMap(map);
    final location = ContentLocation.fromPostMap(map);
    final media = _contentMediaFromPostMap(map);
    return ContentItem(
      id: map['id']?.toString() ?? '',
      authorId: (map['user_id'] ?? map['author_id'])?.toString() ?? '',
      type: _contentTypeFromPost(map),
      text: (map['content'] ?? map['caption'] ?? map['text'])?.toString(),
      mediaUrl: (map['media_url'] ?? map['image_url'] ?? map['video_url'])
              ?.toString() ??
          (media.isEmpty ? null : media.first.url),
      thumbnailUrl: (map['thumbnail_url'] ?? map['thumb_url'])?.toString(),
      media: media,
      location: location.isEmpty ? null : location,
      hashtags: _stringList(map['hashtags'] ?? map['tags']),
      productTags: _productTagsFromPostMap(map),
      collaborators: _collaboratorsFromPostMap(map),
      effectsUsed: _stringList(map['effects_used']),
      visibility: map['visibility']?.toString() ?? 'public',
      likesCount: _intOrZero(map['likes_count']),
      commentsCount: _intOrZero(map['comments_count']),
      sharesCount: _intOrZero(map['shares_count']),
      viewsCount: _intOrZero(map['views_count'] ?? map['view_count']),
      isPinned: map['is_pinned'] == true,
      isLikedByMe: map['is_liked_by_me'] == true,
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: DateTime.tryParse(map['updated_at']?.toString() ?? ''),
      raw: Map<String, dynamic>.from(map),
    );
  }

  Map<String, dynamic> toPostInsertMap() {
    final normalizedTags = _mergeHashtags(hashtags, text);
    final values = <String, dynamic>{
      'user_id': authorId,
      'content': text ?? '',
      'content_type': type.name,
      'visibility': visibility,
      'hashtags': normalizedTags,
      'tags': normalizedTags,
      'effects_used': effectsUsed,
      if (mediaUrl != null) 'media_url': mediaUrl,
      if (thumbnailUrl != null) 'thumbnail_url': thumbnailUrl,
      if (media.isNotEmpty) 'media': media.map((e) => e.toJson()).toList(),
    };
    for (final key in const [
      'media_urls',
      'media_type',
      'poll_data',
      'source',
      'source_id',
    ]) {
      final rawValue = raw[key];
      if (rawValue != null) {
        values[key] = rawValue;
      }
    }
    if (location != null) values.addAll(location!.toPostMap());
    return values;
  }

  Map<String, dynamic> toEditMap() => {
        'content': text ?? '',
        'hashtags': hashtags,
        'visibility': visibility,
        if (location != null) 'location_name': location!.name,
        if (location != null) 'location_lat': location!.latitude,
        if (location != null) 'location_lng': location!.longitude,
        if (location != null) 'location_address': location!.address,
        if (location != null) 'location_geohash': location!.geohash,
      };

  ContentItem copyWith({
    String? id,
    String? authorId,
    ContentType? type,
    String? text,
    String? mediaUrl,
    String? thumbnailUrl,
    List<ContentMedia>? media,
    ContentLocation? location,
    List<String>? hashtags,
    List<String>? productTags,
    List<ContentCollaborator>? collaborators,
    List<String>? effectsUsed,
    String? visibility,
    int? likesCount,
    int? commentsCount,
    int? sharesCount,
    int? viewsCount,
    bool? isPinned,
    bool? isLikedByMe,
    DateTime? createdAt,
    DateTime? updatedAt,
    Map<String, dynamic>? raw,
  }) {
    return ContentItem(
      id: id ?? this.id,
      authorId: authorId ?? this.authorId,
      type: type ?? this.type,
      text: text ?? this.text,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      media: media ?? this.media,
      location: location ?? this.location,
      hashtags: hashtags ?? this.hashtags,
      productTags: productTags ?? this.productTags,
      collaborators: collaborators ?? this.collaborators,
      effectsUsed: effectsUsed ?? this.effectsUsed,
      visibility: visibility ?? this.visibility,
      likesCount: likesCount ?? this.likesCount,
      commentsCount: commentsCount ?? this.commentsCount,
      sharesCount: sharesCount ?? this.sharesCount,
      viewsCount: viewsCount ?? this.viewsCount,
      isPinned: isPinned ?? this.isPinned,
      isLikedByMe: isLikedByMe ?? this.isLikedByMe,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      raw: raw ?? this.raw,
    );
  }
}

List<String> _mergeHashtags(List<String> explicit, String? content) {
  final tags = <String>{
    for (final tag in explicit) _normalizeHashtag(tag),
  }..removeWhere((tag) => tag.isEmpty);
  final text = content ?? '';
  for (final match in RegExp(r'#([A-Za-z0-9_]+)').allMatches(text)) {
    final tag = match.group(1);
    if (tag != null) tags.add(_normalizeHashtag(tag));
  }
  return tags.toList(growable: false);
}

String _normalizeHashtag(String tag) =>
    tag.trim().replaceFirst(RegExp(r'^#'), '').toLowerCase();

ContentType _contentTypeFromPost(Map<String, dynamic> map) {
  final value =
      (map['content_type'] ?? map['type'] ?? map['media_type'])?.toString();
  return ContentType.values.firstWhere(
    (type) => type.name == value,
    orElse: () {
      if (map['video_url'] != null || map['media_type'] == 'video') {
        return ContentType.video;
      }
      if (map['media_url'] != null || map['image_url'] != null) {
        return ContentType.image;
      }
      if (map['location_lat'] != null || map['latitude'] != null) {
        return ContentType.location;
      }
      return ContentType.text;
    },
  );
}

List<String> _stringList(dynamic value) {
  if (value == null) return const [];
  final decoded =
      value is String && value.startsWith('[') ? jsonDecode(value) : value;
  if (decoded is List) {
    return decoded
        .map((e) => e.toString())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }
  if (decoded is String && decoded.trim().isNotEmpty) return [decoded.trim()];
  return const [];
}

List<ContentMedia> _contentMediaFromPostMap(Map<String, dynamic> map) {
  final explicit = ContentMedia.listFrom(map['media']);
  if (explicit.isNotEmpty) return explicit;

  final urls = _stringList(
    map['media_urls'] ??
        map['media_url'] ??
        map['image_url'] ??
        map['video_url'],
  );
  if (urls.isEmpty) return const [];

  final mediaType = _mediaTypeFromPost(map['media_type']?.toString(), urls);
  return [
    for (var i = 0; i < urls.length; i++)
      ContentMedia(
        id: 'media-$i',
        type: mediaType,
        url: urls[i],
        thumbnailUrl: i == 0
            ? (map['thumbnail_url'] ?? map['thumb_url'])?.toString()
            : null,
      ),
  ];
}

ContentMediaType _mediaTypeFromPost(String? mediaType, List<String> urls) {
  final normalized = mediaType?.toLowerCase();
  if (normalized == 'video' || normalized == 'reel') {
    return ContentMediaType.video;
  }
  if (normalized == 'audio' || normalized == 'voice') {
    return ContentMediaType.audio;
  }
  if (normalized == 'document' || normalized == 'file') {
    return ContentMediaType.document;
  }
  if (normalized == 'location') {
    return ContentMediaType.location;
  }
  final first = urls.isEmpty ? '' : urls.first.toLowerCase();
  if (RegExp(r'\.(mp4|mov|m4v|webm|avi|mkv)(\?|$)').hasMatch(first)) {
    return ContentMediaType.video;
  }
  if (RegExp(r'\.(mp3|m4a|aac|ogg|wav|flac)(\?|$)').hasMatch(first)) {
    return ContentMediaType.audio;
  }
  if (RegExp(r'\.(pdf|doc|docx|xls|xlsx|ppt|pptx|zip|rar)(\?|$)')
      .hasMatch(first)) {
    return ContentMediaType.document;
  }
  return ContentMediaType.image;
}

List<String> _productTagsFromPostMap(Map<String, dynamic> map) {
  final value = map['product_tags'] ?? map['post_product_tags'];
  if (value is List) {
    return value
        .map((entry) {
          if (entry is Map) {
            return (entry['product_id'] ?? entry['id'])?.toString() ?? '';
          }
          return entry.toString();
        })
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
  }
  return _stringList(value);
}

List<ContentCollaborator> _collaboratorsFromPostMap(
  Map<String, dynamic> map,
) {
  final value = map['collaborators'] ?? map['post_collaborators'];
  if (value is! List) return const [];
  return value
      .map((entry) {
        if (entry is! Map) return null;
        final data = Map<String, dynamic>.from(entry);
        final profile = data['profile'];
        if (profile is Map) {
          return ContentCollaborator.fromMap(
            Map<String, dynamic>.from(profile),
          );
        }
        return ContentCollaborator.fromMap(data);
      })
      .whereType<ContentCollaborator>()
      .where((collaborator) => collaborator.id.isNotEmpty)
      .toList(growable: false);
}

double? _doubleOrNull(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

int _intOrZero(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  return int.tryParse(value.toString()) ?? 0;
}
