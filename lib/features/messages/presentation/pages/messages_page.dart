import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/widgets/verified_badge.dart';
import '../../data/models/conversation_model.dart';
import '../../data/repositories/messages_repository.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/conversations_provider.dart';
import '../providers/online_status_provider.dart';
import '../widgets/create_group_channel_sheet.dart';
import 'chat_page.dart';

class MessagesPage extends ConsumerStatefulWidget {
  const MessagesPage({super.key});
  @override
  ConsumerState<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends ConsumerState<MessagesPage> with TickerProviderStateMixin {
  String _tab = 'private';
  String _query = '';
  Conversation? _selected;
  double _leftPanelWidth = 320.0;
  static const _desktopBreakpoint = 900.0;

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final w = MediaQuery.of(context).size.width;
    final isDesktop = w >= _desktopBreakpoint;
    if (isDesktop) {
      return Scaffold(
        backgroundColor: c.background,
        body: SafeArea(child: Row(children: [
          SizedBox(
            width: _leftPanelWidth,
            child: _LeftPanel(
              tab: _tab, query: _query, selected: _selected,
              isCompact: _leftPanelWidth < 140,
              onTabChange: (t) => setState(() => _tab = t),
              onQueryChange: (q) => setState(() => _query = q),
              onSelect: (conv) => setState(() => _selected = conv),
              onOpenSelfChat: _openSelfChat,
            ),
          ),
          MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: GestureDetector(
              onHorizontalDragUpdate: (d) => setState(() {
                double nw = _leftPanelWidth + d.delta.dx;
                if (nw < 100) {
                  nw = 72;
                } else if (nw < 200) {
                  nw = 200;
                }
                _leftPanelWidth = nw.clamp(72.0, 480.0);
              }),
              child: Container(
                width: 6,
                color: Colors.transparent,
                child: Center(child: Container(width: 1, height: double.infinity, color: c.border)),
              ),
            ),
          ),
          Expanded(child: _selected == null
            ? _NoChatSelected(c: c)
            : ChatPage(key: ValueKey(_selected!.id), conversationId: _selected!.id, conversation: _selected, embedded: true)),
        ])),
      );
    }
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(child: _LeftPanel(
        tab: _tab, query: _query, selected: _selected,
        isCompact: false,
        onTabChange: (t) => setState(() => _tab = t),
        onQueryChange: (q) => setState(() => _query = q),
        onSelect: (conv) {
          setState(() => _selected = conv);
          context.push('/messages/${conv.id}', extra: conv);
        },
        onOpenSelfChat: _openSelfChat,
      )),
    );
  }

  Future<void> _openSelfChat() async {
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Saqlangan xabarlar...'), duration: Duration(seconds: 1)));
    final conv = await const MessagesRepository().getOrCreateSelfChat(userId);
    if (!mounted) return;
    if (conv == null) return;
    await ref.read(conversationsProvider.notifier).load();
    if (!mounted) return;
    final w = MediaQuery.of(context).size.width;
    if (w >= _desktopBreakpoint) {
      setState(() { _tab = 'private'; _selected = conv; });
    } else {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChatPage(conversationId: conv.id, conversation: conv),
      ));
    }
  }
}

// ─── Left Panel ─────────────────────────────────────────────────────────────
class _LeftPanel extends ConsumerStatefulWidget {
  final String tab, query;
  final Conversation? selected;
  final bool isCompact;
  final ValueChanged<String> onTabChange, onQueryChange;
  final ValueChanged<Conversation> onSelect;
  final VoidCallback onOpenSelfChat;
  const _LeftPanel({required this.tab, required this.query, required this.selected,
    required this.isCompact, required this.onTabChange, required this.onQueryChange,
    required this.onSelect, required this.onOpenSelfChat});
  @override
  ConsumerState<_LeftPanel> createState() => _LeftPanelState();
}

