import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/post_model.dart';
import '../../data/repositories/posts_repository.dart';

final postsRepositoryProvider = Provider((ref) => PostsRepository());

class PostsState {
  final List<Post> posts;
  final bool isLoading;
  final bool hasMore;
  final int page;
  final String? error;

  const PostsState({
    this.posts = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.page = 0,
    this.error,
  });

  PostsState copyWith({
    List<Post>? posts,
    bool? isLoading,
    bool? hasMore,
    int? page,
    String? error,
  }) =>
      PostsState(
        posts: posts ?? this.posts,
        isLoading: isLoading ?? this.isLoading,
        hasMore: hasMore ?? this.hasMore,
        page: page ?? this.page,
        error: error,
      );
}

class PostsNotifier extends StateNotifier<PostsState> {
  final PostsRepository _repo;
  PostsNotifier(this._repo) : super(const PostsState()) {
    refresh();
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final posts = await _repo.fetchPosts(page: 0);
      state = state.copyWith(
        posts: posts,
        isLoading: false,
        page: 0,
        hasMore: posts.length >= 10,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> loadMore() async {
    if (state.isLoading || !state.hasMore) return;
    state = state.copyWith(isLoading: true);
    try {
      final next = state.page + 1;
      final more = await _repo.fetchPosts(page: next);
      state = state.copyWith(
        posts: [...state.posts, ...more],
        isLoading: false,
        page: next,
        hasMore: more.length >= 10,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> toggleLike(Post post) async {
    // optimistic update
    final liked = !post.isLiked;
    _patch(post.id, post.copyWith(isLiked: liked, likesCount: post.likesCount + (liked ? 1 : -1)));
    try {
      final result = await _repo.toggleLike(post);
      if (result != liked) {
        _patch(post.id, post); // revert
      }
    } catch (_) {
      _patch(post.id, post); // revert
    }
  }

  void _patch(String id, Post updated) {
    state = state.copyWith(
      posts: [for (final p in state.posts) if (p.id == id) updated else p],
    );
  }
}

final postsProvider = StateNotifierProvider<PostsNotifier, PostsState>((ref) {
  return PostsNotifier(ref.watch(postsRepositoryProvider));
});
