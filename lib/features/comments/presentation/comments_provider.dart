import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/providers/auth_provider.dart';
import '../data/comment_model.dart';
import '../data/comments_repository.dart';

final commentsRepositoryProvider =
    Provider((ref) => const CommentsRepository());

final commentsProvider = StateNotifierProvider.family<CommentsNotifier,
    AsyncValue<List<Comment>>, String>((ref, postId) {
  final userId = ref.watch(authProvider).user?.id;
  return CommentsNotifier(ref.read(commentsRepositoryProvider), postId, userId);
});

class CommentsNotifier extends StateNotifier<AsyncValue<List<Comment>>> {
  final CommentsRepository _repo;
  final String _postId;
  final String? _userId;

  CommentsNotifier(this._repo, this._postId, this._userId)
      : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    try {
      state = AsyncValue.data(await _repo.fetch(_postId, _userId));
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> add(String content, {String? parentId}) async {
    if (_userId == null || content.trim().isEmpty) return;
    await _repo.add(_postId, _userId, content.trim(), parentId: parentId);
    load();
  }

  Future<void> toggleLike(Comment c) async {
    if (_userId == null) return;
    await _repo.toggleLike(c.id, _userId, c.isLiked);
    load();
  }

  Future<void> addComment(String text, {String? parentId}) async {
    await add(text, parentId: parentId);
  }
}
