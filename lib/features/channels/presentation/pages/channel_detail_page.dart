import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/channel_model.dart';
import '../providers/channels_provider.dart';
import '../../../../shared/widgets/app_toast.dart';

/// v21: Channel detail page — cover + avatar + meta + posts list.
/// Replaces the previous "tez orada" snackbar in channels_page.dart.
class ChannelDetailPage extends ConsumerStatefulWidget {
  final Channel channel;
  const ChannelDetailPage({super.key, required this.channel});

  @override
  ConsumerState<ChannelDetailPage> createState() => _ChannelDetailPageState();
}

class _ChannelDetailPageState extends ConsumerState<ChannelDetailPage> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _posts = [];
  bool _loading = true;

  Future<void> _copyLink(String link) async {
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    AppToast.success(context, 'Havola nusxalandi');
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _client
          .from('channel_posts')
          .select(
              'id, content, media_urls, likes_count, comments_count, views_count, created_at')
          .eq('channel_id', widget.channel.id)
          .order('created_at', ascending: false)
          .limit(50);
      if (!mounted) return;
      setState(() {
        _posts = List<Map<String, dynamic>>.from(r as List);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final ch = widget.channel;
    final isMine = ch.ownerId == ref.watch(authProvider).user?.id;

    return Scaffold(
      backgroundColor: c.background,
      body: CustomScrollView(slivers: [
        SliverAppBar(
          expandedHeight: 200,
          pinned: true,
          backgroundColor: c.background,
          iconTheme: IconThemeData(color: c.foreground),
          title: Text(ch.name,
              style: TextStyle(
                  color: c.foreground,
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
          flexibleSpace: FlexibleSpaceBar(
            background: ch.coverUrl != null && ch.coverUrl!.isNotEmpty
                ? CachedNetworkImage(imageUrl: ch.coverUrl!, fit: BoxFit.cover)
                : Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          primary.withValues(alpha: 0.5),
                          primary.withValues(alpha: 0.2)
                        ],
                      ),
                    ),
                  ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: primary.withValues(alpha: 0.15),
                  backgroundImage:
                      (ch.avatarUrl != null && ch.avatarUrl!.isNotEmpty)
                          ? CachedNetworkImageProvider(ch.avatarUrl!)
                          : null,
                  child: (ch.avatarUrl == null || ch.avatarUrl!.isEmpty)
                      ? Text(ch.name[0].toUpperCase(),
                          style: TextStyle(
                              color: primary,
                              fontWeight: FontWeight.w700,
                              fontSize: 22))
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(ch.name,
                          style: TextStyle(
                              color: c.foreground,
                              fontSize: 18,
                              fontWeight: FontWeight.w700)),
                      if (ch.username != null)
                        Text('@${ch.username}',
                            style: TextStyle(
                                color: c.mutedForeground, fontSize: 13)),
                      const SizedBox(height: 4),
                      Row(children: [
                        Icon(LucideIcons.users,
                            size: 14, color: c.mutedForeground),
                        const SizedBox(width: 4),
                        Text('${_fmt(ch.subscriberCount)} obunachi',
                            style: TextStyle(
                                color: c.mutedForeground, fontSize: 12)),
                        const SizedBox(width: 12),
                        Icon(LucideIcons.fileText,
                            size: 14, color: c.mutedForeground),
                        const SizedBox(width: 4),
                        Text('${ch.postsCount} post',
                            style: TextStyle(
                                color: c.mutedForeground, fontSize: 12)),
                      ]),
                    ])),
                if (!isMine)
                  FilledButton.icon(
                    onPressed: () async {
                      if (ch.isMember) {
                        await ref.read(channelsProvider.notifier).leave(ch.id);
                      } else {
                        await ref.read(channelsProvider.notifier).join(ch.id);
                      }
                    },
                    icon: Icon(
                        ch.isMember ? LucideIcons.check : LucideIcons.userPlus,
                        size: 16),
                    label: Text(ch.isMember ? 'Obuna' : 'Obuna bo\'lish'),
                    style: FilledButton.styleFrom(
                      backgroundColor: ch.isMember ? c.muted : primary,
                      foregroundColor:
                          ch.isMember ? c.foreground : Colors.white,
                    ),
                  ),
              ]),
              if (ch.description != null && ch.description!.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(ch.description!,
                    style: TextStyle(
                        color: c.foreground.withValues(alpha: 0.85),
                        fontSize: 14,
                        height: 1.4)),
              ],
              const SizedBox(height: 12),
              _InviteLinkCard(
                channel: ch,
                c: c,
                onCopy: () => _copyLink(ch.publicLink),
              ),
              if (ch.canManage) ...[
                const SizedBox(height: 12),
                _AdminPermissionsCard(
                  channel: ch,
                  c: c,
                  onChanged: (next) => ref
                      .read(channelsProvider.notifier)
                      .updatePermissions(ch.id, next),
                ),
              ],
              const SizedBox(height: 14),
              Divider(color: c.border, height: 1),
            ]),
          ),
        ),
        if (_loading)
          const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()))
        else if (_posts.isEmpty)
          SliverFillRemaining(
              child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(LucideIcons.fileText,
                size: 56, color: c.mutedForeground.withValues(alpha: 0.3)),
            const SizedBox(height: 12),
            Text('Hozircha postlar yo\'q',
                style: TextStyle(color: c.mutedForeground, fontSize: 14)),
          ])))
        else
          SliverList(
              delegate: SliverChildBuilderDelegate(
            (ctx, i) {
              final p = _posts[i];
              final media = (p['media_urls'] as List?)?.cast<String>() ?? [];
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Container(
                  decoration: BoxDecoration(
                    color: c.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: c.border),
                  ),
                  padding: const EdgeInsets.all(14),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if ((p['content'] as String?)?.isNotEmpty ?? false)
                          Text(p['content'] as String,
                              style: TextStyle(
                                  color: c.foreground,
                                  fontSize: 14,
                                  height: 1.4)),
                        if (media.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: AspectRatio(
                              aspectRatio: 16 / 9,
                              child: CachedNetworkImage(
                                  imageUrl: media.first, fit: BoxFit.cover),
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Row(children: [
                          Icon(LucideIcons.heart,
                              size: 14, color: c.mutedForeground),
                          const SizedBox(width: 4),
                          Text(_fmt((p['likes_count'] as num?)?.toInt() ?? 0),
                              style: TextStyle(
                                  color: c.mutedForeground, fontSize: 12)),
                          const SizedBox(width: 14),
                          Icon(LucideIcons.messageCircle,
                              size: 14, color: c.mutedForeground),
                          const SizedBox(width: 4),
                          Text(
                              _fmt((p['comments_count'] as num?)?.toInt() ?? 0),
                              style: TextStyle(
                                  color: c.mutedForeground, fontSize: 12)),
                          const SizedBox(width: 14),
                          Icon(LucideIcons.eye,
                              size: 14, color: c.mutedForeground),
                          const SizedBox(width: 4),
                          Text(_fmt((p['views_count'] as num?)?.toInt() ?? 0),
                              style: TextStyle(
                                  color: c.mutedForeground, fontSize: 12)),
                        ]),
                      ]),
                ),
              );
            },
            childCount: _posts.length,
          )),
        const SliverToBoxAdapter(child: SizedBox(height: 80)),
      ]),
    );
  }
}

