import 'dart:convert';

const String alsamosMessagePayloadSchema = 'alsamos.message.v1';

Map<String, dynamic> decodeMessageMetadata(Object? raw) {
  if (raw == null) return <String, dynamic>{};
  if (raw is Map) return Map<String, dynamic>.from(raw);
  if (raw is String && raw.isNotEmpty) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
  }
  return <String, dynamic>{};
}

Map<String, dynamic> hydrateStructuredMessageMetadata(
  Map<String, dynamic> row,
  Map<String, dynamic> metadata,
) {
  final next = Map<String, dynamic>.from(metadata);

  final dbLocation = decodeMessageMetadata(row['location_payload']);
  if (dbLocation.isNotEmpty) {
    next['location_payload'] = dbLocation;
    next['location'] = _canonicalLocation(dbLocation) ?? dbLocation;
  }

  final existingLocation = decodeMessageMetadata(next['location']);
  final flatLocation = <String, dynamic>{
    if (next['latitude'] != null) 'latitude': next['latitude'],
    if (next['longitude'] != null) 'longitude': next['longitude'],
    if (next['lat'] != null) 'lat': next['lat'],
    if (next['lng'] != null) 'lng': next['lng'],
    if (next['location_label'] != null) 'label': next['location_label'],
    if (next['address'] != null) 'address': next['address'],
  };
  final canonical = _canonicalLocation(
    existingLocation.isNotEmpty ? existingLocation : flatLocation,
  );
  if (canonical != null) {
    next['schema'] = alsamosMessagePayloadSchema;
    next['location'] = canonical;
  }

  for (final key in const [
    'live_location_expires_at',
    'live_location_stopped_at',
  ]) {
    final value = row[key];
    if (value != null) next[key] = value;
  }

  final poll = canonicalPollPayload(
    next['poll'],
    content: row['content']?.toString(),
    mediaType: row['media_type']?.toString(),
  );
  if (poll != null) {
    next['schema'] = alsamosMessagePayloadSchema;
    next['poll'] = poll;
  }

  return next;
}

String? normalizeLocationContentForLegacyRenderer({
  required String? mediaType,
  required String? content,
  required String? mediaUrl,
  required Map<String, dynamic> metadata,
}) {
  // Existing Flutter bubble pollni metadata orqali native chizadi. Canonical yoki
  // legacy poll tanilgandan keyin transport matnini ikkinchi marta ko'rsatmaymiz.
  if (mediaType == 'poll' &&
      canonicalPollPayload(
            metadata['poll'],
            content: content,
            mediaType: mediaType,
          ) !=
          null) {
    return '';
  }

  if (mediaType != 'location' && mediaType != 'live_location') return content;
  final original = content?.trim() ?? '';
  if (_coordinatesFromText(original) != null) return content;

  Map<String, dynamic>? location = _canonicalLocation(metadata['location']);
  location ??= _canonicalLocation(metadata['location_payload']);
  location ??= _canonicalLocation(metadata);

  final mediaCoordinates = _coordinatesFromText(mediaUrl ?? '');
  if (location == null && mediaCoordinates != null) {
    location = <String, dynamic>{
      'schema': alsamosMessagePayloadSchema,
      'latitude': mediaCoordinates.$1,
      'longitude': mediaCoordinates.$2,
    };
  }
  if (location == null) return content;

  final latitude = location['latitude'];
  final longitude = location['longitude'];
  if (latitude == null || longitude == null) return content;
  final label = _cleanText(location['address']) ??
      _cleanText(location['label']) ??
      (original.isEmpty ? null : original);
  return '${label == null ? '' : '$label\n'}$latitude,$longitude';
}

