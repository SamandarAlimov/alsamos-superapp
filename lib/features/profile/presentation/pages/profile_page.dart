import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../../shared/widgets/alsamos_refresh_indicator.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../data/bookmarks_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../home/presentation/widgets/post_view_modal.dart';
import '../../../stories/presentation/providers/highlights_provider.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../../../shared/widgets/verified_badge.dart';
import '../../../../shared/widgets/username_qr_dialog.dart';
import '../../../../shared/widgets/skeleton_shimmer.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../data/profile_model.dart';
import '../providers/profile_provider.dart';
import '../widgets/follow_message_buttons.dart';
import '../widgets/edit_profile_dialog.dart';

String _fmt(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
  return '$n';
}

String _mediaPath(String url) => Uri.tryParse(url)?.path ?? url;

bool _hasMediaExt(String? url, String pattern) {
  if (url == null || url.isEmpty) return false;
  return RegExp(pattern, caseSensitive: false).hasMatch(_mediaPath(url));
}

bool _gridMediaIsImage(String? url) => _hasMediaExt(
      url,
      r'\.(jpg|jpeg|png|gif|webp|bmp|heic|heif)$',
    );

bool _gridMediaIsVideo(String? mediaType, String? url) {
  if (_gridMediaIsImage(url)) return false;
  if (_hasMediaExt(url, r'\.(mp4|webm|mov|m4v|avi|mkv|flv|wmv)$')) {
    return true;
  }
  final kind = mediaType?.toLowerCase().trim();
  return kind == 'video' || kind == 'reel' || kind == 'short';
}

/// Pixel-perfect port of web pages/ProfilePage.tsx.
///
/// Web reference: rounded-2xl cover (h-36 sm:h-48 md:h-64) + gradient fallback,
/// pill "Cover o'zgartirish" button bottom-right, story-ring avatar overlapping
/// cover, name+@username+verified, Edit/Ads/Archive buttons, bio + meta row
/// (location/website/joined date), stats with border-y, story highlights row,
/// 4 tabs (Posts/Videos/Reposts/Saved) with primary underline + 3-col grid.
class ProfilePage extends ConsumerStatefulWidget {
  final String? userId;
  const ProfilePage({super.key, this.userId});
  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  int _tab = 0;
  bool _uploadingCover = false;
  bool _uploadingAvatar = false;

  static const _tabs = [
    (LucideIcons.layoutGrid, 'Postlar'),
    (LucideIcons.video, 'Videolar'),
    (LucideIcons.repeat2, 'Repostlar'),
    (LucideIcons.bookmark, 'Saqlangan'),
  ];