class _LeftPanelState extends ConsumerState<_LeftPanel> {
  late final TextEditingController _searchCtrl;
  @override
  void initState() { super.initState(); _searchCtrl = TextEditingController(text: widget.query); }
  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  static const _tabs = [
    ('private','Shaxsiy'),('groups','Guruhlar'),('channels','Kanallar'),
    ('requests',"So'rovlar"),('archived','Arxiv'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final theme = Theme.of(context);
    final convState = ref.watch(conversationsProvider);
    final allConvs = convState.valueOrNull ?? [];

    final convs = allConvs.where((cv) {
      if (widget.tab == 'archived') return cv.isArchived;
      if (widget.tab == 'requests') return false;
      final typeMatch = widget.tab == 'private' ? cv.type == 'private'
        : widget.tab == 'groups' ? cv.type == 'group'
        : widget.tab == 'channels' ? cv.type == 'channel'
        : true;
      if (!typeMatch) return false;
      if (cv.isArchived) return false;
      final name = cv.title.toLowerCase();
      return widget.query.isEmpty || name.contains(widget.query.toLowerCase());
    }).toList()
      ..sort((a, b) {
        if (a.isPinned && !b.isPinned) return -1;
        if (!a.isPinned && b.isPinned) return 1;
        return b.lastMessageAt.compareTo(a.lastMessageAt);
      });

    if (widget.isCompact) {
      return Container(
        color: c.background,
        child: Column(children: [
          const SizedBox(height: 8),
          Expanded(child: ListView.builder(
            itemCount: convs.length,
            itemBuilder: (_, i) => _ChatListItem(
              conversation: convs[i], selected: widget.selected?.id == convs[i].id,
              isCompact: true, onTap: () => widget.onSelect(convs[i]),
            ),
          )),
        ]),
      );
    }

    return Column(children: [
      // Header
      Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 8),
        decoration: BoxDecoration(color: c.background, border: Border(bottom: BorderSide(color: c.border.withValues(alpha: 0.3)))),
        child: Column(children: [
          Row(children: [
            Expanded(child: Container(
              height: 40, decoration: BoxDecoration(color: c.muted, borderRadius: BorderRadius.circular(20)),
              child: TextField(
                controller: _searchCtrl,
                onChanged: widget.onQueryChange,
                style: TextStyle(fontSize: 14, color: c.foreground),
                decoration: InputDecoration(
                  hintText: 'Izlash...',
                  hintStyle: TextStyle(color: c.mutedForeground, fontSize: 14),
                  prefixIcon: Icon(LucideIcons.search, size: 16, color: c.mutedForeground),
                  suffixIcon: widget.query.isNotEmpty ? IconButton(
                    icon: Icon(LucideIcons.x, size: 16, color: c.mutedForeground),
                    onPressed: () { _searchCtrl.clear(); widget.onQueryChange(''); },
                  ) : null,
                  border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            )),
            const SizedBox(width: 4),
            _HeaderBtn(icon: LucideIcons.bookmark, tooltip: 'Saqlangan xabarlar', onTap: widget.onOpenSelfChat, c: c),
            _HeaderBtn(icon: LucideIcons.plus, tooltip: 'Yangi suhbat', isPrimary: true,
              onTap: () => _showNewChatDialog(context), c: c),
          ]),
          const SizedBox(height: 8),
          SizedBox(height: 36, child: ListView(scrollDirection: Axis.horizontal, children: _tabs.map((t) {
            final active = widget.tab == t.$1;
            return GestureDetector(
              onTap: () => widget.onTabChange(t.$1),
              child: Container(
                margin: const EdgeInsets.only(right: 4),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: active ? theme.colorScheme.primary : c.muted,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(t.$2, style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600,
                  color: active ? theme.colorScheme.onPrimary : c.mutedForeground,
                )),
              ),
            );
          }).toList())),
        ]),
      ),
      // List
      Expanded(child: convState.isLoading
        ? Center(child: CircularProgressIndicator(color: theme.colorScheme.primary))
        : convs.isEmpty
          ? _EmptyState(tab: widget.tab, c: c, onNewChat: () => _showNewChatDialog(context))
          : ListView.builder(
              itemCount: convs.length,
              itemBuilder: (_, i) => _ChatListItem(
                conversation: convs[i],
                selected: widget.selected?.id == convs[i].id,
                isCompact: false,
                onTap: () => widget.onSelect(convs[i]),
              ),
            ),
      ),
    ]);
  }

