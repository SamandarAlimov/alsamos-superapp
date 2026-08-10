import 'dart:convert';

class CreateDraft {
  static const currentSchemaVersion = 1;

  final String id;
  final int schemaVersion;
  final String mode;
  final DateTime updatedAt;
  final Map<String, dynamic> payload;

  CreateDraft({
    required this.id,
    required this.mode,
    required DateTime updatedAt,
    Map<String, dynamic> payload = const {},
    this.schemaVersion = currentSchemaVersion,
  })  : updatedAt = updatedAt.toUtc(),
        payload = _deepCopyMap(payload);

  factory CreateDraft.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final schemaVersion = json['schemaVersion'];
    final mode = json['mode'];
    final updatedAt = json['updatedAt'];
    final payload = json['payload'];

    if (id is! String || id.isEmpty) {
      throw const FormatException('Draft id is missing');
    }
    if (schemaVersion is! int || schemaVersion < 1) {
      throw const FormatException('Draft schemaVersion is invalid');
    }
    if (mode is! String || mode.isEmpty) {
      throw const FormatException('Draft mode is missing');
    }
    if (updatedAt is! String || updatedAt.isEmpty) {
      throw const FormatException('Draft updatedAt is missing');
    }

    final parsedUpdatedAt = DateTime.parse(updatedAt).toUtc();
    return CreateDraft(
      id: id,
      schemaVersion: schemaVersion,
      mode: mode,
      updatedAt: parsedUpdatedAt,
      payload: payload is Map ? Map<String, dynamic>.from(payload) : const {},
    );
  }

  static CreateDraft? tryFromJson(Map<String, dynamic> json) {
    try {
      return CreateDraft.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  CreateDraft copyWith({
    String? id,
    int? schemaVersion,
    String? mode,
    DateTime? updatedAt,
    Map<String, dynamic>? payload,
  }) {
    return CreateDraft(
      id: id ?? this.id,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      mode: mode ?? this.mode,
      updatedAt: updatedAt ?? this.updatedAt,
      payload: payload ?? this.payload,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'schemaVersion': schemaVersion,
        'mode': mode,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'payload': _deepCopyMap(payload),
      };

  static List<CreateDraft> newestFirst(Iterable<CreateDraft> drafts) {
    return drafts.toList()
      ..sort((a, b) {
        final byUpdatedAt = b.updatedAt.compareTo(a.updatedAt);
        if (byUpdatedAt != 0) return byUpdatedAt;
        return b.id.compareTo(a.id);
      });
  }

  static Map<String, dynamic> _deepCopyMap(Map<String, dynamic> value) {
    final encoded = jsonEncode(value);
    final decoded = jsonDecode(encoded);
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
    return <String, dynamic>{};
  }
}