  Future<void> _pickAndUploadCover(String userId) async {
    final picker = ImagePicker();
    final img =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (img == null || !mounted) return;
    setState(() => _uploadingCover = true);
    try {
      final file = File(img.path);
      final ext = img.path.split('.').last;
      final path =
          '$userId/cover-${DateTime.now().millisecondsSinceEpoch}.$ext';
      final supabase = Supabase.instance.client;
      await supabase.storage.from('message-attachments').upload(path, file);
      final url =
          supabase.storage.from('message-attachments').getPublicUrl(path);
      await supabase
          .from('profiles')
          .update({'cover_url': url}).eq('id', userId);
      if (mounted) {
        ref.invalidate(profileProvider(widget.userId));
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cover rasm yangilandi')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Xato: $e')));
      }
    } finally {
      if (mounted) setState(() => _uploadingCover = false);
    }
  }

  Future<void> _pickAndUploadAvatar(String userId) async {
    final picker = ImagePicker();
    final img =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (img == null || !mounted) return;
    setState(() => _uploadingAvatar = true);
    try {
      final file = File(img.path);
      final ext = img.path.split('.').last;
      final path =
          '$userId/avatar-${DateTime.now().millisecondsSinceEpoch}.$ext';
      final supabase = Supabase.instance.client;
      await supabase.storage.from('message-attachments').upload(path, file);
      final url =
          supabase.storage.from('message-attachments').getPublicUrl(path);
      await supabase
          .from('profiles')
          .update({'avatar_url': url}).eq('id', userId);
      if (mounted) {
        ref.invalidate(profileProvider(widget.userId));
        ref.invalidate(authProvider);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profil rasmi yangilandi')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Xato: $e')));
      }
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final me = ref.watch(authProvider).user?.id;
    final profileAsync = ref.watch(profileProvider(widget.userId));

    return Scaffold(
      backgroundColor: c.background,
      body: profileAsync.when(
        loading: () => const _ProfileSkeleton(),
        error: (e, _) => Center(
          child:
              Text('Xatolik: $e', style: TextStyle(color: c.mutedForeground)),
        ),
        data: (profile) {
          if (profile == null) {
            return Center(
              child: Text('Profil topilmadi',
                  style: TextStyle(color: c.mutedForeground)),
            );
          }
          final isOwn = profile.id == me;
          final postsAsync = ref.watch(userPostsProvider(profile.id));
          final highlightsAsync = ref.watch(highlightsProvider(profile.id));
          // v36: brand orange `AlsamosRefreshIndicator`
          return AlsamosRefreshIndicator(
            onRefresh: () async {
              ref.invalidate(profileProvider(widget.userId));
              ref.invalidate(userPostsProvider(profile.id));
              ref.invalidate(highlightsProvider(profile.id));
              await Future.delayed(const Duration(milliseconds: 400));
            },
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 896),
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 12),
                          _CoverAndAvatar(
                            profile: profile,
                            isOwn: isOwn,
                            uploadingCover: _uploadingCover,
                            uploadingAvatar: _uploadingAvatar,
                            onPickCover: () => _pickAndUploadCover(profile.id),
                            onPickAvatar: () =>
                                _pickAndUploadAvatar(profile.id),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 56),
                                _NameAndActions(
                                  profile: profile,
                                  isOwn: isOwn,
                                  onEdit: () =>
                                      EditProfileDialog.show(context, profile),
                                  onAds: () => context.push('/ads'),
                                  onArchive: () =>
                                      context.push('/story-archive'),
                                ),
                                if (profile.bio != null &&
                                    profile.bio!.trim().isNotEmpty) ...[
                                  const SizedBox(height: 14),
                                  Text(
                                    profile.bio!,
                                    style: TextStyle(
                                        color: c.foreground,
                                        fontSize: 14,
                                        height: 1.55),
                                  ),
                                ],
                                const SizedBox(height: 12),
                                _MetaRow(profile: profile, c: c),
                                const SizedBox(height: 16),
                                _StatsBar(
                                  profile: profile,
                                  onFollowers: () => _openFollowDialog(
                                      context, profile,
                                      type: 'followers'),
                                  onFollowing: () => _openFollowDialog(
                                      context, profile,
                                      type: 'following'),
                                ),
                                const SizedBox(height: 16),
                                _Highlights(
                                  highlightsAsync: highlightsAsync,
                                  isOwn: isOwn,
                                ),
                                const SizedBox(height: 8),
                              ],
                            ),
                          ),
                          _TabBar(
                              active: _tab,
                              onChange: (i) {
                                HapticFeedback.selectionClick();
                                setState(() => _tab = i);
                              }),
                        ],
                      ),
                    ),
                    _TabBody(
                      tab: _tab,
                      postsAsync: postsAsync,
                      isOwn: isOwn,
                      c: c,
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 96)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _openFollowDialog(BuildContext context, FullProfile profile,
      {required String type}) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AlsamosColors.of(context).card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _FollowDialogStub(profileId: profile.id, type: type),
    );
  }
}