  void _showNewChatDialog(BuildContext context) {
    showModalBottomSheet(context: context, isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _NewChatSheet(
        onCreated: (conv) { Navigator.pop(ctx); widget.onSelect(conv); },
      ),
    );
  }

  // ignore: unused_element
  Future<void> _clearMessagesCache() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AlsamosColors.of(ctx).card.withValues(alpha: 0.98),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Messages cache tozalansinmi?'),
        content: const Text(
          'Lokal saqlangan suhbat va xabarlar tozalanadi. Serverdagi xabarlar o‘chmaydi.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Bekor'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Tozalash'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().toList()) {
      if (key.startsWith('alsamos_messages_') ||
          key.startsWith('alsamos_conversations_')) {
        await prefs.remove(key);
      }
    }
    if (!mounted) return;
    await ref.read(conversationsProvider.notifier).load();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Messages cache tozalandi')),
    );
  }
}

// ─── Chat List Item ──────────────────────────────────────────────────────────
class _ChatListItem extends ConsumerStatefulWidget {
  final Conversation conversation;
  final bool selected, isCompact;
  final VoidCallback onTap;
  const _ChatListItem({required this.conversation, required this.selected,
    required this.isCompact, required this.onTap});
  @override
  ConsumerState<_ChatListItem> createState() => _ChatListItemState();
}

class _ChatListItemState extends ConsumerState<_ChatListItem> with SingleTickerProviderStateMixin {
  bool _hover = false;
  late AnimationController _pulse;
  late Animation<double> _pulseAnim;
  int _prevUnread = 0;

  @override
  void initState() {
    super.initState();
    _prevUnread = widget.conversation.unreadCount;
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _pulseAnim = Tween(begin: 1.0, end: 1.3).chain(CurveTween(curve: Curves.easeOut)).animate(_pulse);
  }

  @override
  void didUpdateWidget(_ChatListItem old) {
    super.didUpdateWidget(old);
    if (widget.conversation.unreadCount > _prevUnread) {
      _pulse.forward(from: 0).then((_) => _pulse.reverse());
    }
    _prevUnread = widget.conversation.unreadCount;
  }

