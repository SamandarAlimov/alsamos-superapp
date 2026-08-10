import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'create_draft.dart';
import 'create_draft_store_base.dart';

class LocalCreateDraftStore implements CreateDraftStore {
  LocalCreateDraftStore._();

  static final LocalCreateDraftStore instance = LocalCreateDraftStore._();

  static const _indexKey = 'alsamos_create_drafts_index';

  String _draftKey(String id) => 'alsamos_create_draft_$id';

  @override
  Future<void> save(CreateDraft draft) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = await _loadIndex(prefs);
    if (!ids.contains(draft.id)) {
      ids.add(draft.id);
    }
    await prefs.setString(_draftKey(draft.id), jsonEncode(draft.toJson()));
    await _saveIndex(prefs, ids);
  }

  @override
  Future<List<CreateDraft>> list({String? mode, int? limit}) async {
    if (limit != null && limit <= 0) return const <CreateDraft>[];
    final prefs = await SharedPreferences.getInstance();
    final ids = await _loadIndex(prefs);
    final drafts = <CreateDraft>[];
    final validIds = <String>[];

    for (final id in ids) {
      final draft = _decodeDraft(prefs.getString(_draftKey(id)));
      if (draft == null) {
        await prefs.remove(_draftKey(id));
        continue;
      }
      validIds.add(id);
      if (mode == null || draft.mode == mode) {
        drafts.add(draft);
      }
    }

    if (validIds.length != ids.length) {
      await _saveIndex(prefs, validIds);
    }

    final ordered = CreateDraft.newestFirst(drafts);
    if (limit != null && ordered.length > limit) {
      return ordered.sublist(0, limit);
    }
    return ordered;
  }

  @override
  Future<CreateDraft?> load(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final draft = _decodeDraft(prefs.getString(_draftKey(id)));
    if (draft == null) {
      await prefs.remove(_draftKey(id));
    }
    return draft;
  }

  @override
  Future<void> delete(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = await _loadIndex(prefs);
    await prefs.remove(_draftKey(id));
    await _saveIndex(prefs, ids.where((item) => item != id).toList());
  }

  @override
  Future<void> clear({String? mode}) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = await _loadIndex(prefs);
    if (mode == null) {
      for (final id in ids) {
        await prefs.remove(_draftKey(id));
      }
      await prefs.remove(_indexKey);
      return;
    }

    final keepIds = <String>[];
    for (final id in ids) {
      final draft = _decodeDraft(prefs.getString(_draftKey(id)));
      if (draft == null || draft.mode == mode) {
        await prefs.remove(_draftKey(id));
      } else {
        keepIds.add(id);
      }
    }
    await _saveIndex(prefs, keepIds);
  }

  Future<List<String>> _loadIndex(SharedPreferences prefs) async {
    final raw = prefs.getString(_indexKey);
    if (raw == null || raw.isEmpty) return <String>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.whereType<String>().toList();
      }
    } catch (_) {}
    return <String>[];
  }

  Future<void> _saveIndex(SharedPreferences prefs, List<String> ids) {
    return prefs.setString(_indexKey, jsonEncode(ids.toSet().toList()));
  }

  CreateDraft? _decodeDraft(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return CreateDraft.tryFromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {}
    return null;
  }
}