class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();
  @override
  Widget build(BuildContext context) {
    // v43: SkeletonShimmer reusable widget bilan refaktor
    return const SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonShimmer(
              height: 168, borderRadius: BorderRadius.all(Radius.circular(16))),
          SizedBox(height: 64),
          Row(children: [
            SkeletonShimmer.circle(96),
            SizedBox(width: 16),
            Expanded(
                child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonShimmer(
                    height: 20,
                    width: 180,
                    borderRadius: BorderRadius.all(Radius.circular(6))),
                SizedBox(height: 8),
                SkeletonShimmer(
                    height: 14,
                    width: 120,
                    borderRadius: BorderRadius.all(Radius.circular(6))),
              ],
            )),
          ]),
          SizedBox(height: 24),
          SkeletonShimmer(
              height: 14, borderRadius: BorderRadius.all(Radius.circular(6))),
          SizedBox(height: 8),
          SkeletonShimmer(
              height: 14,
              width: 260,
              borderRadius: BorderRadius.all(Radius.circular(6))),
          SizedBox(height: 24),
          Row(children: [
            Expanded(
                child: Column(
              children: [
                SkeletonShimmer(
                    height: 20,
                    width: 60,
                    borderRadius: BorderRadius.all(Radius.circular(6))),
                SizedBox(height: 6),
                SkeletonShimmer(
                    height: 12,
                    width: 80,
                    borderRadius: BorderRadius.all(Radius.circular(6))),
              ],
            )),
            SizedBox(width: 16),
            Expanded(
                child: Column(
              children: [
                SkeletonShimmer(
                    height: 20,
                    width: 60,
                    borderRadius: BorderRadius.all(Radius.circular(6))),
                SizedBox(height: 6),
                SkeletonShimmer(
                    height: 12,
                    width: 80,
                    borderRadius: BorderRadius.all(Radius.circular(6))),
              ],
            )),
            SizedBox(width: 16),
            Expanded(
                child: Column(
              children: [
                SkeletonShimmer(
                    height: 20,
                    width: 60,
                    borderRadius: BorderRadius.all(Radius.circular(6))),
                SizedBox(height: 6),
                SkeletonShimmer(
                    height: 12,
                    width: 80,
                    borderRadius: BorderRadius.all(Radius.circular(6))),
              ],
            )),
          ]),
        ],
      ),
    );
  }
}

class _CoverAndAvatar extends StatelessWidget {
  final FullProfile profile;
  final bool isOwn;
  final bool uploadingCover;
  final bool uploadingAvatar;
  final VoidCallback onPickCover;
  final VoidCallback onPickAvatar;
  const _CoverAndAvatar({
    required this.profile,
    required this.isOwn,
    required this.uploadingCover,
    required this.uploadingAvatar,
    required this.onPickCover,
    required this.onPickAvatar,
  });

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final w = MediaQuery.of(context).size.width;
    final coverH = w >= 768 ? 256.0 : (w >= 640 ? 192.0 : 168.0);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(w >= 768 ? 20 : 14),
            child: SizedBox(
              height: coverH,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (profile.coverUrl != null && profile.coverUrl!.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: profile.coverUrl!,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(color: c.muted),
                      errorWidget: (_, __, ___) => const DecoratedBox(
                        decoration:
                            BoxDecoration(gradient: AppColors.gradientPrimary),
                      ),
                    )
                  else
                    const DecoratedBox(
                        decoration:
                            BoxDecoration(gradient: AppColors.gradientPrimary)),
                  DecoratedBox(
                      decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        c.background.withValues(alpha: 0.5),
                        Colors.transparent
                      ],
                    ),
                  )),
                  // Back button (only when can pop)
                  if (Navigator.of(context).canPop())
                    Positioned(
                      top: 10,
                      left: 10,
                      child: _PillIconButton(
                        icon: LucideIcons.arrowLeft,
                        onTap: () => context.pop(),
                      ),
                    ),
                  // Cover edit pill
                  if (isOwn)
                    Positioned(
                      bottom: 12,
                      right: 12,
                      child: _CoverEditPill(
                        uploading: uploadingCover,
                        onTap: onPickCover,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        // Avatar with gradient story ring overlapping cover
        Positioned(
          left: 24,
          bottom: -48,
          child: GestureDetector(
            onTap: isOwn ? onPickAvatar : null,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.gradientPrimary,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                        shape: BoxShape.circle, color: c.background),
                    child: UserAvatar(
                      avatarUrl: profile.avatarUrl,
                      fallback: profile.initial,
                      size: 88,
                    ),
                  ),
                ),
                if (isOwn)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: c.background, width: 2),
                      ),
                      child: uploadingAvatar
                          ? const Padding(
                              padding: EdgeInsets.all(6),
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Icon(LucideIcons.camera,
                              color: Colors.white, size: 14),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PillIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _PillIconButton({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkResponse(
        onTap: onTap,
        radius: 22,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      ),
    );
  }
}

