import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../shared/content/utils/content_metadata.dart';
import '../../../../shared/navigation/app_routes.dart';
import '../../../../shared/stories/story_avatar_ring.dart';
import '../../../../shared/widgets/alsamos_refresh_indicator.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/error_mapper.dart';
import '../../../../shared/widgets/skeleton_shimmer.dart';
import '../../../../shared/widgets/username_qr_dialog.dart';
import '../../../../shared/widgets/verified_badge.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../home/data/models/post_model.dart';
import '../../../home/presentation/widgets/post_view_modal.dart';
import '../../../stories/presentation/widgets/story_highlights.dart';
import '../../data/bookmarks_provider.dart';
import '../../data/profile_model.dart';
import '../../data/user_block_service.dart';
import '../providers/profile_provider.dart';
import '../widgets/edit_profile_dialog.dart';
import 'profile_photo_viewer.dart';

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
  if (_hasMediaExt(url, r'\.(mp4|webm|mov|m4v|avi|mkv|flv|wmv)$')) return true;
  final kind = mediaType?.toLowerCase().trim();
  return kind == 'video' || kind == 'reel' || kind == 'short';
}

bool _looksLikeUuid(String value) =>
    RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
        .hasMatch(value);

/// Unified Profile Page used for every user in the application.
///
/// Pass [userId] for direct UUID-based access, or [usernameOrId] for
/// username/UUID resolution. When both are null, shows the current user's
/// profile.
///
/// The layout is identical for all users — only action buttons and editable
/// functionality change based on ownership.
class ProfilePage extends ConsumerStatefulWidget {
  final String? userId;
  final String? usernameOrId;
  const ProfilePage({super.key, this.userId, this.usernameOrId});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  int _tab = 0;
  bool _uploadingCover = false;
  bool _uploadingAvatar = false;
  bool _followBusy = false;
  bool _blockBusy = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  String? get _resolvedUserId {
    if (widget.userId != null) return widget.userId;
    if (widget.usernameOrId != null && _looksLikeUuid(widget.usernameOrId!)) {
      return widget.usernameOrId;
    }
    return null;
  }

