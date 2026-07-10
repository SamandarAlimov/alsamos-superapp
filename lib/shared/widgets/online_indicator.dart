import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';

/// UI-only port of web `src/components/OnlineIndicator.tsx`.
///
/// In the web app, presence is fed by `OnlinePresenceContext` (Supabase
/// realtime presence channel). Here we expose the same surface as a
/// `StateProvider<Set<String>>` that the UI reads via `isUserOnline()`.
///
/// The realtime hookup itself is left for the backend layer — this widget is
/// fully UI-only and renders nothing until the provider's set is populated.
final onlinePresenceProvider = StateProvider<Set<String>>((_) => <String>{});

/// Helper: returns true if [userId] is in the current presence set.
bool isUserOnline(WidgetRef ref, String userId) =>
    ref.watch(onlinePresenceProvider).contains(userId);

enum OnlineDotSize { xs, sm, md, lg }

/// Tiny green dot rendered next to an avatar (web parity).
///
/// Set [absolute] true to position absolutely in the bottom-right corner of
/// the parent Stack (matches web `absolute bottom-0 right-0`).
class OnlineIndicator extends ConsumerWidget {
  final String userId;
  final OnlineDotSize size;
  final bool absolute;
  const OnlineIndicator({
    super.key,
    required this.userId,
    this.size = OnlineDotSize.md,
    this.absolute = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(onlinePresenceProvider).contains(userId);
    if (!isOnline) return const SizedBox.shrink();

    final c = AlsamosColors.of(context);
    final dim = switch (size) {
      OnlineDotSize.xs => 8.0,
      OnlineDotSize.sm => 10.0,
      OnlineDotSize.md => 12.0,
      OnlineDotSize.lg => 16.0,
    };
    final border = switch (size) {
      OnlineDotSize.xs => 0.0,
      OnlineDotSize.sm => 1.0,
      OnlineDotSize.md => 2.0,
      OnlineDotSize.lg => 2.0,
    };

    final dot = Container(
      width: dim,
      height: dim,
      decoration: BoxDecoration(
        color: const Color(0xFF22C55E), // tailwind green-500
        shape: BoxShape.circle,
        border: border > 0 ? Border.all(color: c.background, width: border) : null,
      ),
    );

    if (!absolute) return dot;
    return Positioned(bottom: 0, right: 0, child: dot);
  }
}