class _CoverEditPill extends StatelessWidget {
  final bool uploading;
  final VoidCallback onTap;
  const _CoverEditPill({required this.uploading, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: uploading ? null : onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (uploading)
                const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
              else
                const Icon(LucideIcons.camera, color: Colors.white, size: 14),
              const SizedBox(width: 6),
              Text(
                uploading ? 'Yuklanmoqda...' : "Cover o'zgartirish",
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NameAndActions extends StatelessWidget {
  final FullProfile profile;
  final bool isOwn;
  final VoidCallback onEdit;
  final VoidCallback onAds;
  final VoidCallback onArchive;
  const _NameAndActions({
    required this.profile,
    required this.isOwn,
    required this.onEdit,
    required this.onAds,
    required this.onArchive,
  });

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      profile.displayName ?? profile.username ?? 'User',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 22),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (profile.isVerified) ...[
                    const SizedBox(width: 6),
                    const VerifiedBadge(size: 18),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(
                  child: Text('@${profile.username ?? 'user'}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.mutedForeground, fontSize: 14)),
                ),
                const SizedBox(width: 4),
                InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => UsernameQrDialog.show(
                    context,
                    title: profile.displayName ?? profile.username ?? 'Alsamos',
                    subtitle: '@${profile.username ?? 'user'}',
                    data: 'https://alsamos.app/user/${profile.username ?? profile.id}',
                    avatarUrl: profile.avatarUrl,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(LucideIcons.qrCode, size: 15, color: c.mutedForeground),
                  ),
                ),
              ]),
            ],
          ),
        ),
        const SizedBox(width: 8),
        if (isOwn)
          _OwnActions(onEdit: onEdit, onAds: onAds, onArchive: onArchive)
        else
          FollowMessageButtons(profile: profile),
      ],
    );
  }
}

class _OwnActions extends StatelessWidget {
  final VoidCallback onEdit;
  final VoidCallback onAds;
  final VoidCallback onArchive;
  const _OwnActions(
      {required this.onEdit, required this.onAds, required this.onArchive});
  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final c = AlsamosColors.of(context);
    return Wrap(
      spacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilledButton.icon(
          onPressed: onEdit,
          icon: const Icon(LucideIcons.edit3, size: 14),
          label: const Text('Tahrirlash', style: TextStyle(fontSize: 13)),
          style: FilledButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            minimumSize: const Size(0, 36),
          ),
        ),
        _SquareIconButton(
            icon: LucideIcons.megaphone,
            onTap: onAds,
            tooltip: 'Reklama',
            c: c),
        _SquareIconButton(
            icon: LucideIcons.archive,
            onTap: onArchive,
            tooltip: 'Arxiv',
            c: c),
      ],
    );
  }
}

class _SquareIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final AlsamosColors c;
  const _SquareIconButton(
      {required this.icon,
      required this.onTap,
      required this.tooltip,
      required this.c});
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: c.background,
              border: Border.all(color: c.border),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 16, color: c.foreground),
          ),
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final FullProfile profile;
  final AlsamosColors c;
  const _MetaRow({required this.profile, required this.c});

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    if (profile.location != null && profile.location!.trim().isNotEmpty) {
      items.add(_metaItem(LucideIcons.mapPin, profile.location!, c));
    }
    if (profile.website != null && profile.website!.trim().isNotEmpty) {
      final clean = profile.website!.replaceFirst(RegExp(r'^https?://'), '');
      items.add(_metaItem(LucideIcons.link, clean, c,
          color: Theme.of(context).colorScheme.primary));
    }
    if (profile.createdAt != null) {
      final joined = DateFormat.yMMMM().format(profile.createdAt!);
      items.add(_metaItem(LucideIcons.calendar, joined, c));
    }
    if (items.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 16,
      runSpacing: 6,
      children: items,
    );
  }

  Widget _metaItem(IconData icon, String text, AlsamosColors c,
      {Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color ?? c.mutedForeground),
        const SizedBox(width: 4),
        Text(text,
            style: TextStyle(color: color ?? c.mutedForeground, fontSize: 13)),
      ],
    );
  }
}

