import 'dart:convert';

const messagePayloadSchema = 'alsamos.message.v1';

Map<String, dynamic>? _asMap(Object? value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  if (value is String && value.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
  }
  return null;
}

String? _cleanText(Object? value) {
  if (value is! String) return null;
  final text = value.trim();
  return text.isEmpty ? null : text;
}

double? _coordinate(Object? value, double max) {
  final numeric = value is num ? value.toDouble() : double.tryParse('$value');
  if (numeric == null || !numeric.isFinite || numeric.abs() > max) return null;
  return numeric;
}

Map<String, dynamic>? _normalizeLocation(Object? value) {
  final data = _asMap(value);
  if (data == null) return null;
  final latitude = _coordinate(data['latitude'] ?? data['lat'], 90);
  final longitude = _coordinate(data['longitude'] ?? data['lng'], 180);
  if (latitude == null || longitude == null) return null;
  return {
    'schema': messagePayloadSchema,
    'latitude': latitude,
    'longitude': longitude,
    if (_cleanText(data['address']) != null) 'address': _cleanText(data['address']),
    if (_cleanText(data['label'] ?? data['name']) != null)
      'label': _cleanText(data['label'] ?? data['name']),
    'live': data['live'] == true || data['is_live'] == true,
    if (_cleanText(data['expiresAt'] ?? data['expires_at'] ?? data['live_until']) != null)
      'expiresAt': _cleanText(data['expiresAt'] ?? data['expires_at'] ?? data['live_until']),
  };
}

({double latitude, double longitude})? _coordinatesFromText(String raw) {
  final match = RegExp(r'(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)').firstMatch(raw);
  if (match == null) return null;
  final latitude = _coordinate(match.group(1), 90);
  final longitude = _coordinate(match.group(2), 180);
  if (latitude == null || longitude == null) return null;
  return (latitude: latitude, longitude: longitude);
}

Map<String, dynamic>? parseMessageLocationPayload({
  required String? content,
  required String? mediaType,
  required String? mediaUrl,
  required Map<String, dynamic> metadata,
}) {
  final nested =
      _normalizeLocation(metadata['location']) ??
      _normalizeLocation(metadata['location_payload']);
  if (nested != null) {
    return {
      ...nested,
      'live': nested['live'] == true || mediaType == 'live_location',
      if (nested['expiresAt'] == null &&
          _cleanText(metadata['live_location_expires_at']) != null)
        'expiresAt': _cleanText(metadata['live_location_expires_at']),
    };
  }

  if ((mediaType == 'location' || mediaType == 'live_location') &&
      mediaUrl != null) {
    final coords = _coordinatesFromText(mediaUrl);
    if (coords != null) {
      return {
        'schema': messagePayloadSchema,
        'latitude': coords.latitude,
        'longitude': coords.longitude,
        if (_cleanText(content) != null) 'label': _cleanText(content),
        'live': mediaType == 'live_location',
        if (_cleanText(metadata['live_location_expires_at']) != null)
          'expiresAt': _cleanText(metadata['live_location_expires_at']),
      };
    }
  }

  final text = content?.trim() ?? '';
  if (text.startsWith('📍 LOCATION:')) {
    final body = text.substring('📍 LOCATION:'.length);
    final parts = body.split('|');
    final coords = _coordinatesFromText(parts.first);
    if (coords == null) return null;
    String? address;
    String? expiresAt;
    for (final part in parts.skip(1)) {
      if (part.startsWith('LIVE:')) {
        expiresAt = _cleanText(part.substring('LIVE:'.length));
      } else if (_cleanText(part) != null) {
        address ??= _cleanText(part);
      }
    }
    return {
      'schema': messagePayloadSchema,
      'latitude': coords.latitude,
      'longitude': coords.longitude,
      if (address != null) 'address': address,
      'live': expiresAt != null || mediaType == 'live_location',
      if (expiresAt != null) 'expiresAt': expiresAt,
    };
  }

  if (mediaType == 'location' || mediaType == 'live_location') {
    final coords = _coordinatesFromText(text);
    if (coords == null) return null;
    final label = text
        .replaceAll(RegExp(r'-?\d+(?:\.\d+)?\s*,\s*-?\d+(?:\.\d+)?'), '')
        .replaceAll('📍', '')
        .trim();
    return {
      'schema': messagePayloadSchema,
      'latitude': coords.latitude,
      'longitude': coords.longitude,
      if (label.isNotEmpty) 'label': label,
      'live': mediaType == 'live_location',
      if (_cleanText(metadata['live_location_expires_at']) != null)
        'expiresAt': _cleanText(metadata['live_location_expires_at']),
    };
  }

  return null;
}

