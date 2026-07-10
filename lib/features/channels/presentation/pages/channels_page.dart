import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../data/channel_model.dart';
import 'channel_detail_page.dart';
import '../providers/channels_provider.dart';

enum _Tab { my, discover, popular }

class ChannelsPage extends ConsumerStatefulWidget {
  const ChannelsPage({super.key});
  @override
  ConsumerState<ChannelsPage> createState() => _ChannelsPageState();
}

class _ChannelsPageState extends ConsumerState<ChannelsPage> {
  _Tab _tab = _Tab.my;
  final _queryCtrl = TextEditingController();

  @override
  void dispose() { _queryCtrl.dispose(); super.dispose(); }

  List<Channel> _filter(List<Channel> all) {
    final q = _queryCtrl.text.toLowerCase();
    List<Channel> base;
    switch (_tab) {
      case _Tab.my: base = all.where((c) => c.isMember).toList(); break;
      case _Tab.discover: base = all.where((c) => !c.isMember && c.channelType == 'public').toList(); break;
      case _Tab.popular: base = List.of(all)..sort((a, b) => b.subscriberCount.compareTo(a.subscriberCount)); base = base.take(20).toList(); break;
    }
    if (q.isEmpty) return base;
    return base.where((c) => c.name.toLowerCase().contains(q) || (c.username?.toLowerCase().contains(q) ?? false)).toList();
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }

  Future<void> _createDialog() async {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    var type = 'public';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Yangi kanal', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Kanal nomi', hintText: '@username')),
            const SizedBox(height: 10),
            TextField(controller: descCtrl, maxLines: 2,
                decoration: const InputDecoration(labelText: 'Tavsif (ixtiyoriy)')),
            const SizedBox(height: 10),
            Row(children: [
              const Text('Turi:', style: TextStyle(fontWeight: FontWeight.w500)),
              const Spacer(),
              DropdownButton<String>(
                value: type, underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: 'public', child: Row(children: [Icon(LucideIcons.globe, size: 14), SizedBox(width: 4), Text('Ochiq')])),
                  DropdownMenuItem(value: 'private', child: Row(children: [Icon(LucideIcons.lock, size: 14), SizedBox(width: 4), Text('Yopiq')])),
                ],
                onChanged: (v) => setS(() => type = v ?? 'public'),
              ),
            ]),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Bekor')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yaratish')),
          ],
        ),
      ),
    );
    if (ok == true && nameCtrl.text.trim().isNotEmpty) {
      await ref.read(channelsProvider.notifier).create(nameCtrl.text.trim(), type, description: descCtrl.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final channelsAsync = ref.watch(channelsProvider);
    final channels = channelsAsync.channels;
    final filtered = _filter(channels);
    final isLoading = channelsAsync.isLoading;

    return Scaffold(
      backgroundColor: c.background,
      body: Column(
        children: [
          // Header — matches web exactly
          SafeArea(
            bottom: false,
            child: Container(
              decoration: BoxDecoration(
                color: c.background.withValues(alpha: 0.95),
                border: Border(bottom: BorderSide(color: c.border)),
              ),
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(LucideIcons.megaphone, size: 24, color: AppColors.alsamosOrange),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text('Kanallar',
                            style: TextStyle(fontFamily: 'SpaceGrotesk',
                                fontSize: 20, fontWeight: FontWeight.bold)),
                      ),
                      FilledButton.icon(
                        onPressed: _createDialog,
                        icon: const Icon(LucideIcons.plus, size: 16),
                        label: const Text('Yaratish', style: TextStyle(fontSize: 13)),
                        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Search
                  TextField(
                    controller: _queryCtrl,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Kanallarni qidirish...',
                      prefixIcon: Icon(LucideIcons.search, size: 18, color: c.mutedForeground),
                      filled: true,
                      fillColor: c.muted.withValues(alpha: 0.6),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Tabs
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                        color: c.muted.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      children: [
                        _TabBtn(label: 'Mening', icon: LucideIcons.bookmark,
                            active: _tab == _Tab.my,
                            onTap: () => setState(() => _tab = _Tab.my), c: c),
                        _TabBtn(label: 'Topish', icon: LucideIcons.search,
                            active: _tab == _Tab.discover,
                            onTap: () => setState(() => _tab = _Tab.discover), c: c),
                        _TabBtn(label: 'Mashhur', icon: LucideIcons.trendingUp,
                            active: _tab == _Tab.popular,
                            onTap: () => setState(() => _tab = _Tab.popular), c: c),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // List
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? _EmptyChannels(tab: _tab, onCreateTap: _createDialog, c: c)
                    : RefreshIndicator(
                        onRefresh: () => ref.read(channelsProvider.notifier).load(),
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          itemCount: filtered.length,
                          itemBuilder: (_, i) => _ChannelCard(
                            channel: filtered[i],
                            fmt: _fmt,
                            onTap: () => _openChannel(filtered[i]),
                            onJoin: () => ref.read(channelsProvider.notifier).join(filtered[i].id),
                            onLeave: () => ref.read(channelsProvider.notifier).leave(filtered[i].id),
                            c: c,
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  void _openChannel(Channel ch) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChannelDetailPage(channel: ch),
    ));
  }
}

class _TabBtn extends StatelessWidget {
  final String label; final IconData icon; final bool active;
  final VoidCallback onTap; final AlsamosColors c;
  const _TabBtn({required this.label, required this.icon, required this.active,
      required this.onTap, required this.c});
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? c.background : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: active ? AppColors.alsamosOrange : c.mutedForeground),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(
                  fontSize: 12, fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                  color: active ? AppColors.alsamosOrange : c.mutedForeground)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChannelCard extends StatelessWidget {
  final Channel channel; final String Function(int) fmt;
  final VoidCallback onTap; final VoidCallback onJoin; final VoidCallback onLeave;
  final AlsamosColors c;
  const _ChannelCard({required this.channel, required this.fmt, required this.onTap,
      required this.onJoin, required this.onLeave, required this.c});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                  color: AppColors.alsamosOrange.withValues(alpha: 0.12),
                  shape: BoxShape.circle),
              child: channel.avatarUrl != null
                  ? ClipOval(child: Image.network(channel.avatarUrl!, width: 52, height: 52, fit: BoxFit.cover))
                  : Icon(LucideIcons.megaphone, size: 22, color: AppColors.alsamosOrange),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(channel.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        channel.channelType == 'private' ? LucideIcons.lock : LucideIcons.globe,
                        size: 13,
                        color: channel.channelType == 'private' ? c.mutedForeground : AppColors.alsamosOrange,
                      ),
                    ],
                  ),
                  if (channel.username != null)
                    Text('@${channel.username}',
                        style: TextStyle(fontSize: 12, color: c.mutedForeground)),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(LucideIcons.users, size: 12, color: c.mutedForeground),
                      const SizedBox(width: 4),
                      Text(fmt(channel.subscriberCount),
                          style: TextStyle(fontSize: 12, color: c.mutedForeground)),
                      if (channel.isPaid) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                              color: c.muted, borderRadius: BorderRadius.circular(6)),
                          child: Text('Pullik',
                              style: TextStyle(fontSize: 10, color: c.mutedForeground)),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // Action
            if (!channel.isMember)
              FilledButton(
                onPressed: onJoin,
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7)),
                child: const Text('Obuna', style: TextStyle(fontSize: 12)),
              )
            else if (channel.memberRole == 'admin')
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    border: Border.all(color: c.border),
                    borderRadius: BorderRadius.circular(8)),
                child: const Text('Admin', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
              )
            else
              OutlinedButton(
                onPressed: onLeave,
                style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7)),
                child: const Text('Chiqish', style: TextStyle(fontSize: 12)),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyChannels extends StatelessWidget {
  final _Tab tab; final VoidCallback onCreateTap; final AlsamosColors c;
  const _EmptyChannels({required this.tab, required this.onCreateTap, required this.c});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.megaphone, size: 64, color: c.mutedForeground.withValues(alpha: 0.3)),
          const SizedBox(height: 12),
          Text(
            tab == _Tab.my ? "Hali kanallaringiz yo'q" : 'Kanal topilmadi',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 6),
          Text(
            tab == _Tab.my
                ? "Yangi kanal yarating yoki boshqa kanallarga obuna bo'ling"
                : "Boshqa kalit so'z bilan qidirib ko'ring",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: c.mutedForeground),
          ),
          if (tab == _Tab.my) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onCreateTap,
              icon: const Icon(LucideIcons.plus, size: 16),
              label: const Text('Kanal yaratish'),
            ),
          ],
        ],
      ),
    );
  }
}
