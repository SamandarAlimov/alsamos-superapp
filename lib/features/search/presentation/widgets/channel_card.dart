import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/widgets/verified_badge.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../../../shared/widgets/error_mapper.dart';

/// Channel/Group card for search results with avatar, stats, and join button
class ChannelCard extends ConsumerStatefulWidget {
  final Map<String, dynamic> channel;
  final bool isGroup;

  const ChannelCard({
    super.key,
    required this.channel,
    this.isGroup = false,
  });

  @override
  ConsumerState<ChannelCard> createState() => _ChannelCardState();
}

class _ChannelCardState extends ConsumerState<ChannelCard> {
  bool _isJoined = false;
  bool _isLoading = true;

  String get _id => widget.channel['id']?.toString() ?? '';
  String get _name => widget.channel['name']?.toString() ?? 'Channel';
  String? get _avatarUrl => widget.channel['avatar_url']?.toString();
  int get _subscriberCount => widget.channel['subscriber_count'] ?? 0;
  bool get _isVerified => widget.channel['is_verified'] == true;

  @override
  void initState() {
    super.initState();
    _checkMembershipStatus();
  }

  Future<void> _checkMembershipStatus() async {
    try {
      final supa = Supabase.instance.client;
      final userId = supa.auth.currentUser?.id;
      if (userId == null) {
        setState(() => _isLoading = false);
        return;
      }

      final response = await supa
          .from('channel_members')
          .select()
          .eq('channel_id', _id)
          .eq('user_id', userId)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _isJoined = response != null;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error checking membership: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String get _subscriberLabel {
    if (_subscriberCount >= 1000000) {
      return '${(_subscriberCount / 1000000).toStringAsFixed(1)}M a\'zo';
    }
    if (_subscriberCount >= 1000) {
      return '${(_subscriberCount / 1000).toStringAsFixed(1)}K a\'zo';
    }
    return '$_subscriberCount a\'zo';
  }

  // Mock last activity (TODO: add to database schema)
  String get _lastActivity {
    final hash = _id.hashCode % 24;
    if (hash == 0) return 'Hozir';
    if (hash < 6) return '$hash soat oldin';
    return '${hash ~/ 6} kun oldin';
  }

  Future<void> _toggleJoin() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);

    // Optimistic update
    final wasJoined = _isJoined;
    setState(() => _isJoined = !_isJoined);

    try {
      final supa = Supabase.instance.client;
      final userId = supa.auth.currentUser?.id;
      if (userId == null) throw Exception('Not authenticated');

      if (_isJoined) {
        // Join channel
        await supa.from('channel_members').insert({
          'channel_id': _id,
          'user_id': userId,
          'role': 'member',
        });
      } else {
        // Leave channel
        await supa
            .from('channel_members')
            .delete()
            .eq('channel_id', _id)
            .eq('user_id', userId);
      }

      if (!mounted) return;
      AppToast.success(context,
          _isJoined ? 'Kanalga qo\'shildingiz' : 'Kanaldan chiqdingiz');
    } catch (e) {
      // Rollback on error
      if (mounted) {
        setState(() => _isJoined = wasJoined);
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
      onTap: () => context.push('/channel/$_id'),
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
            // Avatar/thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _avatarUrl != null
                  ? CachedNetworkImage(
                      imageUrl: _avatarUrl!,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        width: 48,
                        height: 48,
                        color: primary.withValues(alpha: 0.1),
                        child: Icon(
                          widget.isGroup
                              ? LucideIcons.users
                              : LucideIcons.radio,
                          color: primary,
                          size: 24,
                        ),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        width: 48,
                        height: 48,
                        color: primary.withValues(alpha: 0.1),
                        child: Icon(
                          widget.isGroup
                              ? LucideIcons.users
                              : LucideIcons.radio,
                          color: primary,
                          size: 24,
                        ),
                      ),
                    )
                  : Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        widget.isGroup ? LucideIcons.users : LucideIcons.radio,
                        color: primary,
                        size: 24,
                      ),
                    ),
            ),
            const SizedBox(width: 12),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name + verified
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          _name,
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
                  // Subscribers + last activity
                  Text(
                    '$_subscriberLabel · $_lastActivity',
                    style: TextStyle(
                      fontSize: 12,
                      color: c.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Join button
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
                    onPressed: _toggleJoin,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      minimumSize: const Size(0, 36),
                      backgroundColor: _isJoined
                          ? c.muted.withValues(alpha: 0.3)
                          : Colors.transparent,
                      side: BorderSide(
                        color: _isJoined
                            ? c.border.withValues(alpha: 0.5)
                            : primary,
                        width: _isJoined ? 1 : 1.5,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      _isJoined ? 'Qo\'shilgan' : 'Qo\'shilish',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _isJoined ? c.mutedForeground : primary,
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
