import 'dart:convert';

const String alsamosMessagePayloadSchema = 'alsamos.message.v1';

/// Marker of the legacy text location protocol produced by the web client and
/// by share links:
/// `<pushpin> LOCATION:<lat>,<lng>|<address>[|LIVE:<expiresAt>]`
///
/// This is a data protocol, not user-facing text, so it must never reach the
/// bubble as-is. See docs/CONTRACTS/message-protocol.md section 4.
const String legacyLocationContentMarker = 'LOCATION:';

const String _legacyLiveSegmentMarker = 'LIVE:';

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

/// Extracts a canonical-shaped location map out of the legacy `content`
/// protocol.
///
/// Intentionally independent of `media_type`: legacy rows frequently carry a
/// null or `text` media type while still encoding coordinates in `content`.
/// Returns null when the marker is absent or the coordinates are unusable.
Map<String, dynamic>? parseLegacyLocationContent(Object? raw) {
  final text = _cleanText(raw is String ? raw : raw?.toString());
  if (text == null) return null;

  final markerIndex = text.indexOf(legacyLocationContentMarker);
  if (markerIndex == -1) return null;

  // Only the pushpin emoji and whitespace may precede the marker, otherwise
  // this is ordinary prose that happens to contain the word LOCATION:.
  final head =
      text.substring(0, markerIndex).replaceAll('\u{1F4CD}', '').trim();
  if (head.isNotEmpty) return null;

  final parts = text
      .substring(markerIndex + legacyLocationContentMarker.length)
      .split('|');
  if (parts.isEmpty) return null;

  final coordinates = _coordinatesFromText(parts.first);
  if (coordinates == null) return null;

  String? address;
  String? expiresAt;
  var live = false;
  for (final part in parts.skip(1)) {
    final value = _cleanText(part);
    if (value == null) continue;
    if (value.startsWith(_legacyLiveSegmentMarker)) {
      live = true;
      expiresAt =
          _cleanText(value.substring(_legacyLiveSegmentMarker.length));
      continue;
    }
    address ??= value;
  }

  return <String, dynamic>{
    'schema': alsamosMessagePayloadSchema,
    'latitude': coordinates.$1,
    'longitude': coordinates.$2,
    if (address != null) 'address': address,
    if (live) 'live': true,
    if (expiresAt != null) 'expiresAt': expiresAt,
  };
}

/// Canonical `call_history` payload.
///
/// The web client stores a JSON document inside `content`. Older rows store a
/// human readable string starting with the telephone-receiver emoji instead.
/// See docs/CONTRACTS/message-protocol.md section 5.
Map<String, dynamic>? canonicalCallHistoryPayload(Object? rawContent) {
  final text =
      _cleanText(rawContent is String ? rawContent : rawContent?.toString());
  if (text == null) return null;

  if (text.startsWith('{')) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) {
        final data = Map<String, dynamic>.from(decoded);
        final type = _cleanText(data['type']);
        final status = _cleanText(data['status']);
        if (type != null && status != null) {
          final duration = _durationSeconds(data['duration']);
          return <String, dynamic>{
            'schema': alsamosMessagePayloadSchema,
            'type': type == 'video' ? 'video' : 'audio',
            'status': status,
            if (duration != null) 'duration': duration,
            if (_cleanText(data['timestamp']) != null)
              'timestamp': _cleanText(data['timestamp']),
            if (_cleanText(data['caller_id']) != null)
              'caller_id': _cleanText(data['caller_id']),
            if (_cleanText(data['callee_id']) != null)
              'callee_id': _cleanText(data['callee_id']),
          };
        }
      }
    } catch (_) {}
  }

  if (!text.startsWith('\u{1F4DE}')) return null;

  final match = RegExp(r'(\d+):(\d+)(?::(\d+))?').firstMatch(text);
  int? duration;
  if (match != null) {
    final first = int.tryParse(match.group(1)!) ?? 0;
    final second = int.tryParse(match.group(2)!) ?? 0;
    final third =
        match.group(3) == null ? null : int.tryParse(match.group(3)!);
    duration = third == null
        ? first * 60 + second
        : first * 3600 + second * 60 + third;
  }

  return <String, dynamic>{
    'schema': alsamosMessagePayloadSchema,
    'type': text.toLowerCase().contains('video') ? 'video' : 'audio',
    'status': 'ended',
    if (duration != null) 'duration': duration,
  };
}

/// Short user-facing label for a call-history row.
String callHistoryLabel(Map<String, dynamic> call) {
  final base = call['type'] == 'video'
      ? "Video qo'ng'iroq"
      : "Audio qo'ng'iroq";

  switch (call['status']) {
    case 'missed':
      return '$base \u00b7 javobsiz';
    case 'declined':
      return '$base \u00b7 rad etildi';
    case 'cancelled':
    case 'canceled':
      return '$base \u00b7 bekor qilindi';
  }

  final duration = _durationSeconds(call['duration']);
  if (duration == null || duration <= 0) return base;
  return '$base \u00b7 ${_formatCallDuration(duration)}';
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

  // Last resort: recover the location from the legacy content protocol so the
  // bubble can render natively instead of printing the raw marker.
  if (next['location'] == null) {
    final legacy = _canonicalLocation(
      parseLegacyLocationContent(row['content']),
    );
    if (legacy != null) {
      next['schema'] = alsamosMessagePayloadSchema;
      next['location'] = legacy;
    }
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

  if (row['media_type']?.toString() == 'call_history') {
    final call = canonicalCallHistoryPayload(row['content']);
    if (call != null) {
      next['schema'] = alsamosMessagePayloadSchema;
      next['call'] = call;
    }
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

  // Call history is a JSON document on the wire. Replace it with a readable
  // label so the raw document never reaches the bubble.
  if (mediaType == 'call_history') {
    final call = decodeMessageMetadata(metadata['call']);
    final resolved = call.isNotEmpty
        ? call
        : canonicalCallHistoryPayload(content) ?? const <String, dynamic>{};
    if (resolved.isNotEmpty) return callHistoryLabel(resolved);
  }

  // The legacy content protocol is handled before the media_type gate, because
  // such rows often carry a null or `text` media type.
  final legacyLocation = parseLegacyLocationContent(content);
  if (legacyLocation != null) {
    final label = _cleanText(legacyLocation['address']) ??
        _cleanText(legacyLocation['label']);
    final latitude = legacyLocation['latitude'];
    final longitude = legacyLocation['longitude'];
    return '${label == null ? '' : '$label\n'}$latitude,$longitude';
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
      .map((line) => line.replaceFirst(RegExp(r'^[-*\u2022]\s*'), '').trim())
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

int? _durationSeconds(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value);
  return null;
}

String _formatCallDuration(int seconds) {
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final rest = seconds % 60;
  final minutesText = minutes.toString().padLeft(hours > 0 ? 2 : 1, '0');
  final secondsText = rest.toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutesText:$secondsText' : '$minutesText:$secondsText';
}

String? _cleanText(Object? value) {
  if (value is! String) return null;
  final text = value.trim();
  return text.isEmpty ? null : text;
}