class _StatsBar extends ConsumerWidget {
  final FullProfile profile;
  final VoidCallback onFollowers;
  final VoidCallback onFollowing;
  const _StatsBar(
      {required this.profile,
      required this.onFollowers,
      required this.onFollowing});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AlsamosColors.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: c.border, width: 0.5),
          bottom: BorderSide(color: c.border, width: 0.5),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatItem(
              value: _fmt(profile.postsCount), label: 'Postlar', onTap: () {}),
          _StatItem(
              value: _fmt(profile.followersCount),
              label: 'Obunachilar',
              onTap: onFollowers),
          _StatItem(
              value: _fmt(profile.followingCount),
              label: 'Obunalar',
              onTap: onFollowing),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String value;
  final String label;
  final VoidCallback onTap;
  const _StatItem(
      {required this.value, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(value,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(fontSize: 12, color: c.mutedForeground)),
          ],
        ),
      ),
    );
  }
}

class _Highlights extends StatelessWidget {
  final AsyncValue<List<StoryHighlight>> highlightsAsync;
  final bool isOwn;
  const _Highlights({required this.highlightsAsync, required this.isOwn});

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    return highlightsAsync.when(
      loading: () => SizedBox(
        height: 86,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: 5,
          padding: const EdgeInsets.symmetric(vertical: 8),
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (_, __) => Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: c.muted, shape: BoxShape.circle),
          ),
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (items) {
        if (items.isEmpty && !isOwn) return const SizedBox.shrink();
        return SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: items.length + (isOwn ? 1 : 0),
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (_, i) {
              if (isOwn && i == items.length) {
                return _HighlightBubble.add(
                    onTap: () =>
                        Navigator.of(context).pushNamed('/highlights/new'));
              }
              final h = items[i];
              return _HighlightBubble(
                title: h.name,
                coverUrl: h.coverUrl,
                onTap: () =>
                    Navigator.of(context).pushNamed('/highlight/${h.id}'),
              );
            },
          ),
        );
      },
    );
  }
}

