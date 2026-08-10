import 'dart:convert';

Map<String, dynamic> normalizePostMap(Map<String, dynamic> source) {
  final map = Map<String, dynamic>.from(source);
  final mediaUrls = _stringList(
    map['media_urls'] ??
        map['media_url'] ??
        map['image_url'] ??
        map['video_url'] ??
        _urlsFromMedia(map['media']),
  );
  final hashtags = _stringList(map['hashtags'] ?? map['tags']);
  final mediaType = _mediaTypeFromMap(map, mediaUrls);

  map['media_urls'] = mediaUrls;
  map['media_type'] = mediaType;
  map['content_type'] ??= _contentTypeFromMap(map, mediaType, mediaUrls);
  map['hashtags'] = hashtags;
  map['tags'] = hashtags;

  if (mediaUrls.isNotEmpty) {
    map['media_url'] ??= mediaUrls.first;
  }

  map['location_name'] ??= map['place_name'] ?? map['location'];
  map['location_address'] ??= map['address'];
  map['location_lng'] ??= map['location_lon'] ?? map['longitude'] ?? map['lng'];
  map['location_lat'] ??= map['latitude'] ?? map['lat'];

  final profile =
      map['profile'] ?? map['profiles'] ?? map['user'] ?? map['author'];
  if (profile != null) {
    map['profile'] = profile;
    map['profiles'] ??= profile;
  }

  return map;
}

List<String> _urlsFromMedia(dynamic value) {
  if (value is! List) return const [];
  return value
      .map((item) {
        if (item is Map) {
          return (item['url'] ?? item['media_url'])?.toString() ?? '';
        }
        return item.toString();
      })
      .where((url) => url.isNotEmpty)
      .toList(growable: false);
}

List<String> _stringList(dynamic value) {
  if (value == null) return const [];
  final decoded = value is String && value.trim().startsWith('[')
      ? _tryDecodeJson(value)
      : value;
  if (decoded is List) {
    return decoded
        .map((item) => item.toString())
        .where((item) => item.trim().isNotEmpty)
        .toList(growable: false);
  }
  if (decoded is String && decoded.trim().isNotEmpty) {
    return [decoded.trim()];
  }
  return const [];
}

dynamic _tryDecodeJson(String value) {
  try {
    return jsonDecode(value);
  } catch (_) {
    return value;
  }
}

String _mediaTypeFromMap(Map<String, dynamic> map, List<String> mediaUrls) {
  final explicit = (map['media_type'] ?? map['content_type'] ?? map['type'])
      ?.toString()
      .toLowerCase();
  if (explicit != null && explicit.isNotEmpty && explicit != 'album') {
    return explicit == 'reel' ? 'video' : explicit;
  }
  if (mediaUrls.isEmpty) return 'text';
  if (mediaUrls.any(_isVideoUrl)) return 'video';
  if (mediaUrls.any(_isAudioUrl)) return 'audio';
  if (mediaUrls.any(_isDocumentUrl)) return 'file';
  return 'image';
}

String _contentTypeFromMap(
  Map<String, dynamic> map,
  String mediaType,
  List<String> mediaUrls,
) {
  final explicit = (map['content_type'] ?? map['type'])?.toString();
  if (explicit != null && explicit.isNotEmpty) return explicit;
  if (mediaUrls.length > 1) return 'album';
  if (mediaType == 'video') return 'video';
  if (mediaType == 'image') return 'image';
  if (map['location_lat'] != null || map['latitude'] != null) {
    return 'location';
  }
  return 'text';
}

bool _isVideoUrl(String url) =>
    RegExp(r'\.(mp4|mov|m4v|webm|avi|mkv)(\?|$)', caseSensitive: false)
        .hasMatch(url);

bool _isAudioUrl(String url) =>
    RegExp(r'\.(mp3|m4a|aac|ogg|wav|flac)(\?|$)', caseSensitive: false)
        .hasMatch(url);

bool _isDocumentUrl(String url) =>
    RegExp(r'\.(pdf|doc|docx|xls|xlsx|ppt|pptx|zip|rar)(\?|$)',
            caseSensitive: false)
        .hasMatch(url);
