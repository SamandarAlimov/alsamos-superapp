import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/error_boundary.dart';

/// v44: Page transition helpers for GoRouter.
/// Web parity: Framer Motion-style page enter/exit.
///
/// Usage:
///   GoRoute(path: '/x', pageBuilder: (c, s) => fadeSlidePage(c, s, const XPage()))

/// Default fade + slide-from-right (iOS feel) for navigations.
CustomTransitionPage<T> fadeSlidePage<T>(
  BuildContext context,
  GoRouterState state,
  Widget child, {
  Duration duration = const Duration(milliseconds: 280),
}) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    transitionDuration: duration,
    reverseTransitionDuration: duration,
    child: ErrorBoundary.page(
      child: child,
      onRetry: () async => GoRouter.of(context).go(state.uri.toString()),
    ),
    transitionsBuilder: (ctx, anim, secAnim, child) {
      final curve = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curve,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.992, end: 1).animate(curve),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.035, 0),
              end: Offset.zero,
            ).animate(curve),
            child: child,
          ),
        ),
      );
    },
  );
}

/// Slide-up modal style (videos / chat / stories).
CustomTransitionPage<T> modalUpPage<T>(
  BuildContext context,
  GoRouterState state,
  Widget child,
) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    fullscreenDialog: true,
    child: ErrorBoundary.page(
      child: child,
      onRetry: () async => GoRouter.of(context).go(state.uri.toString()),
    ),
    transitionsBuilder: (ctx, anim, _, child) {
      final curve = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curve,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.985, end: 1).animate(curve),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.10),
              end: Offset.zero,
            ).animate(curve),
            child: child,
          ),
        ),
      );
    },
  );
}

/// Use a native Cupertino transition (iOS swipe-back gesture).
CustomTransitionPage<T> cupertinoPage<T>(
  BuildContext context,
  GoRouterState state,
  Widget child,
) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    transitionDuration: const Duration(milliseconds: 300),
    child: ErrorBoundary.page(
      child: child,
      onRetry: () async => GoRouter.of(context).go(state.uri.toString()),
    ),
    transitionsBuilder: (ctx, anim, secAnim, child) => CupertinoPageTransition(
      primaryRouteAnimation: anim,
      secondaryRouteAnimation: secAnim,
      linearTransition: false,
      child: child,
    ),
  );
}

/// Tag generator for Hero animations so the source and destination can
/// reference the same logical entity (avatar / post media) consistently.
class HeroTags {
  static String avatar(String userId) => 'avatar.$userId';
  static String postMedia(String postId, int index) => 'media.$postId.$index';
  static String storyRing(String storyId) => 'story.$storyId';
}