  String? get _resolvedUsername {
    if (widget.usernameOrId != null && !_looksLikeUuid(widget.usernameOrId!)) {
      return widget.usernameOrId;
    }
    return null;
  }

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
        ref.invalidate(profileProvider(_resolvedUserId));
        AppToast.success(context, 'Cover rasm yangilandi');
      }
    } catch (e) {
      if (mounted) AppToast.error(context, friendlyError(e));
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
      final insertRes = await supabase
          .from('profile_photo_history')
          .insert({
            'user_id': userId,
            'photo_url': url,
            'is_current': false,
          })
          .select()
          .single();
      await supabase.rpc('set_current_profile_photo', params: {
        'p_user_id': userId,
        'p_photo_id': insertRes['id'],
        'p_photo_url': url,
      });
      if (mounted) {
        ref.invalidate(profileProvider(_resolvedUserId));
        ref.invalidate(authProvider);
        AppToast.success(context, 'Profil rasmi yangilandi');
      }
    } catch (e) {
      if (mounted) AppToast.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _toggleFollow(FullProfile profile, bool currentlyFollowing) async {
    final me = ref.read(authProvider).user?.id;
    if (me == null || _followBusy) return;
    setState(() => _followBusy = true);
    HapticFeedback.selectionClick();
    try {
      await ref
          .read(profileRepositoryProvider)
          .toggleFollow(me, profile.id, currentlyFollowing);
      ref.invalidate(isFollowingProvider(profile.id));
      ref.invalidate(profileProvider(profile.id));
      if (mounted) {
        AppToast.success(
          context,
          currentlyFollowing
              ? '${profile.title} - obuna bekor qilindi'
              : '${profile.title} - obuna bo\'lindi',
        );
      }
    } catch (e) {
      if (mounted) AppToast.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  Future<void> _toggleBlock(FullProfile profile) async {
    final me = ref.read(authProvider).user?.id;
    if (me == null || me == profile.id || _blockBusy) return;
    setState(() => _blockBusy = true);
    try {
      const service = UserBlockService();
      final current = await service.isBlocked(profile.id);
      await service.setBlocked(profile.id, !current);
      if (mounted) {
        AppToast.info(
          context,
          !current
              ? '${profile.title} bloklandi'
              : '${profile.title} blokdan chiqarildi',
        );
        setState(() {});
      }
    } finally {
      if (mounted) setState(() => _blockBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final me = ref.watch(authProvider).user?.id;

    if (_resolvedUsername != null) {
      return Scaffold(
        backgroundColor: c.background,
        body: FutureBuilder<FullProfile?>(
          future: ref
              .read(profileRepositoryProvider)
              .fetchProfile(username: _resolvedUsername),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const _ProfileSkeleton();
            }
            if (snap.data == null) {
              return const EmptyView(
                icon: LucideIcons.userX,
                title: 'Profil topilmadi',
              );
            }
            return _buildBody(snap.data!, me, c);
          },
        ),
      );
    }

    final profileAsync = ref.watch(profileProvider(_resolvedUserId));
    return Scaffold(
      backgroundColor: c.background,
      body: profileAsync.when(
        loading: () => const _ProfileSkeleton(),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(profileProvider(_resolvedUserId)),
        ),
        data: (profile) {
          if (profile == null) {
            return const EmptyView(
              icon: LucideIcons.userX,
              title: 'Profil topilmadi',
            );
          }
          return _buildBody(profile, me, c);
        },
      ),
    );
  }

  Widget _buildBody(FullProfile profile, String? me, AlsamosColors c) {
    final isOwn = profile.id == me;
    final postsAsync = ref.watch(userPostsProvider(profile.id));
    final tabs = _buildTabs(isOwn);

    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      thickness: 8,
      radius: const Radius.circular(4),
      child: AlsamosRefreshIndicator(
        onRefresh: () async {
          ref.invalidate(profileProvider(_resolvedUserId ?? profile.id));
          ref.invalidate(userPostsProvider(profile.id));
          await Future.delayed(const Duration(milliseconds: 400));
        },
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 896),
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
                        onPickAvatar: () => _pickAndUploadAvatar(profile.id),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 56),
                            _NameAndActions(
                              profile: profile,
                              isOwn: isOwn,
                              followBusy: _followBusy,
                              blockBusy: _blockBusy,
                              onEdit: () =>
                                  EditProfileDialog.show(context, profile),
                              onAds: () => context.push('/ads'),
                              onArchive: () => context.push('/story-archive'),
                              onFollowToggle: (following) =>
                                  _toggleFollow(profile, following),
                              onMessage: () => context
                                  .push('${AppRoutes.messages}/${profile.id}'),
                              onBlockToggle: () => _toggleBlock(profile),
                            ),
                            if (profile.bio != null &&
                                profile.bio!.trim().isNotEmpty) ...[
                              const SizedBox(height: 14),
                              Text(
                                profile.bio!,
                                style: TextStyle(
                                  color: c.foreground,
                                  fontSize: 14,
                                  height: 1.55,
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            _MetaRow(profile: profile),
                            const SizedBox(height: 16),
                            _StatsBar(
                              profile: profile,
                              onFollowers: () =>
                                  _openFollowSheet(context, profile, 'followers'),
                              onFollowing: () =>
                                  _openFollowSheet(context, profile, 'following'),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: StoryHighlights(userId: profile.id),
                      ),
                      const SizedBox(height: 8),
                      _TabBar(
                        tabs: tabs,
                        active: _tab,
                        onChange: (i) {
                          HapticFeedback.selectionClick();
                          setState(() => _tab = i);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _TabBody(
              tab: _tab,
              tabs: tabs,
              postsAsync: postsAsync,
              isOwn: isOwn,
              c: c,
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
            const SliverFillRemaining(
              hasScrollBody: false,
              child: SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  List<_ProfileTab> _buildTabs(bool isOwn) {
    return [
      const _ProfileTab(LucideIcons.layoutGrid, 'Postlar', 'posts'),
      const _ProfileTab(LucideIcons.video, 'Videolar', 'videos'),
      const _ProfileTab(LucideIcons.repeat2, 'Repostlar', 'reposts'),
      if (isOwn)
        const _ProfileTab(LucideIcons.bookmark, 'Saqlangan', 'saved'),
    ];
  }

  void _openFollowSheet(
      BuildContext context, FullProfile profile, String type) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AlsamosColors.of(context).card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _FollowSheet(profileId: profile.id, type: type),
    );
  }
}

class _ProfileTab {
  final IconData icon;
  final String label;
  final String key;
  const _ProfileTab(this.icon, this.label, this.key);
}

// ---------------------------------------------------------------------------
// SKELETON
// ---------------------------------------------------------------------------

class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();
  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonShimmer(
              height: 168,
              borderRadius: BorderRadius.all(Radius.circular(16))),
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
              ),
            ),
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
              child: Column(children: [
                SkeletonShimmer(
                    height: 20,
                    width: 60,
                    borderRadius: BorderRadius.all(Radius.circular(6))),
                SizedBox(height: 6),
                SkeletonShimmer(
                    height: 12,
                    width: 80,
                    borderRadius: BorderRadius.all(Radius.circular(6))),
              ]),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(children: [
                SkeletonShimmer(
                    height: 20,
                    width: 60,
                    borderRadius: BorderRadius.all(Radius.circular(6))),
                SizedBox(height: 6),
                SkeletonShimmer(
                    height: 12,
                    width: 80,
                    borderRadius: BorderRadius.all(Radius.circular(6))),
              ]),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(children: [
                SkeletonShimmer(
                    height: 20,
                    width: 60,
                    borderRadius: BorderRadius.all(Radius.circular(6))),
                SizedBox(height: 6),
                SkeletonShimmer(
                    height: 12,
                    width: 80,
                    borderRadius: BorderRadius.all(Radius.circular(6))),
              ]),
            ),
          ]),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// COVER + AVATAR
// ---------------------------------------------------------------------------

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
                          BoxDecoration(gradient: AppColors.gradientPrimary),
                    ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          c.background.withValues(alpha: 0.5),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                  if (Navigator.of(context).canPop())
                    Positioned(
                      top: 10,
                      left: 10,
                      child: _PillIconButton(
                        icon: LucideIcons.arrowLeft,
                        onTap: () => context.pop(),
                      ),
                    ),
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
        Positioned(
          left: 24,
          bottom: -48,
          child: GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ProfilePhotoViewer(
                    userId: profile.id,
                    initialAvatarUrl: profile.avatarUrl,
                  ),
                ),
              );
            },
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                StoryAvatarRing(
                  userId: profile.id,
                  avatarUrl: profile.avatarUrl,
                  fallback: profile.initial,
                  size: 96,
                  inactiveBorderColor: c.border,
                ),
                if (profile.isOnline)
                  Positioned(
                    right: 4,
                    bottom: 4,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: const Color(0xFF22C55E),
                        shape: BoxShape.circle,
                        border: Border.all(color: c.background, width: 3),
                      ),
                    ),
                  ),
                if (isOwn)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: onPickAvatar,
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
                                    color: Colors.white, strokeWidth: 2),
                              )
                            : const Icon(LucideIcons.camera,
                                color: Colors.white, size: 14),
                      ),
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
                      color: Colors.white, strokeWidth: 2),
                )
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

