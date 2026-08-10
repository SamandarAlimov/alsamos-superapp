import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/stories/story_avatar_ring.dart';
import '../../../../shared/widgets/verified_badge.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../../../shared/widgets/error_mapper.dart';
import '../../../profile/data/profile_model.dart';

/// User result tile for search with follow button
class UserResultTile extends ConsumerStatefulWidget {
  final FullProfile user;

  const UserResultTile({
    super.key,
    required this.user,
  });

  @override
  ConsumerState<UserResultTile> createState() => _UserResultTileState();
}

class _UserResultTileState extends ConsumerState<UserResultTile> {
  bool _isFollowing = false;
  bool _isLoading = true;

  String get _displayName =>
      widget.user.displayName ?? widget.user.username ?? 'User';
  String get _username => '@${widget.user.username ?? 'user'}';
  String? get _avatarUrl => widget.user.avatarUrl;
  bool get _isVerified => widget.user.isVerified;
  int get _followersCount => widget.user.followersCount;

  String get _followersLabel {
    if (_followersCount >= 1000000) {
      return '${(_followersCount / 1000000).toStringAsFixed(1)}M obunachi';
    }
    if (_followersCount >= 1000) {
      return '${(_followersCount / 1000).toStringAsFixed(1)}K obunachi';
    }
    return '$_followersCount obunachi';
  }

  @override
  void initState() {
    super.initState();
    _checkFollowStatus();
  }

  Future<void> _checkFollowStatus() async {
    try {
      final supa = Supabase.instance.client;
      final userId = supa.auth.currentUser?.id;
      if (userId == null) {
        setState(() => _isLoading = false);
        return;
      }

      final response = await supa
          .from('follows')
          .select()
          .eq('follower_id', userId)
          .eq('following_id', widget.user.id)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _isFollowing = response != null;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error checking follow status: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _toggleFollow() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);

    // Optimistic update
    final wasFollowing = _isFollowing;
    setState(() => _isFollowing = !_isFollowing);

    try {
      final supa = Supabase.instance.client;
      final userId = supa.auth.currentUser?.id;
      if (userId == null) throw Exception('Not authenticated');

      if (_isFollowing) {
        // Follow user
        await supa.from('follows').insert({
          'follower_id': userId,
          'following_id': widget.user.id,
        });
      } else {
        // Unfollow user
        await supa
            .from('follows')
            .delete()
            .eq('follower_id', userId)
            .eq('following_id', widget.user.id);
      }

      if (!mounted) return;
      AppToast.success(context,
          _isFollowing ? 'Obuna bo\'ldingiz' : 'Obunani bekor qildingiz');
    } catch (e) {
      // Rollback on error
      if (mounted) {
        setState(() => _isFollowing = wasFollowing);
        AppToast.error(context, friendlyError(e));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;

    return InkWell(
      onTap: () =>
          context.push('/profile/${widget.user.username ?? widget.user.id}'),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.border.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            StoryAvatarRing(
              userId: widget.user.id,
              avatarUrl: _avatarUrl,
              fallback: _displayName.isEmpty ? 'U' : _displayName[0],
              size: 46,
              backgroundColor: primary.withValues(alpha: 0.1),
              onTap: () => context.push(
                '/profile/${widget.user.username ?? widget.user.id}',
              ),
            ),
            const SizedBox(width: 12),

            // User info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Display name + verified
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          _displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: c.foreground,
                          ),
                        ),
                      ),
                      if (_isVerified) ...[
                        const SizedBox(width: 4),
                        const VerifiedBadge(size: 14),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  // Username + followers
                  Text(
                    '$_username · $_followersLabel',
                    style: TextStyle(
                      fontSize: 12,
                      color: c.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Follow button
            _isLoading
                ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: primary,
                    ),
                  )
                : OutlinedButton(
                    onPressed: _toggleFollow,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      minimumSize: const Size(0, 36),
                      backgroundColor: _isFollowing
                          ? c.muted.withValues(alpha: 0.3)
                          : Colors.transparent,
                      side: BorderSide(
                        color: _isFollowing
                            ? c.border.withValues(alpha: 0.5)
                            : primary,
                        width: _isFollowing ? 1 : 1.5,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      _isFollowing ? 'Obuna bo\'lindi' : 'Obuna',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _isFollowing ? c.mutedForeground : primary,
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