class _HighlightBubble extends StatelessWidget {
  final String title;
  final String? coverUrl;
  final VoidCallback onTap;
  final bool isAdd;
  const _HighlightBubble({
    required this.title,
    required this.coverUrl,
    required this.onTap,
  }) : isAdd = false;
  const _HighlightBubble.add({required this.onTap})
      : title = "Qo'shish",
        coverUrl = null,
        isAdd = true;

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(40),
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: isAdd ? null : AppColors.gradientPrimary,
                color: isAdd ? c.muted : null,
              ),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration:
                    BoxDecoration(shape: BoxShape.circle, color: c.background),
                child: ClipOval(
                  child: SizedBox(
                    width: 52,
                    height: 52,
                    child: isAdd
                        ? Icon(LucideIcons.plus, color: primary, size: 22)
                        : (coverUrl != null && coverUrl!.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: coverUrl!, fit: BoxFit.cover)
                            : Container(
                                color: c.muted,
                                child: const Icon(LucideIcons.image,
                                    size: 22, color: Colors.white70))),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: c.foreground)),
          ],
        ),
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  final int active;
  final ValueChanged<int> onChange;
  const _TabBar({required this.active, required this.onChange});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final c = AlsamosColors.of(context);
    final wide = MediaQuery.of(context).size.width >= 640;
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border, width: 0.5)),
      ),
      child: Row(
        children: List.generate(_ProfilePageState._tabs.length, (i) {
          final isActive = active == i;
          return Expanded(
            child: InkWell(
              onTap: () => onChange(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: isActive ? primary : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(_ProfilePageState._tabs[i].$1,
                        size: 18,
                        color: isActive ? primary : c.mutedForeground),
                    if (wide) ...[
                      const SizedBox(width: 6),
                      Text(_ProfilePageState._tabs[i].$2,
                          style: TextStyle(
                              fontSize: 13,
                              color: isActive ? primary : c.mutedForeground,
                              fontWeight: isActive
                                  ? FontWeight.w600
                                  : FontWeight.w500)),
                    ],
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _TabBody extends ConsumerWidget {
  final int tab;
  final AsyncValue postsAsync;
  final bool isOwn;
  final AlsamosColors c;
  const _TabBody(
      {required this.tab,
      required this.postsAsync,
      required this.isOwn,
      required this.c});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (tab == 2) {
      return _emptySliver(
          LucideIcons.repeat2,
          'Repostlar yo\'q',
          isOwn
              ? 'Yoqqan kontentni repost qiling!'
              : 'Hech narsa repost qilinmagan');
    }
    if (tab == 3) {
      if (!isOwn) {
        return _emptySliver(LucideIcons.bookmark, 'Saqlangan postlar yo\'q',
            'Saqlangan postlar faqat egasiga ko\'rinadi');
      }
      final bookmarksAsync = ref.watch(bookmarksProvider);
      return bookmarksAsync.when(
        loading: () => const SliverToBoxAdapter(
            child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()))),
        error: (e, _) => SliverToBoxAdapter(
            child: Center(
                child: Text('$e', style: TextStyle(color: c.mutedForeground)))),
        data: (list) {
          if (list.isEmpty) {
            return _emptySliver(LucideIcons.bookmark, 'Saqlangan postlar yo\'q',
                'Postlarni keyinroq ko\'rish uchun bookmark qiling');
          }
          return SliverPadding(
            padding: const EdgeInsets.all(2),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3, crossAxisSpacing: 2, mainAxisSpacing: 2),
              delegate: SliverChildBuilderDelegate(
                (ctx, i) {
                  final post = list[i];
                  final media =
                      (post.mediaUrls != null && post.mediaUrls!.isNotEmpty)
                          ? post.mediaUrls!.first as String
                          : null;
                  return _PostGridTile(
                    mediaUrl: media,
                    content: post.content,
                    isVideo: _gridMediaIsVideo(post.mediaType, media),
                    hasMultiple: (post.mediaUrls?.length ?? 0) > 1,
                    likesCount: post.likesCount,
                    commentsCount: post.commentsCount,
                    c: c,
                    onTap: () => GoRouter.of(ctx).push('/post/${post.id}'),
                  );
                },
                childCount: list.length,
              ),
            ),
          );
        },
      );
    }
    return postsAsync.when(
      loading: () => const SliverToBoxAdapter(
          child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()))),
      error: (e, _) => SliverToBoxAdapter(
          child: Center(
              child: Text('$e', style: TextStyle(color: c.mutedForeground)))),
      data: (posts) {
        final list = (posts as List);
        final filtered = tab == 1
            ? list.where((p) => p.mediaType == 'video').toList()
            : list;
        if (filtered.isEmpty) {
          return _emptySliver(
            tab == 1 ? LucideIcons.video : LucideIcons.layoutGrid,
            tab == 1 ? 'Videolar yo\'q' : 'Postlar yo\'q',
            isOwn ? 'Birinchi postingizni yarating!' : 'Hozircha post yo\'q',
            actionLabel: isOwn ? 'Birinchi post qo\'shish' : null,
            onAction: isOwn ? () => GoRouter.of(context).push('/create') : null,
          );
        }
        return SliverPadding(
          padding: const EdgeInsets.all(2),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3, crossAxisSpacing: 2, mainAxisSpacing: 2),
            delegate: SliverChildBuilderDelegate(
              (ctx, i) {
                final post = filtered[i];
                final mediaList = post.mediaUrls as List?;
                final media = (mediaList != null && mediaList.isNotEmpty)
                    ? mediaList.first as String
                    : null;
                final isVideo = _gridMediaIsVideo(post.mediaType, media);
                final hasMultiple = (mediaList?.length ?? 0) > 1;
                return _PostGridTile(
                  mediaUrl: media,
                  content: post.content as String?,
                  isVideo: isVideo,
                  hasMultiple: hasMultiple,
                  likesCount: (post.likesCount as int?) ?? 0,
                  commentsCount: (post.commentsCount as int?) ?? 0,
                  c: c,
                  onTap: () => PostViewModal.show(
                    ctx,
                    post: post,
                    isOwnProfile: isOwn,
                  ),
                );
              },
              childCount: filtered.length,
            ),
          ),
        );
      },
    );
  }

  Widget _emptySliver(IconData icon, String title, String subtitle,
      {String? actionLabel, VoidCallback? onAction}) {
    // v42: EmptyState widget bilan delegatsiya — a11y Semantics bilan
    return SliverToBoxAdapter(
      child: EmptyState(
        icon: icon,
        title: title,
        subtitle: subtitle,
        ctaLabel: actionLabel,
        onCta: onAction,
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      ),
    );
  }
}