  @override
  void dispose() { _pulse.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final theme = Theme.of(context);
    final conv = widget.conversation;
    final isSelf = conv.isSelfChat;
    final isPrivate = conv.type == 'private';
    final otherId = conv.otherParticipant?.id;
    final online = isPrivate && !isSelf && otherId != null && ref.watch(isUserOnlineProvider(otherId));
    final unread = conv.unreadCount > 0;

    if (widget.isCompact) {
      return Tooltip(
        message: conv.title,
        preferBelow: false,
        child: GestureDetector(
          onSecondaryTapDown: (d) => _showMenu(context, d.globalPosition),
          onLongPressStart: (d) => _showMenu(context, d.globalPosition),
          child: InkWell(
            onTap: widget.onTap,
            child: Container(
              color: widget.selected ? theme.colorScheme.primary.withValues(alpha: 0.15) : null,
              padding: const EdgeInsets.symmetric(vertical: 10),
              alignment: Alignment.center,
              child: Stack(clipBehavior: Clip.none, children: [
                _Avatar(conv: conv, size: 44, online: online),
                if (unread) Positioned(right: -6, top: -6,
                  child: ScaleTransition(scale: _pulseAnim,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(color: theme.colorScheme.primary, borderRadius: BorderRadius.circular(9), border: Border.all(color: c.background, width: 1.5)),
                      child: Text(unread ? '${conv.unreadCount > 99 ? "99+" : conv.unreadCount}' : '',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: theme.colorScheme.onPrimary, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      );
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onSecondaryTapDown: (d) => _showMenu(context, d.globalPosition),
        onLongPressStart: (d) => _showMenu(context, d.globalPosition),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          color: widget.selected
            ? theme.colorScheme.primary.withValues(alpha: 0.12)
            : _hover ? c.muted.withValues(alpha: 0.5) : Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border.withValues(alpha: 0.2)))),
              child: Row(children: [
                _Avatar(conv: conv, size: 48, online: online),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Row(children: [
                      Flexible(child: Text(isSelf ? 'Saqlangan xabarlar' : conv.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: unread ? FontWeight.w700 : FontWeight.w600, fontSize: 14))),
                      if (conv.isVerified == true) ...[const SizedBox(width: 3), const VerifiedBadge(size: 13)],
                      if (conv.isPinned) ...[const SizedBox(width: 3), Icon(LucideIcons.pin, size: 12, color: c.mutedForeground)],
                      if (conv.isMuted) ...[const SizedBox(width: 3), Icon(LucideIcons.volumeX, size: 12, color: c.mutedForeground)],
                    ])),
                      Text(_fmt(conv.lastMessageAt), style: TextStyle(fontSize: 11, color: unread ? theme.colorScheme.primary : c.mutedForeground)),
                  ]),
                  const SizedBox(height: 2),
                  Row(children: [
                    Expanded(child: _LastMessage(conv: conv, c: c, unread: unread)),
                    if (unread) const SizedBox(width: 6),
                    if (unread) ScaleTransition(scale: _pulseAnim, child: Container(
                      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      decoration: BoxDecoration(
                        color: conv.isMuted ? c.mutedForeground : theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(conv.unreadCount > 99 ? '99+' : '${conv.unreadCount}',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                    )),
                  ]),
                ])),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  String _fmt(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return DateFormat('HH:mm').format(d);
    if (diff == 1) return 'Kecha';
    if (diff < 7) return DateFormat('EEE').format(d);
    return DateFormat('dd.MM.yy').format(d);
  }

  void _showMenu(BuildContext context, Offset? pos) {
    if (pos == null) return;
    HapticFeedback.lightImpact();
    final conv = widget.conversation;
    final notifier = ref.read(conversationsProvider.notifier);
    
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final rect = overlay == null
        ? RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy)
        : RelativeRect.fromRect(
            Rect.fromLTWH(pos.dx, pos.dy, 1, 1),
            Offset.zero & overlay.size,
          );
    showMenu(
      context: context,
      position: rect,
      constraints: const BoxConstraints(minWidth: 240, maxWidth: 320),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.94),
      elevation: 14,
      items: [
        PopupMenuItem(
          onTap: () => notifier.togglePin(conv.id),
          child: Row(children: [
            Icon(conv.isPinned ? LucideIcons.pinOff : LucideIcons.pin, size: 18),
            const SizedBox(width: 12),
            Text(conv.isPinned ? 'Pindan olish' : 'Pinlash')
          ]),
        ),
        PopupMenuItem(
          onTap: () => notifier.toggleMute(conv.id),
          child: Row(children: [
            Icon(conv.isMuted ? LucideIcons.volume2 : LucideIcons.volumeX, size: 18),
            const SizedBox(width: 12),
            Text(conv.isMuted ? 'Ovozni yoqish' : 'Ovozni o\'chiring')
          ]),
        ),
        PopupMenuItem(
          onTap: () => notifier.markAsRead(conv.id),
          child: Row(children: [
            const Icon(LucideIcons.checkCheck, size: 18),
            const SizedBox(width: 12),
            const Text('O\'qilgan deb belgilash')
          ]),
        ),
        if (!conv.isArchived)
          PopupMenuItem(
            onTap: () => notifier.archive(conv.id),
            child: Row(children: [
              const Icon(LucideIcons.archive, size: 18),
              const SizedBox(width: 12),
              const Text('Arxivlash')
            ]),
          ),
        if (conv.isArchived)
          PopupMenuItem(
            onTap: () => notifier.unarchive(conv.id),
            child: Row(children: [
              const Icon(LucideIcons.archiveRestore, size: 18),
              const SizedBox(width: 12),
              const Text('Arxivdan chiqarish')
            ]),
          ),
        PopupMenuItem(
          onTap: () async {
            // Delay a bit to let menu close first before dialog opens
            Future.delayed(const Duration(milliseconds: 100), () async {
              final ok = await showDialog<bool>(context: context,
                builder: (d) => AlertDialog(
                  title: const Text("Suhbatni o'chirish?"),
                  content: const Text("Barcha xabarlar o'chiriladi."),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Bekor')),
                    TextButton(onPressed: () => Navigator.pop(d, true),
                      child: const Text("O'chirish", style: TextStyle(color: Colors.red))),
                  ],
                ));
              if (ok == true) await notifier.delete(conv.id);
            });
          },
          child: const Row(children: [
            Icon(LucideIcons.trash2, size: 18, color: Colors.red),
            SizedBox(width: 12),
            Text('O\'chirish', style: TextStyle(color: Colors.red))
          ]),
        ),
      ],
    );
  }
}

// ─── Avatar widget ────────────────────────────────────────────────────────────
class _Avatar extends StatelessWidget {
  final Conversation conv;
  final double size;
  final bool online;
  const _Avatar({required this.conv, required this.size, required this.online});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = AlsamosColors.of(context);
    final isSelf = conv.isSelfChat;
    final isGroup = conv.type == 'group';
    final isChannel = conv.type == 'channel';
    final avatarUrl = conv.type == 'private' ? conv.otherParticipant?.avatarUrl : conv.avatarUrl;
    Widget avatar = avatarUrl != null && avatarUrl.isNotEmpty
      ? CircleAvatar(radius: size / 2, backgroundImage: NetworkImage(avatarUrl))
      : CircleAvatar(
          radius: size / 2,
          backgroundColor: theme.colorScheme.primary,
          child: Icon(
            isSelf ? LucideIcons.bookmark : isGroup ? LucideIcons.users : isChannel ? LucideIcons.megaphone : null,
            size: size * 0.42,
            color: Colors.white,
          ),
        );
    if (avatarUrl == null || avatarUrl.isEmpty) {
      if (!isSelf && !isGroup && !isChannel) {
        final name = conv.title;
        avatar = CircleAvatar(
          radius: size / 2,
          backgroundColor: theme.colorScheme.primary,
          child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: TextStyle(color: Colors.white, fontSize: size * 0.38, fontWeight: FontWeight.w600)),
        );
      }
    }
    return Stack(clipBehavior: Clip.none, children: [
      SizedBox(width: size, height: size, child: avatar),
      if (online) Positioned(right: 1, bottom: 1, child: Container(
        width: size * 0.28, height: size * 0.28,
        decoration: BoxDecoration(color: const Color(0xFF22C55E), shape: BoxShape.circle,
          border: Border.all(color: c.background, width: 1.5)),
      )),
      if (isSelf) Positioned(right: -2, bottom: -2, child: Container(
        width: size * 0.32, height: size * 0.32,
        decoration: BoxDecoration(color: c.card, shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFF59E0B), width: 1.5)),
        child: Icon(LucideIcons.bookmark, size: size * 0.16, color: const Color(0xFFF59E0B)),
      )),
    ]);
  }
}

