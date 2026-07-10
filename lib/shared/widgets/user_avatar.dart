import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import 'online_indicator.dart';

/// Avatar with image + initial fallback (web `Avatar` + `AvatarFallback`).
///
/// v31: optional [userId] + [showOnline] overlay an [OnlineIndicator] in the
/// bottom-right corner when the user is present in `onlinePresenceProvider`
/// (mirrors web `<Avatar>` siblings like `<OnlineIndicator>` in chat lists).
class UserAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String fallback;
  final double size;
  final Color? backgroundColor;
  final String? userId;
  final bool showOnline;
  /// v45: opt-in Hero shared-element. Pass an explicit `heroTag` (e.g.
  /// `HeroTags.avatar(userId)`) ONLY at unique source/destination pairs (e.g.
  /// the profile page header). Avoid in repeated lists — duplicate Hero tags
  /// throw at runtime.
  final Object? heroTag;
  const UserAvatar({
    super.key,
    this.avatarUrl,
    this.fallback = 'U',
    this.size = 40,
    this.backgroundColor,
    this.userId,
    this.showOnline = false,
    this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final bg = backgroundColor ?? c.muted;
    final placeholder = Container(
      width: size,
      height: size,
      color: bg,
      alignment: Alignment.center,
      child: Text(
        fallback,
        style: TextStyle(fontSize: size * 0.4, fontWeight: FontWeight.w600, color: c.foreground),
      ),
    );

    final avatar = ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: (avatarUrl != null && avatarUrl!.isNotEmpty)
            ? CachedNetworkImage(
                imageUrl: avatarUrl!,
                fit: BoxFit.cover,
                placeholder: (_, __) => placeholder,
                errorWidget: (_, __, ___) => placeholder,
              )
            : placeholder,
      ),
    );

    // v45: Hero shared element — opt-in via explicit `heroTag`.
    Widget heroWrap(Widget child) {
      if (heroTag == null) return child;
      return Hero(
        tag: heroTag!,
        flightShuttleBuilder: (_, __, ___, ____, _____) => Material(
          color: Colors.transparent,
          child: ClipOval(child: child),
        ),
        child: child,
      );
    }

    if (!showOnline || userId == null || userId!.isEmpty) return heroWrap(avatar);

    final dotSize = size < 28
        ? OnlineDotSize.xs
        : size < 40
            ? OnlineDotSize.sm
            : size < 64
                ? OnlineDotSize.md
                : OnlineDotSize.lg;
    return heroWrap(SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          OnlineIndicator(userId: userId!, size: dotSize),
        ],
      ),
    ));
  }
}
