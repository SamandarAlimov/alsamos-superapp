import 'create_draft.dart';

abstract class CreateDraftStore {
  Future<void> save(CreateDraft draft);

  Future<List<CreateDraft>> list({String? mode, int? limit});

  Future<CreateDraft?> load(String id);

  Future<void> delete(String id);

  Future<void> clear({String? mode});
}