Map<String, dynamic>? canonicalPollPayload(
  Object? value, {
  String? content,
  String? mediaType,
}) {
  final data = decodeMessageMetadata(value);
  String? question = _cleanText(data['question'] ?? data['title']);
  final rawOptions = data['options'] is List ? data['options'] as List : const [];
  var options = <Map<String, dynamic>>[];
  for (var i = 0; i < rawOptions.length; i++) {
    final option = _normalizePollOption(rawOptions[i], i);
    if (option != null) options.add(option);
  }

  if ((question == null || options.length < 2) && mediaType == 'poll') {
    final parsedLegacy = _parseLegacyPollContent(content ?? '');
    question ??= parsedLegacy?.question;
    if (options.length < 2 && parsedLegacy != null) {
      options = [
        for (var i = 0; i < parsedLegacy.options.length; i++)
          {'id': 'opt_$i', 'text': parsedLegacy.options[i], 'votes': 0},
      ];
    }
  }

  if (question == null || options.length < 2) return null;
  return <String, dynamic>{
    'schema': alsamosMessagePayloadSchema,
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

Map<String, dynamic>? _canonicalLocation(Object? value) {
  final data = decodeMessageMetadata(value);
  if (data.isEmpty) return null;
  final latitude = _coordinate(data['latitude'] ?? data['lat'], 90);
  final longitude = _coordinate(data['longitude'] ?? data['lng'], 180);
  if (latitude == null || longitude == null) return null;
  return <String, dynamic>{
    'schema': alsamosMessagePayloadSchema,
    'latitude': latitude,
    'longitude': longitude,
    if (_cleanText(data['address']) != null) 'address': _cleanText(data['address']),
    if (_cleanText(data['label'] ?? data['name'] ?? data['location_label']) != null)
      'label': _cleanText(data['label'] ?? data['name'] ?? data['location_label']),
    if (data['live'] == true || data['is_live'] == true) 'live': true,
    if (_cleanText(data['expiresAt'] ?? data['expires_at'] ?? data['live_until']) != null)
      'expiresAt': _cleanText(data['expiresAt'] ?? data['expires_at'] ?? data['live_until']),
  };
}

Map<String, dynamic>? _normalizePollOption(Object? value, int index) {
  if (value is String) {
    final text = value.trim();
    return text.isEmpty ? null : {'id': 'opt_$index', 'text': text, 'votes': 0};
  }
  if (value is! Map) return null;
  final item = Map<String, dynamic>.from(value);
  final text = _cleanText(item['text'] ?? item['title'] ?? item['label']);
  if (text == null) return null;
  final votes = int.tryParse('${item['votes'] ?? 0}') ?? 0;
  return {
    'id': _cleanText(item['id']) ?? 'opt_$index',
    'text': text,
    'votes': votes,
  };
}

({String question, List<String> options})? _parseLegacyPollContent(String raw) {
  final text = raw.trim();
  final legacy = RegExp(r'\[POLL\]([\s\S]*?)\[/POLL\]').firstMatch(text);
  if (legacy != null) {
    try {
      final decoded = jsonDecode(legacy.group(1)!);
      final poll = canonicalPollPayload(decoded);
      if (poll != null) {
        return (
          question: poll['question'] as String,
          options: (poll['options'] as List)
              .whereType<Map>()
              .map((e) => e['text']?.toString() ?? '')
              .where((e) => e.isNotEmpty)
              .toList(),
        );
      }
    } catch (_) {}
  }
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
  if (options.length < 2) return null;
  return (question: lines.first, options: options);
}

(double, double)? _coordinatesFromText(String text) {
  final match = RegExp(r'(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)').firstMatch(text);
  if (match == null) return null;
  final latitude = _coordinate(match.group(1), 90);
  final longitude = _coordinate(match.group(2), 180);
  return latitude == null || longitude == null ? null : (latitude, longitude);
}

double? _coordinate(Object? value, double max) {
  final number = value is num ? value.toDouble() : double.tryParse('$value');
  if (number == null || !number.isFinite || number.abs() > max) return null;
  return number;
}

String? _cleanText(Object? value) {
  if (value is! String) return null;
  final text = value.trim();
  return text.isEmpty ? null : text;
}