// ─── Last Message ─────────────────────────────────────────────────────────────
class _LastMessage extends StatelessWidget {
  final Conversation conv;
  final AlsamosColors c;
  final bool unread;
  const _LastMessage({required this.conv, required this.c, required this.unread});
  @override
  Widget build(BuildContext context) {
    final draft = chatDrafts[conv.id];
    if (draft != null) {
      return Text.rich(
        TextSpan(children: [
          const TextSpan(text: 'Qoralama: ', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w500)),
          TextSpan(text: draft, style: TextStyle(color: unread ? c.foreground : c.mutedForeground)),
        ]),
        maxLines: 1, overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13),
      );
    }
    
    final msg = conv.lastMessage;
    if (msg == null || msg.isEmpty) {
      return Text('Hali xabar yo\'q', style: TextStyle(fontSize: 12, color: c.mutedForeground), maxLines: 1, overflow: TextOverflow.ellipsis);
    }
    IconData? icon; Color iconColor = c.mutedForeground; String text = msg;
    if (msg.startsWith('{') && msg.contains('"type"')) {
      try {
        final d = jsonDecode(msg) as Map<String, dynamic>;
        final t = d['type'] as String?;
        if (t == 'video' || t == 'audio') {
          final isVideo = t == 'video';
          final status = d['status'] as String?;
          switch (status) {
            case 'missed': text = isVideo ? "O'tkazib yuborilgan video" : "O'tkazib yuborilgan qo'ng'iroq"; icon = LucideIcons.phoneMissed; iconColor = Colors.red; break;
            case 'declined': text = isVideo ? "Rad etilgan video" : "Rad etilgan qo'ng'iroq"; icon = LucideIcons.phoneOff; iconColor = Colors.orange; break;
            default:
              text = isVideo ? "Video qo'ng'iroq" : "Qo'ng'iroq";
              final dur = d['duration'];
              if (dur is num) { final m = dur ~/ 60; final s = (dur.toInt() % 60).toString().padLeft(2,'0'); text += ' ($m:$s)'; }
              icon = isVideo ? LucideIcons.video : LucideIcons.phone; iconColor = Colors.green;
          }
        }
      } catch (_) {}
    }
    return Row(children: [
      if (icon != null) ...[Icon(icon, size: 13, color: iconColor), const SizedBox(width: 3)],
      Expanded(child: Text(text,
        maxLines: 1, overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: unread ? c.foreground : c.mutedForeground,
          fontWeight: unread ? FontWeight.w500 : FontWeight.normal))),
    ]);
  }
}