Map<String, dynamic>? _normalizePoll(Object? value) {
  final data = _asMap(value);
  if (data == null) return null;
  final question = _cleanText(data['question'] ?? data['title']);
  final rawOptions = data['options'];
  if (question == null || rawOptions is! List) return null;

  final options = <Map<String, dynamic>>[];
  for (var i = 0; i < rawOptions.length; i++) {
    final raw = rawOptions[i];
    if (raw is String) {
      final text = raw.trim();
      if (text.isNotEmpty) {
        options.add({'id': 'opt_$i', 'text': text, 'votes': 0});
      }
      continue;
    }
    final item = _asMap(raw);
    if (item == null) continue;
    final text = _cleanText(item['text'] ?? item['title'] ?? item['label']);
    if (text == null) continue;
    final votes = item['votes'] is num ? (item['votes'] as num).toInt() : 0;
    options.add({
      'id': _cleanText(item['id']) ?? 'opt_$i',
      'text': text,
      'votes': votes,
    });
  }

  if (options.length < 2) return null;
  return {
    'schema': messagePayloadSchema,
    'question': question,
    'options': options,
    'multiple': data['multiple'] == true ||
        data['allowMultiple'] == true ||
        data['allows_multiple'] == true,
    'anonymous': data['anonymous'] == true ||
        data['isAnonymous'] == true ||
        data['is_anonymous'] == true,
  };
}

Map<String, dynamic>? parseMessagePollPayload({
  required String? content,
  required String? mediaType,
  required Map<String, dynamic> metadata,
}) {
  final metadataPoll = _normalizePoll(metadata['poll']);
  if (metadataPoll != null) return metadataPoll;

  final text = content?.trim() ?? '';
  final legacy = RegExp(r'\[POLL\]([\s\S]*?)\[/POLL\]').firstMatch(text);
  if (legacy != null) {
    try {
      final normalized = _normalizePoll(jsonDecode(legacy.group(1)!));
      if (normalized != null) return normalized;
    } catch (_) {}
  }

  if (mediaType != 'poll') return null;
  final lines = text
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  if (lines.length < 3) return null;
  final options = lines
      .skip(1)
      .map((line) => line.replaceFirst(RegExp(r'^[-*•]\s*'), '').trim())
      .where((line) => line.isNotEmpty)
      .toList();
  return _normalizePoll({
    'question': lines.first,
    'options': options,
    'multiple': false,
  });
}

Map<String, dynamic> buildCanonicalLocationMetadata({
  required double latitude,
  required double longitude,
  String? address,
  String? label,
  bool live = false,
  String? expiresAt,
}) {
  final location = <String, dynamic>{
    'schema': messagePayloadSchema,
    'latitude': latitude,
    'longitude': longitude,
    if (_cleanText(address) != null) 'address': _cleanText(address),
    if (_cleanText(label) != null) 'label': _cleanText(label),
    'live': live,
    if (_cleanText(expiresAt) != null) 'expiresAt': _cleanText(expiresAt),
  };
  return {
    'schema': messagePayloadSchema,
    'location': location,
    if (_cleanText(expiresAt) != null)
      'live_location_expires_at': _cleanText(expiresAt),
  };
}

Map<String, dynamic> buildCanonicalPollMetadata({
  required String question,
  required List<String> options,
  bool multiple = false,
  bool anonymous = false,
}) {
  return {
    'schema': messagePayloadSchema,
    'poll': {
      'schema': messagePayloadSchema,
      'question': question.trim(),
      'options': [
        for (var i = 0; i < options.length; i++)
          {'id': 'opt_$i', 'text': options[i].trim(), 'votes': 0},
      ],
      'multiple': multiple,
      'anonymous': anonymous,
    },
  };
}
