import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';

import '../../../../app/i18n/app_strings.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../shared/content/utils/content_metadata.dart';
import '../../../../shared/stories/story_avatar_ring.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/poll_display.dart';
import '../../data/notification_model.dart';
import '../providers/notifications_provider.dart';
import '../../../../shared/utils/video_controller_lifecycle.dart';
import '../../../../shared/widgets/app_toast.dart';

/// Faithful port of web pages/NotificationsPage.tsx.
class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key});
  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  String _filter = 'all';

  static const _filters = [
    'all',
    'likes',
    'comments',
    'follows',
    'mentions',
    'collaborations'
  ];
  static const _filterLabels = {
    'all': 'Hammasi',
    'likes': 'Layklar',
    'comments': 'Izohlar',
    'follows': 'Obunalar',
    'mentions': 'Eslatishlar',
    'collaborations': 'Hamkorlik',
  };

  bool _matches(String filter, String type) {
    switch (filter) {
      case 'likes':
        return type == 'like';
      case 'comments':
        return type == 'comment';
      case 'follows':
        return type == 'follow';
      case 'mentions':
        return type == 'mention';
      case 'collaborations':
        return type == 'collaboration_invite' ||
            type == 'collaboration_accepted';
      default:
        return true;
    }
  }

  // Gradient + icon per type (matches web NotificationIcon)
  ({List<Color> colors, IconData icon}) _badge(String type) {
    switch (type) {
      case 'like':
        return (
          colors: const [Color(0xFFEF4444), Color(0xFFEC4899)],
          icon: LucideIcons.heart
        );
      case 'comment':
        return (
          colors: const [Color(0xFF3B82F6), Color(0xFF06B6D4)],
          icon: LucideIcons.messageCircle
        );
      case 'follow':
        return (
          colors: const [Color(0xFF22C55E), Color(0xFF10B981)],
          icon: LucideIcons.userPlus
        );
      case 'mention':
        return (
          colors: const [Color(0xFFA855F7), Color(0xFF8B5CF6)],
          icon: LucideIcons.atSign
        );
      case 'collaboration_invite':
      case 'collaboration_accepted':
        return (
          colors: const [Color(0xFFF97316), Color(0xFFF59E0B)],
          icon: LucideIcons.users
        );
      default:
        return (
          colors: const [Color(0xFFF97316), Color(0xFFFB923C)],
          icon: LucideIcons.bell
        );
    }
  }

  String _section(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Bugun';
    if (diff == 1) return 'Kecha';
    if (diff < 7) return 'Shu hafta';
    if (diff < 30) return 'Shu oy';
    return 'Eski';
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final theme = Theme.of(context);
    final state = ref.watch(notificationsProvider);

    return Scaffold(
      backgroundColor: c.background,
      body: state.when(
        loading: () => Center(
            child: CircularProgressIndicator(color: theme.colorScheme.primary)),
        error: (e, _) => Center(
            child: Text('Xatolik yuz berdi: $e',
                style: TextStyle(
                    color: AlsamosColors.of(context).mutedForeground))),
        data: (all) {
          final unread = all.where((n) => !n.isRead).length;
          final items = all.where((n) => _matches(_filter, n.type)).toList();

          return Column(
            children: [
              // Header
              SafeArea(
                bottom: false,
                child: Container(
                  decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: c.border))),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                        child: Row(
                          children: [
                            Flexible(
                              child: Builder(builder: (ctx) {
                                ref.watch(localeProvider);
                                return Text(
                                    AppStrings.of(ref).t('pages.notifications'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontFamily: 'SpaceGrotesk',
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold));
                              }),
                            ),
                            if (unread > 0) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text('$unread',
                                    style: TextStyle(
                                        color: theme.colorScheme.onPrimary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600)),
                              ),
                            ],
                            const Spacer(),
                            if (unread > 0)
                              TextButton.icon(
                                onPressed: () => ref
                                    .read(notificationsProvider.notifier)
                                    .markAllAsRead(),
                                icon: Icon(LucideIcons.check,
                                    size: 16, color: theme.colorScheme.primary),
                                label: Text(
                                    AppStrings.of(ref)
                                        .t('pages.notificationsMarkAll'),
                                    style: TextStyle(
                                        color: theme.colorScheme.primary)),
                              ),
                            IconButton(
                                icon: Icon(LucideIcons.settings,
                                    size: 20, color: c.foreground),
                                onPressed: () => context.go('/settings')),
                          ],
                        ),
                      ),
                      // Filter pills
                      SizedBox(
                        height: 44,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                          itemCount: _filters.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (_, i) {
                            final f = _filters[i];
                            final active = _filter == f;
                            final count =
                                all.where((n) => _matches(f, n.type)).length;
                            return GestureDetector(
                              onTap: () => setState(() => _filter = f),
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: active
                                      ? theme.colorScheme.primary
                                      : c.muted,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Row(
                                  children: [
                                    Text(_filterLabels[f]!,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: active
                                              ? theme.colorScheme.onPrimary
                                              : c.mutedForeground,
                                        )),
                                    if (count > 0) ...[
                                      const SizedBox(width: 6),
                                      Text('$count',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: (active
                                                    ? theme
                                                        .colorScheme.onPrimary
                                                    : c.mutedForeground)
                                                .withValues(
                                                    alpha: active ? 0.8 : 0.6),
                                          )),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // List
              Expanded(
                child: items.isEmpty
                    ? _empty(c)
                    : RefreshIndicator(
                        color: theme.colorScheme.primary,
                        backgroundColor: c.card,
                        onRefresh: () =>
                            ref.read(notificationsProvider.notifier).load(),
                        child: _buildGroupedList(items, c, theme),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildGroupedList(
      List<AppNotification> items, AlsamosColors c, ThemeData theme) {
    // Group preserving order: Today, Yesterday, This Week, This Month, Older
    const order = ['Bugun', 'Kecha', 'Shu hafta', 'Shu oy', 'Eski'];
    final map = <String, List<AppNotification>>{};
    for (final n in items) {
      map.putIfAbsent(_section(n.createdAt), () => []).add(n);
    }
    final sections = <({String title, List<AppNotification> items})>[];
    for (final sec in order) {
      final group = map[sec];
      if (group != null && group.isNotEmpty) {
        sections.add((title: sec, items: group));
      }
    }

    int itemCount = 0;
    for (final s in sections) {
      itemCount += 1 + s.items.length; // header + items
    }

    return ListView.builder(
      itemCount: itemCount,
      itemBuilder: (context, index) {
        int offset = 0;
        for (final s in sections) {
          if (index == offset) {
            // Section header
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  Icon(LucideIcons.sparkles,
                      size: 12, color: c.mutedForeground),
                  const SizedBox(width: 6),
                  Text(s.title.toUpperCase(),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                          color: c.mutedForeground)),
                ],
              ),
            );
          }
          if (index < offset + 1 + s.items.length) {
            // Item within this section
            final itemIndex = index - offset - 1;
            return _item(s.items[itemIndex], c, theme);
          }
          offset += 1 + s.items.length;
        }
        return const SizedBox.shrink();
      },
    );
  }

  Future<void> _respondToCollaboration(
    AppNotification notification, {
    required bool accept,
  }) async {
    final ok = await ref
        .read(notificationsProvider.notifier)
        .respondToCollaborationInvite(notification, accept: accept);
    if (!mounted) return;
    if (ok) {
      AppToast.success(
        context,
        accept ? 'Hamkorlik qabul qilindi' : 'Hamkorlik rad etildi',
      );
    } else {
      AppToast.error(
        context,
        'Hamkorlik so\'rovini yangilab bo\'lmadi',
      );
    }
  }

  Widget _item(AppNotification n, AlsamosColors c, ThemeData theme) {
    final badge = _badge(n.type);
    final time = DateTime.now().difference(n.createdAt).inDays == 0
        ? DateFormat('HH:mm').format(n.createdAt)
        : timeago.format(n.createdAt);

    final hasPost = n.postId != null && n.postId!.isNotEmpty;
    final message = _bodyText(n);

    return Dismissible(
      key: ValueKey(n.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (direction) async {
        // Show confirmation dialog
        return await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: c.card,
                title: Text('Bildirishnomani o\'chirish?',
                    style: TextStyle(color: c.foreground)),
                content: Text('Bu amalni bekor qilib bo\'lmaydi.',
                    style: TextStyle(color: c.mutedForeground)),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text('Bekor qilish',
                        style: TextStyle(color: c.mutedForeground)),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: Text('O\'chirish',
                        style: TextStyle(color: theme.colorScheme.error)),
                  ),
                ],
              ),
            ) ??
            false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(LucideIcons.trash2, color: Colors.white, size: 22),
            const SizedBox(height: 4),
            Text(
              'O\'chirish',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      onDismissed: (_) =>
          ref.read(notificationsProvider.notifier).deleteNotification(n.id),
      child: Material(
        color: n.isRead
            ? Colors.transparent
            : theme.colorScheme.primary.withValues(alpha: 0.05),
        child: InkWell(
          onTap: () => _handleNotificationTap(n),
          onLongPress: () => _showNotificationMenu(context, n, c, theme),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar + gradient type badge
                SizedBox(
                  width: 56,
                  height: 56,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Center(
                        child: StoryAvatarRing(
                          userId: n.actor?.id,
                          avatarUrl: n.actor?.avatarUrl,
                          fallback: n.actor?.initial ?? 'A',
                          size: 48,
                        ),
                      ),
                      Positioned(
                        bottom: -2,
                        right: -2,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                                colors: badge.colors,
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight),
                            shape: BoxShape.circle,
                            border: Border.all(color: c.background, width: 2.5),
                            boxShadow: [
                              BoxShadow(
                                color:
                                    badge.colors.first.withValues(alpha: 0.4),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child:
                              Icon(badge.icon, size: 12, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Text
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RichText(
                        text: TextSpan(
                          style: TextStyle(
                              fontSize: 14, height: 1.4, color: c.foreground),
                          children: [
                            TextSpan(
                                text: n.actor?.title ?? 'Kimdir',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            TextSpan(
                                text: ' $message',
                                style: TextStyle(color: c.foreground)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(LucideIcons.clock,
                              size: 12, color: c.mutedForeground),
                          const SizedBox(width: 4),
                          Text(time,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: c.mutedForeground)),
                          if (!n.isRead) ...[
                            const SizedBox(width: 8),
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                  color: theme.colorScheme.primary,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: theme.colorScheme.primary
                                          .withValues(alpha: 0.4),
                                      blurRadius: 4,
                                    ),
                                  ]),
                            ),
                          ],
                        ],
                      ),
                      if (n.type == 'collaboration_invite' &&
                          (n.data['collaboration_id']?.toString().isNotEmpty ??
                              false)) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () =>
                                  _respondToCollaboration(n, accept: false),
                              icon: const Icon(LucideIcons.x, size: 14),
                              label: const Text('Rad etish'),
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                foregroundColor: c.mutedForeground,
                              ),
                            ),
                            FilledButton.icon(
                              onPressed: () =>
                                  _respondToCollaboration(n, accept: true),
                              icon: const Icon(LucideIcons.check, size: 14),
                              label: const Text('Qabul qilish'),
                              style: FilledButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                // Post thumbnail or follow button
                if (hasPost) ...[
                  const SizedBox(width: 12),
                  _postPreview(n, c),
                ] else if (n.type == 'follow') ...[
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () {
                      if (n.actor?.id != null) {
                        context.go('/user/${n.actor!.id}');
                      }
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      minimumSize: const Size(0, 36),
                    ),
                    child: const Text('Profil',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showNotificationMenu(BuildContext context, AppNotification n,
      AlsamosColors c, ThemeData theme) {
    showModalBottomSheet(
      context: context,
      backgroundColor: c.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: c.muted,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: Icon(
                n.isRead ? LucideIcons.circleDot : LucideIcons.check,
                color: theme.colorScheme.primary,
              ),
              title: Text(
                n.isRead
                    ? 'O\'qilmagan deb belgilash'
                    : 'O\'qilgan deb belgilash',
                style: TextStyle(color: c.foreground),
              ),
              onTap: () {
                Navigator.pop(context);
                ref.read(notificationsProvider.notifier).markAsRead(n.id);
              },
            ),
            if (n.actor?.id != null)
              ListTile(
                leading: Icon(LucideIcons.user, color: c.foreground),
                title: Text('Profilni ko\'rish',
                    style: TextStyle(color: c.foreground)),
                onTap: () {
                  Navigator.pop(context);
                  this.context.go('/user/${n.actor!.id}');
                },
              ),
            ListTile(
              leading: Icon(LucideIcons.trash2, color: theme.colorScheme.error),
              title: Text('O\'chirish',
                  style: TextStyle(color: theme.colorScheme.error)),
              onTap: () {
                Navigator.pop(context);
                ref
                    .read(notificationsProvider.notifier)
                    .deleteNotification(n.id);
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _handleNotificationTap(AppNotification n) {
    if (!n.isRead) {
      ref.read(notificationsProvider.notifier).markAsRead(n.id);
    }

    if (n.type == 'follow' && n.actor?.id != null) {
      context.go('/user/${n.actor!.id}');
    } else if (n.postId != null && n.postId!.isNotEmpty) {
      if (!n.postExists) {
        _showUnavailablePostToast();
        return;
      }
      context.go('/post/${n.postId}');
    } else if (n.actor?.id != null) {
      context.go('/user/${n.actor!.id}');
    } else {
      _showUnavailablePostToast();
    }
  }

  void _showUnavailablePostToast() {
    AppToast.error(context, 'Bu post o\'chirilgan yoki mavjud emas');
  }

  String _bodyText(AppNotification n) {
    final body = n.body?.trim();
    if (body == null || body.isEmpty) return _defaultText(n.type);
    final actor = n.actor?.title.trim();
    if (actor != null &&
        actor.isNotEmpty &&
        body.toLowerCase().startsWith(actor.toLowerCase())) {
      var stripped = body;
      while (stripped.toLowerCase().startsWith(actor.toLowerCase())) {
        stripped = stripped.substring(actor.length).trimLeft();
      }
      return stripped.isEmpty ? _defaultText(n.type) : stripped;
    }
    return body;
  }

  String _pathOf(String url) => (Uri.tryParse(url)?.path ?? url).toLowerCase();

  bool _hasExt(String url, String pattern) =>
      RegExp(pattern, caseSensitive: false).hasMatch(_pathOf(url));

  bool _urlLooksImage(String url) => _hasExt(
        url,
        r'\.(jpg|jpeg|png|gif|webp|bmp|heic|heif)$',
      );

  bool _urlLooksVideo(String url) => _hasExt(
        url,
        r'\.(mp4|webm|mov|m4v|avi|mkv|flv|wmv)$',
      );

  bool _urlLooksAudio(String url) => _hasExt(
        url,
        r'\.(mp3|wav|ogg|flac|aac|m4a)$',
      );

  bool _urlLooksDocument(String url) => _hasExt(
        url,
        r'\.(pdf|doc|docx|xls|xlsx|ppt|pptx|zip|rar|7z|apk|exe|msi|txt|md|json|csv)$',
      );

  bool _isVideoNotification(AppNotification n) {
    final mediaType = n.mediaType?.toLowerCase();
    if (mediaType == 'video' || mediaType == 'reel' || mediaType == 'reels') {
      return true;
    }
    return n.postMediaUrls.any(_urlLooksVideo) ||
        (n.postThumb != null && _urlLooksVideo(n.postThumb!));
  }

  bool _isPollNotification(AppNotification n) {
    final mediaType = n.mediaType?.toLowerCase();
    final postType = n.postType?.toLowerCase();
    if (mediaType == 'poll' || postType == 'poll') return true;
    final content = n.postContent;
    if (content == null || content.isEmpty) return false;
    final (poll, _) = PollData.parseFromContent(content);
    return poll != null;
  }

  String _cleanPostText(String? content) {
    return stripPostMetadata(content)
        .replaceAll(RegExp(r'\[ASPECT:[^\]]+\]'), '')
        .trim();
  }

  String _fileLabel(String url) {
    final path = Uri.tryParse(url)?.path ?? url;
    final parts = path.split('/').where((s) => s.isNotEmpty).toList();
    final name = parts.isEmpty ? '' : parts.last;
    final dot = name.lastIndexOf('.');
    if (dot == -1 || dot == name.length - 1) return 'FAYL';
    return name.substring(dot + 1).toUpperCase();
  }

  Color _fileColor(String? mediaType, String? url) {
    final type = mediaType?.toLowerCase();
    if (type == 'audio' || (url != null && _urlLooksAudio(url))) {
      return const Color(0xFFEC4899);
    }
    if (url != null && _urlLooksDocument(url)) return const Color(0xFF3B82F6);
    return const Color(0xFF64748B);
  }

  String? _firstMatching(List<String> values, bool Function(String) test) {
    for (final value in values) {
      if (test(value)) return value;
    }
    return null;
  }

  Widget _postPreview(AppNotification n, AlsamosColors c) {
    final urls = n.postMediaUrls;
    final imageUrl = _firstMatching(urls, _urlLooksImage);
    final videoUrl = _firstMatching(urls, _urlLooksVideo);
    final audioUrl = _firstMatching(urls, _urlLooksAudio);
    final documentUrl = _firstMatching(urls, _urlLooksDocument);
    final firstUrl = n.postThumb ?? (urls.isEmpty ? null : urls.first);
    final isVideo = _isVideoNotification(n);
    final isPoll = _isPollNotification(n);
    final text = _cleanPostText(n.postContent);

    Widget previewShell({
      required Widget child,
      double width = 64,
      Color? color,
      Color? borderColor,
    }) =>
        Container(
          width: width,
          height: 56,
          decoration: BoxDecoration(
            color: color ?? c.muted,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: borderColor ?? c.border.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        );

    if (!n.postExists) {
      return GestureDetector(
        onTap: _showUnavailablePostToast,
        child: previewShell(
          color: c.muted.withValues(alpha: 0.55),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.trash2, size: 18, color: c.mutedForeground),
              const SizedBox(height: 3),
              Text(
                'O\'chirilgan',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 9, color: c.mutedForeground),
              ),
            ],
          ),
        ),
      );
    }

    if (isPoll) {
      final (poll, _) = PollData.parseFromContent(n.postContent ?? '');
      return GestureDetector(
        onTap: () => _handleNotificationTap(n),
        child: previewShell(
          width: 96,
          color: const Color(0xFF111827),
          borderColor: const Color(0xFF7C3AED).withValues(alpha: 0.45),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      LucideIcons.barChart3,
                      size: 13,
                      color: Color(0xFFA78BFA),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'So\'rov',
                      style: TextStyle(
                        color: c.foreground,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  poll?.question.isNotEmpty == true
                      ? poll!.question
                      : (text.isNotEmpty ? text : 'Poll post'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.foreground.withValues(alpha: 0.92),
                    fontSize: 10,
                    height: 1.1,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (isVideo || videoUrl != null) {
      return _NotificationVideoPreview(
        url: videoUrl ?? firstUrl ?? '',
        onTap: () => _handleNotificationTap(n),
      );
    }

    if (imageUrl != null) {
      return GestureDetector(
        onTap: () => _handleNotificationTap(n),
        child: previewShell(
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            width: 64,
            height: 56,
            fit: BoxFit.cover,
            placeholder: (context, url) => Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            errorWidget: (context, url, error) => Center(
              child: Icon(LucideIcons.imageOff,
                  size: 20, color: c.mutedForeground),
            ),
          ),
        ),
      );
    }

    if (audioUrl != null || documentUrl != null || firstUrl != null) {
      final url = audioUrl ?? documentUrl ?? firstUrl!;
      final color = _fileColor(n.mediaType, url);
      return GestureDetector(
        onTap: () => _handleNotificationTap(n),
        child: previewShell(
          color: color.withValues(alpha: 0.12),
          borderColor: color.withValues(alpha: 0.35),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                audioUrl != null ? LucideIcons.music : LucideIcons.fileText,
                size: 18,
                color: color,
              ),
              const SizedBox(height: 3),
              Text(
                audioUrl != null ? 'AUDIO' : _fileLabel(url),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: color,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () => _handleNotificationTap(n),
      child: previewShell(
        width: 96,
        color: c.muted.withValues(alpha: 0.45),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            text.isNotEmpty ? text : 'Matnli post',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: c.foreground.withValues(alpha: 0.88),
              fontSize: 10,
              height: 1.15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  String _defaultText(String type) {
    switch (type) {
      case 'like':
        return 'postingizni yoqtirdi';
      case 'comment':
        return 'postingizga izoh qoldirdi';
      case 'follow':
        return 'sizga obuna bo\'ldi';
      case 'mention':
        return 'sizni eslatib o\'tdi';
      case 'collaboration_invite':
        return 'siz bilan hamkorlik qilmoqchi';
      case 'collaboration_accepted':
        return 'hamkorlik so\'rovingizni qabul qildi';
      default:
        return '';
    }
  }

  Widget _empty(AlsamosColors c) {
    // v42: reusable EmptyState widget bilan almashtirildi
    return const Center(
      child: EmptyState(
        icon: LucideIcons.bellOff,
        title: 'Bildirishnomalar hali yo\'q',
        subtitle:
            'Kimdir kontentingizga munosabat bildirsa, shu yerda ko\'rinadi.',
      ),
    );
  }
}

class _NotificationVideoPreview extends StatefulWidget {
  const _NotificationVideoPreview({
    required this.url,
    required this.onTap,
  });

  final String url;
  final VoidCallback onTap;

  @override
  State<_NotificationVideoPreview> createState() =>
      _NotificationVideoPreviewState();
}

class _NotificationVideoPreviewState extends State<_NotificationVideoPreview> {
  VideoPlayerController? _controller;
  Object? _error;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void didUpdateWidget(covariant _NotificationVideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _disposeController();
      _initialize();
    }
  }

  void _initialize() {
    final uri = Uri.tryParse(widget.url);
    if (widget.url.isEmpty || uri == null) {
      _error = 'Invalid video url';
      return;
    }

    final controller = VideoPlayerController.networkUrl(uri);
    _controller = controller;
    controller.setVolume(0);
    controller.initialize().then((_) {
      if (!mounted || _controller != controller) return;
      setState(() => _ready = true);
    }).catchError((Object error) {
      if (!mounted || _controller != controller) return;
      setState(() => _error = error);
    });
  }

  void _disposeController() {
    final controller = _controller;
    _controller = null;
    _ready = false;
    _error = null;
    disposeVideoControllerSafely(controller);
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        width: 64,
        height: 56,
        decoration: BoxDecoration(
          color: c.muted,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.border.withValues(alpha: 0.5)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(child: _buildFrame()),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.18),
                ),
              ),
            ),
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                LucideIcons.play,
                color: Color(0xFFF97316),
                size: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFrame() {
    final controller = _controller;
    if (_error != null || widget.url.isEmpty) {
      return const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF111827), Color(0xFF1E293B)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Icon(LucideIcons.video, color: Colors.white70, size: 22),
        ),
      );
    }

    if (!_ready || controller == null || !controller.value.isInitialized) {
      return const DecoratedBox(
        decoration: BoxDecoration(color: Color(0xFF0F172A)),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Color(0xFFF97316),
            ),
          ),
        ),
      );
    }

    final size = controller.value.size;
    if (size.width <= 0 || size.height <= 0) {
      return const DecoratedBox(
        decoration: BoxDecoration(color: Color(0xFF0F172A)),
        child: Center(
          child: Icon(LucideIcons.video, color: Colors.white70, size: 22),
        ),
      );
    }

    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: VideoPlayer(controller),
      ),
    );
  }
}
