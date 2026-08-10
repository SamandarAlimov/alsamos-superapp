import 'dart:convert';

enum ContentMediaType { image, video, audio, document, sticker, location }

class ContentMedia {
  final String id;
  final ContentMediaType type;
  final String url;
  final String? thumbnailUrl;
  final String? mimeType;
  final int? width;
  final int? height;
  final int? durationMs;
  final int? sizeBytes;
  final Map<String, dynamic> metadata;

  const ContentMedia({
    required this.id,
    required this.type,
    required this.url,
    this.thumbnailUrl,
    this.mimeType,
    this.width,
    this.height,
    this.durationMs,
    this.sizeBytes,
    this.metadata = const {},
  });

  factory ContentMedia.fromJson(Map<String, dynamic> json) {
    return ContentMedia(
      id: json['id']?.toString() ?? '',
      type: _mediaTypeFromString(json['type']?.toString()),
      url: json['url']?.toString() ?? '',
      thumbnailUrl: json['thumbnail_url']?.toString(),
      mimeType: json['mime_type']?.toString(),
      width: _intOrNull(json['width']),
      height: _intOrNull(json['height']),
      durationMs: _intOrNull(json['duration_ms']),
      sizeBytes: _intOrNull(json['size_bytes']),
      metadata: _mapOrEmpty(json['metadata']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'url': url,
      if (thumbnailUrl != null) 'thumbnail_url': thumbnailUrl,
      if (mimeType != null) 'mime_type': mimeType,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (durationMs != null) 'duration_ms': durationMs,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }

  static List<ContentMedia> listFrom(dynamic value) {
    if (value == null) return const [];
    final decoded = value is String ? jsonDecode(value) : value;
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((e) => ContentMedia.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }
}

ContentMediaType _mediaTypeFromString(String? value) {
  return ContentMediaType.values.firstWhere(
    (type) => type.name == value,
    orElse: () => ContentMediaType.image,
  );
}

int? _intOrNull(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  return int.tryParse(value.toString());
}

Map<String, dynamic> _mapOrEmpty(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const {};
}