// ─── Helper Widgets ───────────────────────────────────────────────────────────
class _HeaderBtn extends StatelessWidget {
  final IconData icon; final String tooltip; final VoidCallback onTap;
  final bool isPrimary; final AlsamosColors c;
  const _HeaderBtn({required this.icon, required this.tooltip, required this.onTap, required this.c, this.isPrimary = false});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap, borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 36, height: 36, margin: const EdgeInsets.only(left: 4),
          decoration: BoxDecoration(
            color: isPrimary ? theme.colorScheme.primary : c.muted,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 16, color: isPrimary ? theme.colorScheme.onPrimary : c.foreground),
        ),
      ),
    );
  }
}


class _NoChatSelected extends StatelessWidget {
  final AlsamosColors c;
  const _NoChatSelected({required this.c});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 80, height: 80, decoration: BoxDecoration(color: theme.colorScheme.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
        child: Icon(LucideIcons.messageCircle, size: 36, color: theme.colorScheme.primary)),
      const SizedBox(height: 16),
      Text('Suhbat tanlang', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: c.foreground)),
      const SizedBox(height: 6),
      Text('Chap tomondagi ro\'yxatdan suhbat tanlang', style: TextStyle(fontSize: 13, color: c.mutedForeground)),
    ]));
  }
}

class _EmptyState extends StatelessWidget {
  final String tab; final AlsamosColors c; final VoidCallback onNewChat;
  const _EmptyState({required this.tab, required this.c, required this.onNewChat});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    IconData icon; String title, sub;
    switch (tab) {
      case 'archived': icon = LucideIcons.archive; title = 'Arxiv bo\'sh'; sub = 'Arxivlangan suhbatlar bu yerda ko\'rinadi'; break;
      case 'requests': icon = LucideIcons.inbox; title = 'So\'rovlar yo\'q'; sub = 'Yangi xabar so\'rovlari bu yerda ko\'rinadi'; break;
      default: icon = LucideIcons.messageCircle; title = 'Suhbatlar yo\'q'; sub = 'Birinchi suhbatni boshlang!';
    }
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 64, height: 64, decoration: BoxDecoration(color: theme.colorScheme.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
        child: Icon(icon, size: 28, color: theme.colorScheme.primary)),
      const SizedBox(height: 12),
      Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: c.foreground)),
      const SizedBox(height: 4),
      Text(sub, style: TextStyle(fontSize: 12, color: c.mutedForeground), textAlign: TextAlign.center),
      if (tab == 'private') ...[
        const SizedBox(height: 16),
        ElevatedButton.icon(onPressed: onNewChat, icon: const Icon(LucideIcons.plus, size: 16), label: const Text('Yangi suhbat')),
      ],
    ]));
  }
}

// ─── New Chat Sheet ───────────────────────────────────────────────────────────
class _NewChatSheet extends ConsumerStatefulWidget {
  final ValueChanged<Conversation> onCreated;
  const _NewChatSheet({required this.onCreated});
  @override
  ConsumerState<_NewChatSheet> createState() => _NewChatSheetState();
}

