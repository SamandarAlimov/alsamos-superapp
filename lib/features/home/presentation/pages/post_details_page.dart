import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../data/models/post_model.dart';
import '../providers/posts_provider.dart';
import '../widgets/post_card.dart';

final postDetailsProvider =
    FutureProvider.autoDispose.family<Post?, String>((ref, postId) async {
  final cached = ref.read(postsProvider).posts.where((p) => p.id == postId);
  if (cached.isNotEmpty) return cached.first;
  return ref.read(postsRepositoryProvider).fetchPostById(postId);
});

class PostDetailsPage extends ConsumerWidget {
  final String postId;
  const PostDetailsPage({super.key, required this.postId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AlsamosColors.of(context);
    final asyncPost = ref.watch(postDetailsProvider(postId));

    return asyncPost.when(
      loading: () => Center(
        child: CircularProgressIndicator(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      error: (error, _) => _PostDetailsMessage(
        title: 'Post ochilmadi',
        subtitle: error.toString(),
        actionLabel: 'Bosh sahifaga qaytish',
        onAction: () => context.go('/home'),
      ),
      data: (post) {
        if (post == null) {
          return _PostDetailsMessage(
            title: 'Post topilmadi',
            subtitle: '/post/$postId',
            actionLabel: 'Bosh sahifaga qaytish',
            onAction: () => context.go('/home'),
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 48),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 672),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          context.go('/home');
                        }
                      },
                      icon: Icon(LucideIcons.arrowLeft, color: c.foreground),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Post',
                      style: TextStyle(
                        color: c.foreground,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 672),
                child: PostCard(
                  post: post,
                  onLike: () async {
                    await ref.read(postsRepositoryProvider).toggleLike(post);
                    ref.invalidate(postDetailsProvider(postId));
                    ref.invalidate(postsProvider);
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PostDetailsMessage extends StatelessWidget {
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;
  const _PostDetailsMessage({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: c.muted,
                shape: BoxShape.circle,
                border: Border.all(color: c.border),
              ),
              child: Icon(LucideIcons.fileQuestion, color: primary, size: 34),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.foreground,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: c.mutedForeground, fontSize: 13),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: onAction,
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}