// ---------------------------------------------------------------------------
// NAME + ACTIONS
// ---------------------------------------------------------------------------

class _NameAndActions extends StatelessWidget {
  final FullProfile profile;
  final bool isOwn;
  final bool followBusy;
  final bool blockBusy;
  final VoidCallback onEdit;
  final VoidCallback onAds;
  final VoidCallback onArchive;
  final void Function(bool currentlyFollowing) onFollowToggle;
  final VoidCallback onMessage;
  final VoidCallback onBlockToggle;

  const _NameAndActions({
    required this.profile,
    required this.isOwn,
    required this.followBusy,
    required this.blockBusy,
    required this.onEdit,
    required this.onAds,
    required this.onArchive,
    required this.onFollowToggle,
    required this.onMessage,
    required this.onBlockToggle,
  });

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
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
                            fontWeight: FontWeight.w800,
                            fontSize: 22,
                            letterSpacing: -0.2,
                          ),
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
                      child: Text(
                        '@${profile.username ?? 'user'}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.mutedForeground,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => UsernameQrDialog.show(
                        context,
                        title: profile.displayName ??
                            profile.username ??
                            'Alsamos',
                        subtitle: '@${profile.username ?? 'user'}',
                        data:
                            'https://alsamos.app/user/${profile.username ?? profile.id}',
                        avatarUrl: profile.avatarUrl,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(LucideIcons.qrCode,
                            size: 15, color: c.mutedForeground),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (isOwn)
              _OwnerActions(
                  onEdit: onEdit, onAds: onAds, onArchive: onArchive)
            else
              _VisitorActions(
                profile: profile,
                followBusy: followBusy,
                blockBusy: blockBusy,
                onFollowToggle: onFollowToggle,
                onMessage: onMessage,
                onBlockToggle: onBlockToggle,
              ),
          ],
        ),
      ],
    );
  }
}

