import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../home/data/models/post_model.dart';
import '../../../home/presentation/providers/posts_provider.dart';
import '../../../home/presentation/widgets/post_card.dart';

class TrendingPublicPosts extends ConsumerStatefulWidget {
  const TrendingPublicPosts({super.key});

  @override
  ConsumerState<TrendingPublicPosts> createState() =>
      _TrendingPublicPostsState();
}

class _TrendingPublicPostsState extends ConsumerState<TrendingPublicPosts> {
  late Future<void> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<void> _load() async {
    final posts =
        await ref.read(postsRepositoryProvider).fetchTrendingPublicPosts();
    if (!mounted) return;
    setState(() => _posts = posts);
  }

  List<Post> _posts = const [];

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    return FutureBuilder<void>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _Shell(
            c: c,
            child: const LoadingView(label: 'Public postlar yuklanmoqda...'),
          );
        }
        if (snapshot.hasError) {
          return _Shell(
            c: c,
            child: ErrorView(
              error: snapshot.error!,
              onRetry: () => setState(() => _future = _load()),
            ),
          );
        }
        if (_posts.isEmpty) {
          return _Shell(
            c: c,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(children: [
                Icon(LucideIcons.flame, color: c.mutedForeground),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Public kanal va guruh postlari hali yo\'q',
                      style: TextStyle(color: c.mutedForeground)),
                ),
              ]),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(c: c),
            const SizedBox(height: 12),
            ..._posts.map((post) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: PostCard(
                    post: post,
                    onLike: () async {
                      await ref.read(postsProvider.notifier).toggleLike(post);
                      setState(() => _future = _load());
                    },
                  ),
                )),
          ],
        );
      },
    );
  }
}

class _Shell extends StatelessWidget {
  const _Shell({required this.c, required this.child});

  final AlsamosColors c;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(c: c),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.border),
            ),
            child: child,
          ),
        ],
      );
}

class _Header extends StatelessWidget {
  const _Header({required this.c});

  final AlsamosColors c;

  @override
  Widget build(BuildContext context) => Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: c.primary.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(LucideIcons.flame, color: c.primary, size: 19),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Text('Public postlar trendda',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        ),
      ]);
}