class _NewChatSheetState extends ConsumerState<_NewChatSheet> {
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  Future<void> _search(String q) async {
    if (q.length < 2) { setState(() => _results = []); return; }
    setState(() => _loading = true);
    try {
      final res = await Supabase.instance.client
        .from('profiles').select('id, username, display_name, avatar_url, is_verified')
        .or('username.ilike.%$q%,display_name.ilike.%$q%').limit(20);
      final userId = ref.read(authProvider).user?.id;
      setState(() { _results = (res as List).where((p) => p['id'] != userId).cast<Map<String,dynamic>>().toList(); });
    } catch (_) {} finally { setState(() => _loading = false); }
  }

  Future<void> _start(Map<String, dynamic> profile) async {
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) return;
    setState(() => _loading = true);
    try {
      final convId = await const MessagesRepository().createPrivateConversation(userId, profile['id'] as String);
      if (convId != null && mounted) {
        await ref.read(conversationsProvider.notifier).load();
        final convs = ref.read(conversationsProvider).valueOrNull ?? [];
        final conv = convs.where((c) => c.id == convId).firstOrNull;
        if (conv != null && mounted) { widget.onCreated(conv); }
      }
    } catch (_) {} finally { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final theme = Theme.of(context);
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      margin: const EdgeInsets.all(0),
      decoration: BoxDecoration(color: c.card, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(children: [
        Container(margin: const EdgeInsets.only(top: 10, bottom: 8), width: 36, height: 4,
          decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(2))),
        Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Row(children: [
            const Icon(LucideIcons.userPlus, size: 20),
            const SizedBox(width: 8),
            const Text('Yangi suhbat', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const Spacer(),
            IconButton(icon: const Icon(LucideIcons.x), onPressed: () => Navigator.pop(context)),
          ])),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _searchCtrl, autofocus: true,
            onChanged: _search,
            decoration: InputDecoration(
              hintText: 'Foydalanuvchi qidirish...',
              prefixIcon: const Icon(LucideIcons.search, size: 18),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.border)),
              filled: true, fillColor: c.muted,
            ),
          )),
        const SizedBox(height: 8),
        Expanded(child: _loading
          ? Center(child: CircularProgressIndicator(color: theme.colorScheme.primary))
          : _searchCtrl.text.isEmpty
            ? ListView(
                children: [
                  ListTile(
                    leading: const CircleAvatar(backgroundColor: Colors.blue, child: Icon(LucideIcons.users, color: Colors.white, size: 20)),
                    title: const Text('Yangi guruh', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('A\'zolar qo\'shing va muloqot boshlang', style: TextStyle(fontSize: 12)),
                    onTap: () {
                      Navigator.pop(context);
                      CreateGroupChannelSheet.show(
                        context,
                        isChannel: false,
                        onCreated: widget.onCreated,
                      );
                    },
                  ),
                  ListTile(
                    leading: const CircleAvatar(backgroundColor: Colors.orange, child: Icon(LucideIcons.megaphone, color: Colors.white, size: 20)),
                    title: const Text('Yangi kanal', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('Ommaga xabar tarqating', style: TextStyle(fontSize: 12)),
                    onTap: () {
                      Navigator.pop(context);
                      CreateGroupChannelSheet.show(
                        context,
                        isChannel: true,
                        onCreated: widget.onCreated,
                      );
                    },
                  ),
                ],
              )
            : _results.isEmpty && _searchCtrl.text.length >= 2
              ? Center(child: Text('Topilmadi', style: TextStyle(color: c.mutedForeground)))
              : ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (_, i) {
                    final p = _results[i];
                    final name = p['display_name'] as String? ?? p['username'] as String? ?? 'Unknown';
                    final avatar = p['avatar_url'] as String?;
                    return ListTile(
                      leading: avatar != null && avatar.isNotEmpty
                        ? CircleAvatar(backgroundImage: NetworkImage(avatar))
                        : CircleAvatar(backgroundColor: theme.colorScheme.primary,
                            child: Text(name[0].toUpperCase(), style: const TextStyle(color: Colors.white))),
                      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: p['username'] != null ? Text('@${p['username']}', style: TextStyle(color: c.mutedForeground, fontSize: 12)) : null,
                      trailing: p['is_verified'] == true ? const VerifiedBadge(size: 16) : null,
                      onTap: () => _start(p),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}
