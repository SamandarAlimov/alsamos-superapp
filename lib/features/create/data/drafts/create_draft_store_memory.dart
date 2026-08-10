import 'create_draft.dart';
import 'create_draft_store_base.dart';

class MemoryCreateDraftStore implements CreateDraftStore {
  final Map<String, CreateDraft> _drafts = <String, CreateDraft>{};

  @override
  Future<void> save(CreateDraft draft) async {
    _drafts[draft.id] = CreateDraft.fromJson(draft.toJson());
  }

  @override
  Future<List<CreateDraft>> list({String? mode, int? limit}) async {
    if (limit != null && limit <= 0) return const <CreateDraft>[];
    final ordered = CreateDraft.newestFirst(
      _drafts.values.where((draft) => mode == null || draft.mode == mode),
    );
    if (limit != null && ordered.length > limit) {
      return ordered.sublist(0, limit);
    }
    return ordered
        .map((draft) => CreateDraft.fromJson(draft.toJson()))
        .toList();
  }

  @override
  Future<CreateDraft?> load(String id) async {
    final draft = _drafts[id];
    return draft == null ? null : CreateDraft.fromJson(draft.toJson());
  }

  @override
  Future<void> delete(String id) async {
    _drafts.remove(id);
  }

  @override
  Future<void> clear({String? mode}) async {
    if (mode == null) {
      _drafts.clear();
      return;
    }
    _drafts.removeWhere((_, draft) => draft.mode == mode);
  }
}