class _InviteLinkCard extends StatelessWidget {
  final Channel channel;
  final AlsamosColors c;
  final VoidCallback onCopy;
  const _InviteLinkCard({
    required this.channel,
    required this.c,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.muted.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.link, size: 18, color: primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Invite link',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  channel.publicLink,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: c.mutedForeground),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Nusxalash',
            onPressed: onCopy,
            icon: const Icon(LucideIcons.copy, size: 18),
          ),
        ],
      ),
    );
  }
}

class _AdminPermissionsCard extends StatelessWidget {
  final Channel channel;
  final AlsamosColors c;
  final ValueChanged<Map<String, bool>> onChanged;
  const _AdminPermissionsCard({
    required this.channel,
    required this.c,
    required this.onChanged,
  });

  static const _items = <(String, String, IconData)>[
    ('post', 'Post joylash', LucideIcons.send),
    ('edit_info', 'Maʼlumotni tahrirlash', LucideIcons.squarePen),
    ('invite', 'Aʼzo taklif qilish', LucideIcons.userPlus),
    ('pin', 'Post qadash', LucideIcons.pin),
    ('manage_members', 'Aʼzolarni boshqarish', LucideIcons.shieldCheck),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Row(
              children: [
                Icon(LucideIcons.shield, size: 18, color: c.mutedForeground),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Admin permissions',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
          for (final item in _items)
            SwitchListTile.adaptive(
              dense: true,
              secondary: Icon(item.$3, size: 18, color: c.mutedForeground),
              title: Text(item.$2, style: const TextStyle(fontSize: 13)),
              value: channel.adminPermissions[item.$1] ?? true,
              onChanged: (value) => onChanged({
                ...channel.adminPermissions,
                item.$1: value,
              }),
            ),
        ],
      ),
    );
  }
}