class _PostGridTile extends StatefulWidget {
  final String? mediaUrl;
  final String? content;
  final bool isVideo;
  final bool hasMultiple;
  final int likesCount;
  final int commentsCount;
  final AlsamosColors c;
  final VoidCallback onTap;
  const _PostGridTile({
    required this.mediaUrl,
    required this.content,
    required this.isVideo,
    required this.hasMultiple,
    required this.likesCount,
    required this.commentsCount,
    required this.c,
    required this.onTap,
  });
  @override
  State<_PostGridTile> createState() => _PostGridTileState();
}

class _PostGridTileState extends State<_PostGridTile> {
  bool _hover = false;

  Widget _textFallback() {
    final c = widget.c;
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Center(
        child: Text(
          widget.content ?? 'No content',
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: c.foreground),
        ),
      ),
    );
  }

  Widget _mediaFallback({required IconData icon}) {
    final c = widget.c;
    return Container(
      color: c.muted,
      child: Center(
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white24),
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          color: c.muted,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (widget.mediaUrl != null && widget.isVideo)
                _mediaFallback(icon: LucideIcons.play)
              else if (widget.mediaUrl != null)
                CachedNetworkImage(
                  imageUrl: widget.mediaUrl!,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(color: c.muted),
                  errorWidget: (_, __, ___) =>
                      _mediaFallback(icon: LucideIcons.imageOff),
                )
              else
                _textFallback(),
              if (widget.isVideo)
                const Center(
                    child:
                        Icon(LucideIcons.play, color: Colors.white, size: 28)),
              if (widget.hasMultiple)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(LucideIcons.copy,
                        color: Colors.white, size: 12),
                  ),
                ),
              // Hover overlay with stats
              AnimatedOpacity(
                opacity: _hover ? 1 : 0,
                duration: const Duration(milliseconds: 150),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.5),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(LucideIcons.heart,
                          color: Colors.white, size: 16),
                      const SizedBox(width: 4),
                      Text('${widget.likesCount}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(width: 12),
                      const Icon(LucideIcons.messageCircle,
                          color: Colors.white, size: 16),
                      const SizedBox(width: 4),
                      Text('${widget.commentsCount}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FollowDialogStub extends StatelessWidget {
  final String profileId;
  final String type;
  const _FollowDialogStub({required this.profileId, required this.type});
  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: c.muted,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              type == 'followers' ? 'Obunachilar' : 'Obunalar',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            // v37: "Tez orada" o'rniga real empty state — ikona + tushuntirish + CTA
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
              child: Center(
                child: Column(children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: c.muted,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      type == 'followers'
                          ? Icons.people_outline
                          : Icons.person_add_alt_1,
                      size: 32,
                      color: c.mutedForeground,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    type == 'followers'
                        ? "Hozircha obunachilar yo\u2018q"
                        : "Hech kimga obuna bo\u2018lmagansiz",
                    style: TextStyle(
                        color: c.foreground,
                        fontSize: 14,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    type == 'followers'
                        ? "Postlar va kontent yarating \u2014 odamlar sizni topishadi."
                        : "Qiziqarli mualliflarni topish uchun Discover sahifasiga o\u2018ting.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.mutedForeground, fontSize: 12),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
