import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/profile_model.dart';
import '../providers/profile_provider.dart';

/// Web parity: ProfilePage "Follow/Following" + "Message" button pair shown when
/// viewing another user's profile. Optimistic toggle of the `follows` row.
class FollowMessageButtons extends ConsumerStatefulWidget {
  final FullProfile profile;
  const FollowMessageButtons({super.key, required this.profile});

  @override
  ConsumerState<FollowMessageButtons> createState() => _FollowMessageButtonsState();
}

class _FollowMessageButtonsState extends ConsumerState<FollowMessageButtons> {
  bool _busy = false;

  Future<void> _toggle(bool currentlyFollowing) async {
    final me = ref.read(authProvider).user?.id;
    if (me == null || _busy) return;
    setState(() => _busy = true);
    HapticFeedback.selectionClick();
    try {
      await ref
          .read(profileRepositoryProvider)
          .toggleFollow(me, widget.profile.id, currentlyFollowing);
      ref.invalidate(isFollowingProvider(widget.profile.id));
      ref.invalidate(profileProvider(widget.profile.id));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Xato: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final followingAsync = ref.watch(isFollowingProvider(widget.profile.id));
    final isFollowing = followingAsync.maybeWhen(data: (v) => v, orElse: () => false);

    return Wrap(
      spacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          height: 36,
          child: isFollowing
              ? OutlinedButton(
                  onPressed: _busy ? null : () => _toggle(true),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: c.border),
                    foregroundColor: c.foreground,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(_busy ? '...' : 'Obuna bo\'lingan',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                )
              : FilledButton(
                  onPressed: _busy ? null : () => _toggle(false),
                  style: FilledButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(_busy ? '...' : 'Obuna',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
        ),
        Tooltip(
          message: 'Xabar yozish',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => context.push('/messages/${widget.profile.id}'),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: c.background,
                  border: Border.all(color: c.border),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(LucideIcons.messageCircle, size: 16, color: c.foreground),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