class _OwnerActions extends StatelessWidget {
  final VoidCallback onEdit;
  final VoidCallback onAds;
  final VoidCallback onArchive;
  const _OwnerActions({
    required this.onEdit,
    required this.onAds,
    required this.onArchive,
  });

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    return Wrap(
      spacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.alsamosOrange, AppColors.alsamosOrangeDark],
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onEdit,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.edit3, size: 14, color: Colors.white),
                    SizedBox(width: 6),
                    Text(
                      'Tahrirlash',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        _SquareIconBtn(
            icon: LucideIcons.megaphone,
            onTap: onAds,
            tooltip: 'Reklama',
            c: c),
        _SquareIconBtn(
            icon: LucideIcons.archive,
            onTap: onArchive,
            tooltip: 'Arxiv',
            c: c),
      ],
    );
  }
}

class _VisitorActions extends ConsumerWidget {
  final FullProfile profile;
  final bool followBusy;
  final bool blockBusy;
  final void Function(bool) onFollowToggle;
  final VoidCallback onMessage;
  final VoidCallback onBlockToggle;

  const _VisitorActions({
    required this.profile,
    required this.followBusy,
    required this.blockBusy,
    required this.onFollowToggle,
    required this.onMessage,
    required this.onBlockToggle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AlsamosColors.of(context);
    final followingAsync = ref.watch(isFollowingProvider(profile.id));
    final isFollowing =
        followingAsync.maybeWhen(data: (v) => v, orElse: () => false);

    return Wrap(
      spacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          height: 36,
          child: isFollowing
              ? OutlinedButton(
                  onPressed: followBusy ? null : () => onFollowToggle(true),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: c.border),
                    foregroundColor: c.foreground,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(
                    followBusy ? '...' : 'Obuna bo\'lingan',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                )
              : DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [
                      AppColors.alsamosOrange,
                      AppColors.alsamosOrangeDark,
                    ]),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: followBusy ? null : () => onFollowToggle(false),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 9),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(LucideIcons.userPlus,
                              size: 14, color: Colors.white),
                          const SizedBox(width: 6),
                          Text(
                            followBusy ? '...' : 'Obuna',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ),
        ),
        _SquareIconBtn(
          icon: LucideIcons.messageCircle,
          onTap: onMessage,
          tooltip: 'Xabar',
          c: c,
        ),
        _SquareIconBtn(
          icon: LucideIcons.moreHorizontal,
          onTap: () => _showMoreMenu(context),
          tooltip: 'Ko\'proq',
          c: c,
        ),
      ],
    );
  }

  void _showMoreMenu(BuildContext context) {
    final c = AlsamosColors.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: c.muted,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(LucideIcons.share2),
              title: const Text('Profilni ulashish'),
              onTap: () {
                Navigator.pop(context);
                Clipboard.setData(ClipboardData(
                  text:
                      'https://alsamos.app/user/${profile.username ?? profile.id}',
                ));
                AppToast.success(context, 'Havola nusxalandi');
              },
            ),
            ListTile(
              leading: Icon(LucideIcons.ban,
                  color: blockBusy ? c.mutedForeground : const Color(0xFFEF4444)),
              title: Text(
                'Bloklash',
                style: TextStyle(
                  color: blockBusy ? c.mutedForeground : const Color(0xFFEF4444),
                ),
              ),
              onTap: blockBusy
                  ? null
                  : () {
                      Navigator.pop(context);
                      onBlockToggle();
                    },
            ),
            ListTile(
              leading: const Icon(LucideIcons.flag, color: Color(0xFFEF4444)),
              title: const Text('Shikoyat qilish',
                  style: TextStyle(color: Color(0xFFEF4444))),
              onTap: () {
                Navigator.pop(context);
                AppToast.info(context, 'Shikoyat yuborildi');
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _SquareIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final AlsamosColors c;
  const _SquareIconBtn({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    required this.c,
  });
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

// ---------------------------------------------------------------------------
// META ROW (location, website, joined)
// ---------------------------------------------------------------------------

class _MetaRow extends StatelessWidget {
  final FullProfile profile;
  const _MetaRow({required this.profile});

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final items = <Widget>[];

    if (profile.location != null && profile.location!.trim().isNotEmpty) {
      items.add(_metaChip(LucideIcons.mapPin, profile.location!, c.mutedForeground));
    }
    if (profile.website != null && profile.website!.trim().isNotEmpty) {
      final clean = profile.website!.replaceFirst(RegExp(r'^https?://'), '');
      items.add(_metaChip(LucideIcons.link, clean, primary));
    }
    if (profile.createdAt != null) {
      final joined = DateFormat.yMMMM().format(profile.createdAt!);
      items.add(_metaChip(LucideIcons.calendar, joined, c.mutedForeground));
    }
    if (items.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 16, runSpacing: 6, children: items);
  }

  Widget _metaChip(IconData icon, String text, Color color) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 200),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// STATS BAR
// ---------------------------------------------------------------------------

class _StatsBar extends ConsumerWidget {
  final FullProfile profile;
  final VoidCallback onFollowers;
  final VoidCallback onFollowing;
  const _StatsBar({
    required this.profile,
    required this.onFollowers,
    required this.onFollowing,
  });

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
          _StatItem(value: _fmt(profile.postsCount), label: 'Postlar', onTap: () {}),
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
  const _StatItem({required this.value, required this.label, required this.onTap});
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
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 12, color: c.mutedForeground)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// TABS
// ---------------------------------------------------------------------------

class _TabBar extends StatelessWidget {
  final List<_ProfileTab> tabs;
  final int active;
  final ValueChanged<int> onChange;
  const _TabBar({required this.tabs, required this.active, required this.onChange});

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
        children: List.generate(tabs.length, (i) {
          final isActive = active == i;
          return Expanded(
            child: InkWell(
              onTap: () => onChange(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
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
                    Icon(tabs[i].icon,
                        size: 18,
                        color: isActive ? primary : c.mutedForeground),
                    if (wide) ...[
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          tabs[i].label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: isActive ? primary : c.mutedForeground,
                            fontWeight:
                                isActive ? FontWeight.w600 : FontWeight.w500,
                          ),
                        ),
                      ),
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

// ---------------------------------------------------------------------------
// TAB BODY
// ---------------------------------------------------------------------------

class _TabBody extends ConsumerWidget {
  final int tab;
  final List<_ProfileTab> tabs;
  final AsyncValue<List<Post>> postsAsync;
  final bool isOwn;
  final AlsamosColors c;
  const _TabBody({
    required this.tab,
    required this.tabs,
    required this.postsAsync,
    required this.isOwn,
    required this.c,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTab = tabs[tab];

    switch (currentTab.key) {
      case 'reposts':
        return _emptySliver(
          LucideIcons.repeat2,
          'Repostlar yo\'q',
          isOwn
              ? 'Yoqqan kontentni repost qiling!'
              : 'Hech narsa repost qilinmagan',
        );

      case 'saved':
        if (!isOwn) {
          return _emptySliver(LucideIcons.bookmark, 'Saqlangan postlar yo\'q',
              'Saqlangan postlar faqat egasiga ko\'rinadi');
        }
        final bookmarksAsync = ref.watch(bookmarksProvider);
        return bookmarksAsync.when(
          loading: () => const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
          error: (e, _) => SliverToBoxAdapter(
            child: Center(
              child: Text('$e', style: TextStyle(color: c.mutedForeground)),
            ),
          ),
          data: (list) {
            if (list.isEmpty) {
              return _emptySliver(LucideIcons.bookmark, 'Saqlangan postlar yo\'q',
                  'Postlarni keyinroq ko\'rish uchun bookmark qiling');
            }
            return _buildBookmarksGrid(list, context);
          },
        );

      case 'videos':
        return postsAsync.when(
          loading: () => const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
          error: (e, _) => SliverToBoxAdapter(
            child: Center(
              child: Text('$e', style: TextStyle(color: c.mutedForeground)),
            ),
          ),
          data: (posts) {
            final videos =
                posts.where((p) => p.mediaType == 'video').toList();
            if (videos.isEmpty) {
              return _emptySliver(
                LucideIcons.video,
                'Videolar yo\'q',
                isOwn ? 'Birinchi videongizni yuklang!' : 'Hozircha video yo\'q',
              );
            }
            return _buildPostsGrid(videos, context);
          },
        );

      default: // 'posts'
        return postsAsync.when(
          loading: () => const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
          error: (e, _) => SliverToBoxAdapter(
            child: Center(
              child: Text('$e', style: TextStyle(color: c.mutedForeground)),
            ),
          ),
          data: (posts) {
            if (posts.isEmpty) {
              return _emptySliver(
                LucideIcons.layoutGrid,
                'Postlar yo\'q',
                isOwn ? 'Birinchi postingizni yarating!' : 'Hozircha post yo\'q',
                actionLabel: isOwn ? 'Birinchi post qo\'shish' : null,
                onAction: isOwn ? () => GoRouter.of(context).push('/create') : null,
              );
            }
            return _buildPostsGrid(posts, context);
          },
        );
    }
  }

  Widget _buildPostsGrid(List<Post> posts, BuildContext context) {
    return SliverToBoxAdapter(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 896),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3, crossAxisSpacing: 2, mainAxisSpacing: 2),
              itemCount: posts.length,
              itemBuilder: (ctx, i) {
                final post = posts[i];
                final media =
                    post.mediaUrls.isNotEmpty ? post.mediaUrls.first : null;
                return _PostGridTile(
                  mediaUrl: media,
                  content: post.content,
                  isVideo: _gridMediaIsVideo(post.mediaType, media),
                  hasMultiple: post.mediaUrls.length > 1,
                  isPinned: post.isPinned,
                  likesCount: post.likesCount,
                  commentsCount: post.commentsCount,
                  c: c,
                  onTap: () => PostViewModal.show(
                    ctx,
                    post: post,
                    isOwnProfile: isOwn,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBookmarksGrid(List<BookmarkedPost> list, BuildContext context) {
    return SliverToBoxAdapter(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 896),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3, crossAxisSpacing: 2, mainAxisSpacing: 2),
              itemCount: list.length,
              itemBuilder: (ctx, i) {
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
                  isPinned: false,
                  likesCount: post.likesCount,
                  commentsCount: post.commentsCount,
                  c: c,
                  onTap: () => GoRouter.of(ctx).push('/post/${post.id}'),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptySliver(IconData icon, String title, String subtitle,
      {String? actionLabel, VoidCallback? onAction}) {
    return SliverToBoxAdapter(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 896),
          child: EmptyState(
            icon: icon,
            title: title,
            subtitle: subtitle,
            ctaLabel: actionLabel,
            onCta: onAction,
            padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// POST GRID TILE
// ---------------------------------------------------------------------------

class _PostGridTile extends StatefulWidget {
  final String? mediaUrl;
  final String? content;
  final bool isVideo;
  final bool hasMultiple;
  final bool isPinned;
  final int likesCount;
  final int commentsCount;
  final AlsamosColors c;
  final VoidCallback onTap;
  const _PostGridTile({
    required this.mediaUrl,
    required this.content,
    required this.isVideo,
    required this.hasMultiple,
    required this.isPinned,
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
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: c.muted,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (widget.mediaUrl != null && widget.isVideo)
                Container(
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
                      child: const Icon(LucideIcons.play,
                          color: Colors.white, size: 22),
                    ),
                  ),
                )
              else if (widget.mediaUrl != null)
                CachedNetworkImage(
                  imageUrl: widget.mediaUrl!,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(color: c.muted),
                  errorWidget: (_, __, ___) => Container(
                    color: c.muted,
                    child: const Center(
                      child: Icon(LucideIcons.imageOff,
                          color: Colors.white70, size: 20),
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Center(
                    child: Text(
                      stripPostMetadata(widget.content).isEmpty
                          ? 'No content'
                          : stripPostMetadata(widget.content),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: c.foreground),
                    ),
                  ),
                ),
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
              if (widget.isPinned)
                Positioned(
                  top: 6,
                  left: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(LucideIcons.pin,
                        size: 11, color: Colors.white),
                  ),
                ),
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
                      Flexible(
                        child: Text(
                          '${widget.likesCount}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Icon(LucideIcons.messageCircle,
                          color: Colors.white, size: 16),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          '${widget.commentsCount}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
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

// ---------------------------------------------------------------------------
// FOLLOWERS/FOLLOWING SHEET
// ---------------------------------------------------------------------------

class _FollowSheet extends StatelessWidget {
  final String profileId;
  final String type;
  const _FollowSheet({required this.profileId, required this.type});
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
                        ? "Hozircha obunachilar yo‘q"
                        : "Hech kimga obuna bo‘lmagansiz",
                    style: TextStyle(
                        color: c.foreground,
                        fontSize: 14,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    type == 'followers'
                        ? "Postlar va kontent yarating — odamlar sizni topishadi."
                        : "Qiziqarli mualliflarni topish uchun Discover sahifasiga o‘ting.",
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
