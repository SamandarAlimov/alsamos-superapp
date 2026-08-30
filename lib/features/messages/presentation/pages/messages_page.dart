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
import '../../../../core/responsive/breakpoints.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../../../shared/widgets/verified_badge.dart';
import '../../../../shared/widgets/count_badge.dart' as shared_badges;
import '../../../../shared/stories/story_avatar_ring.dart';
import '../../data/models/conversation_model.dart';
import '../../data/models/message_model.dart';
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

class _MessagesPageState extends ConsumerState<MessagesPage>
    with TickerProviderStateMixin {
  String _tab = 'private';
  String _query = '';
  Conversation? _selected;
  double _leftPanelWidth = 320.0;
  static const _desktopBreakpoint = Responsive.desktopMin;

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final w = MediaQuery.of(context).size.width;
    final isDesktop = w >= _desktopBreakpoint;
    if (isDesktop) {
      final maxLeftPanel = (w * 0.42).clamp(320.0, 480.0).toDouble();
      final leftPanelWidth =
          _leftPanelWidth.clamp(280.0, maxLeftPanel).toDouble();
      return Scaffold(
        backgroundColor: c.background,
        body: SafeArea(
            child: Row(children: [
          SizedBox(
            width: leftPanelWidth,
            child: _LeftPanel(
              tab: _tab,
              query: _query,
              selected: _selected,
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
                double nw = leftPanelWidth + d.delta.dx;
                if (nw < 100) {
                  nw = 72;
                } else if (nw < 200) {
                  nw = 200;
                }
                _leftPanelWidth = nw.clamp(72.0, maxLeftPanel).toDouble();
              }),
              child: Container(
                width: 6,
                color: Colors.transparent,
                child: Center(
                    child: Container(
                        width: 1, height: double.infinity, color: c.border)),
              ),
            ),
          ),
          Expanded(
              child: _selected == null
                  ? _NoChatSelected(c: c)
                  : ChatPage(
                      key: ValueKey(_selected!.id),
                      conversationId: _selected!.id,
                      conversation: _selected,
                      embedded: true)),
        ])),
      );
    }
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
          child: _LeftPanel(
        tab: _tab,
        query: _query,
        selected: _selected,
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
    AppToast.info(context, 'Saqlangan xabarlar...');
    final conv = await const MessagesRepository().getOrCreateSelfChat(userId);
    if (!mounted) return;
    if (conv == null) return;
    await ref.read(conversationsProvider.notifier).load();
    if (!mounted) return;
    final w = MediaQuery.of(context).size.width;
    if (w >= _desktopBreakpoint) {
      setState(() {
        _tab = 'private';
        _selected = conv;
      });
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
  const _LeftPanel(
      {required this.tab,
      required this.query,
      required this.selected,
      required this.isCompact,
      required this.onTabChange,
      required this.onQueryChange,
      required this.onSelect,
      required this.onOpenSelfChat});
  @override
  ConsumerState<_LeftPanel> createState() => _LeftPanelState();
}

class _LeftPanelState extends ConsumerState<_LeftPanel> {
  late final TextEditingController _searchCtrl;
  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController(text: widget.query);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<(String, String)> _tabs() => [
        ('private', 'Private'),
        ('groups', 'Groups'),
        ('channels', 'Channels'),
        ('requests', 'Requests'),
        ('archived', 'Archived'),
      ];

  int _countForTab(
      List<Conversation> items, String tab, List<ChatFolder> folders) {
    return items.where((cv) {
      if (tab == 'archived') return cv.isArchived;
      if (cv.isArchived) return false;
      if (tab == 'requests') return false;
      if (tab.startsWith('folder:')) {
        final id = tab.substring(7);
        final folder = folders.where((f) => f.id == id).firstOrNull;
        return folder?.matches(cv) ?? false;
      }
      return tab == 'private'
          ? cv.type == 'private'
          : tab == 'groups'
              ? cv.type == 'group'
              : tab == 'channels'
                  ? cv.type == 'channel'
                  : true;
    }).fold<int>(0, (sum, cv) {
      if (cv.isMutedEffective) return sum;
      return sum + cv.visibleUnreadCount + (cv.manuallyUnread ? 1 : 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final theme = Theme.of(context);
    final convState = ref.watch(conversationsProvider);
    final folders = ref.watch(chatFoldersProvider).valueOrNull ?? const [];
    final tabs = _tabs();
    final allConvs = convState.valueOrNull ?? [];
    final counts = {
      for (final tab in tabs) tab.$1: _countForTab(allConvs, tab.$1, folders)
    };
    final convs = allConvs.where((cv) {
      if (widget.tab == 'archived') return cv.isArchived;
      if (cv.isArchived) return false;
      if (widget.tab == 'requests') return false;
      if (widget.tab.startsWith('folder:')) {
        final id = widget.tab.substring(7);
        final folder = folders.where((f) => f.id == id).firstOrNull;
        if (folder == null || !folder.matches(cv)) return false;
      } else {
        final typeMatch = widget.tab == 'private'
            ? cv.type == 'private'
            : widget.tab == 'groups'
                ? cv.type == 'group'
                : widget.tab == 'channels'
                    ? cv.type == 'channel'
                    : true;
        if (!typeMatch) return false;
      }
      final name = cv.title.toLowerCase();
      return widget.query.isEmpty || name.contains(widget.query.toLowerCase());
    }).toList()
      ..sort((a, b) {
        if (a.isPinned && !b.isPinned) return -1;
        if (!a.isPinned && b.isPinned) return 1;
        if (a.isPinned && b.isPinned) {
          final po =
              (a.pinnedOrder ?? 1 << 30).compareTo(b.pinnedOrder ?? 1 << 30);
          if (po != 0) return po;
        }
        return b.activityAt.compareTo(a.activityAt);
      });

    if (widget.isCompact) {
      return Container(
        color: c.background,
        child: Column(children: [
          const SizedBox(height: 8),
          Expanded(
              child: ListView.builder(
            itemCount: convs.length,
            itemBuilder: (_, i) => _ChatListItem(
              conversation: convs[i],
              selected: widget.selected?.id == convs[i].id,
              isCompact: true,
              onTap: () => widget.onSelect(convs[i]),
            ),
          )),
        ]),
      );
    }

    return Column(children: [
      // Header
      Container(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 0),
        decoration: BoxDecoration(
            color: c.background,
            border: Border(
                bottom: BorderSide(color: c.border.withValues(alpha: 0.3)))),
        child: Column(children: [
          Row(children: [
            Expanded(
                child: Container(
              height: 52,
              decoration: BoxDecoration(
                color: c.muted.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: c.border.withValues(alpha: 0.5)),
              ),
              clipBehavior: Clip.antiAlias,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: widget.onQueryChange,
                  style: TextStyle(fontSize: 14, color: c.foreground),
                  decoration: InputDecoration(
                    hintText: 'Izlash...',
                    hintStyle:
                        TextStyle(color: c.mutedForeground, fontSize: 14),
                    prefixIcon: Icon(LucideIcons.search,
                        size: 18, color: c.mutedForeground),
                    suffixIcon: widget.query.isNotEmpty
                        ? IconButton(
                            icon: Icon(LucideIcons.x,
                                size: 16, color: c.mutedForeground),
                            onPressed: () {
                              _searchCtrl.clear();
                              widget.onQueryChange('');
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                ),
              ),
            )),
            const SizedBox(width: 8),
            _HeaderBtn(
                icon: LucideIcons.bookmark,
                tooltip: 'Saqlangan xabarlar',
                onTap: widget.onOpenSelfChat,
                c: c),
            _HeaderBtn(
                icon: LucideIcons.plus,
                tooltip: 'Yangi suhbat',
                isPrimary: true,
                onTap: () => _showNewChatDialog(context),
                c: c),
          ]),
          if (widget.query.trim().isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _showGlobalMessageSearch(
                  context,
                  widget.query.trim(),
                  allConvs,
                ),
                icon: const Icon(LucideIcons.search, size: 16),
                label: Text('"${widget.query.trim()}" xabarlar ichidan izlash'),
              ),
            ),
          const SizedBox(height: 12),
          _MessagesSegmentedTabs(
            tabs: tabs,
            current: widget.tab,
            counts: counts,
            onChanged: widget.onTabChange,
          ),
        ]),
      ),
      // List
      Expanded(
        child: convState.isLoading
            ? Center(
                child:
                    CircularProgressIndicator(color: theme.colorScheme.primary))
            : convs.isEmpty
                ? _EmptyState(
                    tab: widget.tab,
                    c: c,
                    onNewChat: () => _showNewChatDialog(context))
                : AnimatedSwitcher(
                    duration: const Duration(milliseconds: 240),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0.02, 0),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: _AnimatedConversationList(
                      key: ValueKey(
                          '${widget.tab}:${widget.query}:${convs.map((c) => c.id).join(",")}'),
                      conversations: convs,
                      selectedId: widget.selected?.id,
                      onSelect: widget.onSelect,
                    ),
                  ),
      ),
    ]);
  }

  void _showNewChatDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _NewChatSheet(
        onCreated: (conv) {
          Navigator.pop(ctx);
          widget.onSelect(conv);
        },
      ),
    );
  }

  Future<void> _showGlobalMessageSearch(
    BuildContext context,
    String initialQuery,
    List<Conversation> conversations,
  ) async {
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _GlobalMessageSearchSheet(
        userId: userId,
        initialQuery: initialQuery,
        conversations: conversations,
        onOpen: (message) {
          final conv = conversations
              .where((item) => item.id == message.conversationId)
              .firstOrNull;
          if (conv == null) return;
          pendingMessageHighlights[conv.id] = message.id;
          Navigator.pop(ctx);
          widget.onSelect(conv);
        },
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
    AppToast.success(context, 'Messages cache tozalandi');
  }
}

// ─── Chat List Item ──────────────────────────────────────────────────────────
class _GlobalMessageSearchSheet extends ConsumerStatefulWidget {
  const _GlobalMessageSearchSheet({
    required this.userId,
    required this.initialQuery,
    required this.conversations,
    required this.onOpen,
  });

  final String userId;
  final String initialQuery;
  final List<Conversation> conversations;
  final ValueChanged<Message> onOpen;

  @override
  ConsumerState<_GlobalMessageSearchSheet> createState() =>
      _GlobalMessageSearchSheetState();
}

class _GlobalMessageSearchSheetState
    extends ConsumerState<_GlobalMessageSearchSheet> {
  late final TextEditingController _query;
  String? _filter;
  Future<List<Message>>? _future;

  @override
  void initState() {
    super.initState();
    _query = TextEditingController(text: widget.initialQuery);
    _search();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _search() {
    final q = _query.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _future = ref.read(messagesRepositoryProvider).globalMessageSearch(
            userId: widget.userId,
            query: q,
            mediaType: _filter,
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.82,
      minChildSize: 0.45,
      maxChildSize: 0.96,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Row(children: [
            const Icon(LucideIcons.search),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Global xabar qidiruvi',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ),
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(LucideIcons.x),
            ),
          ]),
          TextField(
            controller: _query,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              prefixIcon: const Icon(LucideIcons.search),
              suffixIcon: IconButton(
                onPressed: _search,
                icon: const Icon(LucideIcons.arrowRight),
              ),
              hintText: 'Xabar, #hashtag yoki havola izlash',
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final item in const [
                  (null, 'Hammasi'),
                  ('image', 'Media'),
                  ('file', 'Fayllar'),
                  ('link', 'Linklar'),
                  ('audio', 'Audio'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(item.$2),
                      selected: _filter == item.$1,
                      onSelected: (_) {
                        setState(() => _filter = item.$1);
                        _search();
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: FutureBuilder<List<Message>>(
              future: _future,
              builder: (_, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final results = snap.data ?? const [];
                if (results.isEmpty) {
                  return Center(
                    child: Text('Natija yo‘q',
                        style: TextStyle(color: c.mutedForeground)),
                  );
                }
                return ListView.separated(
                  controller: controller,
                  itemCount: results.length,
                  separatorBuilder: (_, __) => Divider(color: c.border),
                  itemBuilder: (_, i) {
                    final m = results[i];
                    final conv = widget.conversations
                        .where((item) => item.id == m.conversationId)
                        .firstOrNull;
                    return ListTile(
                      leading: Icon(
                        m.mediaType == null
                            ? LucideIcons.messageCircle
                            : LucideIcons.paperclip,
                      ),
                      title: Text(conv?.title ?? 'Suhbat',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        m.content?.trim().isNotEmpty == true
                            ? m.content!.trim()
                            : (m.mediaType ?? 'media'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Text(DateFormat('dd.MM').format(m.createdAt)),
                      onTap: () => widget.onOpen(m),
                    );
                  },
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

class _MessagesSegmentedTabs extends StatelessWidget {
  final List<(String, String)> tabs;
  final String current;
  final Map<String, int> counts;
  final ValueChanged<String> onChanged;

  const _MessagesSegmentedTabs({
    required this.tabs,
    required this.current,
    required this.counts,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);

    return SizedBox(
      height: 48,
      width: double.infinity,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.card.withValues(alpha: 0.74),
            borderRadius: BorderRadius.circular(23),
            border: Border.all(color: c.border.withValues(alpha: 0.34)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Row(
              children: [
                for (final tab in tabs)
                  _MessagesSegmentButton(
                    label: tab.$2,
                    count: counts[tab.$1] ?? 0,
                    selected: tab.$1 == current,
                    onTap: () => onChanged(tab.$1),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MessagesSegmentButton extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _MessagesSegmentButton({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final theme = Theme.of(context);
    final textColor = selected ? c.foreground : c.mutedForeground;

    return Padding(
      padding: const EdgeInsets.only(left: 1, right: 1),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: selected ? null : onTap,
          borderRadius: BorderRadius.circular(20),
          hoverColor: c.muted.withValues(alpha: 0.46),
          splashColor: theme.colorScheme.primary.withValues(alpha: 0.08),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 13),
            constraints: const BoxConstraints(minWidth: 76),
            decoration: BoxDecoration(
              color: selected
                  ? c.background.withValues(alpha: 0.92)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(19),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.07),
                        blurRadius: 14,
                        offset: const Offset(0, 7),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    letterSpacing: 0,
                  ),
                  child: Text(label, maxLines: 1, softWrap: false),
                ),
                if (count > 0) ...[
                  const SizedBox(width: 6),
                  shared_badges.CountBadge(
                    count: count,
                    height: 16,
                    subdued: !selected,
                    color: selected ? theme.colorScheme.primary : null,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedConversationList extends StatelessWidget {
  final List<Conversation> conversations;
  final String? selectedId;
  final ValueChanged<Conversation> onSelect;

  const _AnimatedConversationList({
    super.key,
    required this.conversations,
    required this.selectedId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      key: PageStorageKey(
          'messages-list-${conversations.length}-${conversations.firstOrNull?.id ?? "empty"}'),
      physics:
          const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      itemCount: conversations.length,
      itemBuilder: (_, i) {
        final conv = conversations[i];
        final delay = (i * 28).clamp(0, 180);
        return TweenAnimationBuilder<double>(
          key: ValueKey(conv.id),
          tween: Tween(begin: 0, end: 1),
          duration: Duration(milliseconds: 220 + delay),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) => Opacity(
            opacity: value,
            child: Transform.translate(
              offset: Offset(0, 10 * (1 - value)),
              child: child,
            ),
          ),
          child: _ChatListItem(
            conversation: conv,
            selected: selectedId == conv.id,
            isCompact: false,
            onTap: () => onSelect(conv),
          ),
        );
      },
    );
  }
}

class _ChatListItem extends ConsumerStatefulWidget {
  final Conversation conversation;
  final bool selected, isCompact;
  final VoidCallback onTap;
  const _ChatListItem(
      {required this.conversation,
      required this.selected,
      required this.isCompact,
      required this.onTap});
  @override
  ConsumerState<_ChatListItem> createState() => _ChatListItemState();
}

class _ChatListItemState extends ConsumerState<_ChatListItem>
    with SingleTickerProviderStateMixin {
  bool _hover = false;
  late AnimationController _pulse;
  late Animation<double> _pulseAnim;
  int _prevUnread = 0;

  @override
  void initState() {
    super.initState();
    _prevUnread = widget.conversation.unreadCount;
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _pulseAnim = Tween(begin: 1.0, end: 1.3)
        .chain(CurveTween(curve: Curves.easeOut))
        .animate(_pulse);
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
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final theme = Theme.of(context);
    final conv = widget.conversation;
    final isSelf = conv.isSelfChat;
    final isPrivate = conv.type == 'private';
    final otherId = conv.otherParticipant?.id;
    final online = isPrivate &&
        !isSelf &&
        otherId != null &&
        ref.watch(isUserOnlineProvider(otherId));
    final unread = conv.visibleUnreadCount > 0 || conv.manuallyUnread;
    final mentionCount = conv.mentionCount;

    if (widget.isCompact) {
      return Tooltip(
        message: conv.title,
        preferBelow: false,
        child: GestureDetector(
          onSecondaryTapDown: (d) => _showMenu(context, d.globalPosition),
          onLongPressStart: (d) => _showMenu(context, d.globalPosition),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            child: Material(
              color: widget.selected
                  ? theme.colorScheme.primary.withValues(alpha: 0.15)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: widget.onTap,
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  alignment: Alignment.center,
                  child: Stack(clipBehavior: Clip.none, children: [
                    _Avatar(conv: conv, size: 44, online: online),
                    if (unread || mentionCount > 0)
                      Positioned(
                        right: -6,
                        top: -6,
                        child: ScaleTransition(
                          scale: _pulseAnim,
                          child: mentionCount > 0
                              ? shared_badges.CountBadge(
                                  count: 1,
                                  label: '@',
                                  height: 18,
                                  color: const Color(0xFFFF2D55),
                                )
                              : shared_badges.CountBadge(
                                  count: conv.visibleUnreadCount,
                                  height: 18,
                                  color: theme.colorScheme.primary,
                                  subdued: conv.isMutedEffective,
                                ),
                        ),
                      ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Dismissible(
      key: ValueKey('chat-row-${conv.id}-${conv.isArchived}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        final notifier = ref.read(conversationsProvider.notifier);
        conv.isArchived
            ? await notifier.unarchive(conv.id)
            : await notifier.archive(conv.id);
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: theme.colorScheme.primary,
        child: Icon(
          conv.isArchived ? LucideIcons.archiveRestore : LucideIcons.archive,
          color: theme.colorScheme.onPrimary,
        ),
      ),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onSecondaryTapDown: (d) => _showMenu(context, d.globalPosition),
          onLongPressStart: (d) => _showMenu(context, d.globalPosition),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                color: widget.selected
                    ? theme.colorScheme.primary.withValues(alpha: 0.12)
                    : _hover
                        ? c.muted.withValues(alpha: 0.5)
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(18),
              ),
              clipBehavior: Clip.antiAlias,
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(18),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: widget.onTap,
                  borderRadius: BorderRadius.circular(18),
                  hoverColor: Colors.transparent,
                  highlightColor:
                      theme.colorScheme.primary.withValues(alpha: 0.06),
                  splashColor:
                      theme.colorScheme.primary.withValues(alpha: 0.08),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                        border: Border(
                            bottom: BorderSide(
                                color: c.border.withValues(alpha: 0.2)))),
                    child: Row(children: [
                      _Avatar(conv: conv, size: 48, online: online),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Row(children: [
                              Expanded(
                                  child: Row(children: [
                                Flexible(
                                    child: Text(
                                        isSelf
                                            ? 'Saqlangan xabarlar'
                                            : conv.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontWeight: unread
                                                ? FontWeight.w700
                                                : FontWeight.w600,
                                            fontSize: 14))),
                                if (conv.isVerified == true) ...[
                                  const SizedBox(width: 3),
                                  const VerifiedBadge(size: 13)
                                ],
                                if (conv.isPinned) ...[
                                  const SizedBox(width: 3),
                                  Icon(LucideIcons.pin,
                                      size: 12, color: c.mutedForeground)
                                ],
                                if (conv.isMuted) ...[
                                  const SizedBox(width: 3),
                                  Icon(LucideIcons.volumeX,
                                      size: 12, color: c.mutedForeground)
                                ],
                              ])),
                              Text(_fmt(conv.activityAt),
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: unread
                                          ? theme.colorScheme.primary
                                          : c.mutedForeground)),
                            ]),
                            const SizedBox(height: 2),
                            Row(children: [
                              Expanded(
                                  child: _LastMessage(
                                      conv: conv, c: c, unread: unread)),
                              if (mentionCount > 0) ...[
                                const SizedBox(width: 6),
                                shared_badges.CountBadge(
                                  count: 1,
                                  label: '@',
                                  color: const Color(0xFFFF2D55),
                                ),
                              ],
                              if (conv.visibleUnreadCount > 0) ...[
                                const SizedBox(width: 6),
                                shared_badges.CountBadge(
                                  count: conv.visibleUnreadCount,
                                  color: theme.colorScheme.primary,
                                  subdued: conv.isMutedEffective,
                                ),
                              ],
                            ]),
                          ])),
                    ]),
                  ),
                ),
              ),
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
    final unread = conv.visibleUnreadCount > 0 || conv.manuallyUnread;

    final overlay =
        Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?;
    final overlaySize = overlay?.size ?? MediaQuery.sizeOf(context);
    final anchor = overlay?.globalToLocal(pos) ?? pos;
    const menuWidth = 280.0;
    const menuHeight = 336.0;
    final panelBox = context.findRenderObject() as RenderBox?;
    final panelTopLeft = panelBox?.localToGlobal(Offset.zero) ?? Offset.zero;
    final panelSize = panelBox?.size ?? overlaySize;
    final panelLeft = panelTopLeft.dx;
    final panelRight = panelTopLeft.dx + panelSize.width;
    final preferredLeft = anchor.dx + 8;
    final fallbackLeft = anchor.dx - menuWidth - 8;
    final left = (preferredLeft + menuWidth <= panelRight)
        ? preferredLeft
        : fallbackLeft.clamp(panelLeft + 8, panelRight - menuWidth - 8);
    final top = anchor.dy.clamp(8.0, overlaySize.height - menuHeight - 8);
    final rect = RelativeRect.fromLTRB(
      left,
      top,
      overlaySize.width - left - 1,
      overlaySize.height - top - 1,
    );
    showMenu(
      context: context,
      position: rect,
      constraints:
          const BoxConstraints(minWidth: menuWidth, maxWidth: menuWidth),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.94),
      elevation: 14,
      items: [
        PopupMenuItem(
          onTap: () => notifier.togglePin(conv.id),
          child: Row(children: [
            Icon(conv.isPinned ? LucideIcons.pinOff : LucideIcons.pin,
                size: 18),
            const SizedBox(width: 12),
            Text(conv.isPinned ? 'Pindan olish' : 'Pinlash')
          ]),
        ),
        PopupMenuItem(
          onTap: () {
            if (conv.isMutedEffective) {
              notifier.unmute(conv.id);
            } else {
              Future.delayed(
                const Duration(milliseconds: 80),
                () => _showMuteDurationSheet(context, notifier, conv.id),
              );
            }
          },
          child: Row(children: [
            Icon(
                conv.isMutedEffective
                    ? LucideIcons.volume2
                    : LucideIcons.volumeX,
                size: 18),
            const SizedBox(width: 12),
            Text(conv.isMutedEffective ? 'Ovozni yoqish' : 'Mute')
          ]),
        ),
        PopupMenuItem(
          onTap: () => unread
              ? notifier.markAsRead(conv.id)
              : notifier.markAsUnread(conv.id),
          child: Row(children: [
            Icon(unread ? LucideIcons.checkCheck : LucideIcons.circle,
                size: 18),
            const SizedBox(width: 12),
            Text(unread
                ? 'O\'qilgan deb belgilash'
                : 'O\'qilmagan deb belgilash')
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
              final ok = await showDialog<bool>(
                  context: context,
                  builder: (d) => AlertDialog(
                        title: const Text("Suhbatni o'chirish?"),
                        content: const Text("Barcha xabarlar o'chiriladi."),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(d, false),
                              child: const Text('Bekor')),
                          TextButton(
                              onPressed: () => Navigator.pop(d, true),
                              child: const Text("O'chirish",
                                  style: TextStyle(color: Colors.red))),
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

  void _showMuteDurationSheet(
    BuildContext context,
    ConversationsNotifier notifier,
    String conversationId,
  ) {
    final c = AlsamosColors.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _muteTile(ctx, '1 soat',
              () => notifier.setMute(conversationId, const Duration(hours: 1))),
          _muteTile(ctx, '8 soat',
              () => notifier.setMute(conversationId, const Duration(hours: 8))),
          _muteTile(ctx, '2 kun',
              () => notifier.setMute(conversationId, const Duration(days: 2))),
          _muteTile(
              ctx, 'Doimiy', () => notifier.setMute(conversationId, null)),
        ]),
      ),
    );
  }

  Widget _muteTile(BuildContext context, String label, VoidCallback action) =>
      ListTile(
        leading: const Icon(LucideIcons.bellOff, size: 18),
        title: Text(label),
        onTap: () {
          Navigator.pop(context);
          action();
        },
      );
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
    final avatarUrl = conv.type == 'private'
        ? conv.otherParticipant?.avatarUrl
        : conv.avatarUrl;
    Widget avatar;
    if (!isSelf && !isGroup && !isChannel) {
      avatar = StoryAvatarRing(
        userId: conv.otherParticipant?.id,
        avatarUrl: avatarUrl,
        fallback: conv.title.isNotEmpty ? conv.title[0].toUpperCase() : '?',
        size: size,
        backgroundColor: theme.colorScheme.primary,
      );
    } else {
      if (avatarUrl != null && avatarUrl.isNotEmpty) {
        avatar = StoryAvatarRing(
          userId: null,
          avatarUrl: avatarUrl,
          fallback: conv.title.isNotEmpty ? conv.title[0].toUpperCase() : '?',
          size: size,
          backgroundColor: theme.colorScheme.primary,
        );
      } else {
        avatar = CircleAvatar(
          radius: size / 2,
          backgroundColor: theme.colorScheme.primary,
          child: Icon(
            isSelf
                ? LucideIcons.bookmark
                : isGroup
                    ? LucideIcons.users
                    : LucideIcons.megaphone,
            size: size * 0.42,
            color: Colors.white,
          ),
        );
      }
    }
    return Stack(clipBehavior: Clip.none, children: [
      SizedBox(
        width: size + 8,
        height: size + 8,
        child: Center(child: avatar),
      ),
      if (online)
        Positioned(
            right: 1,
            bottom: 1,
            child: Container(
              width: size * 0.28,
              height: size * 0.28,
              decoration: BoxDecoration(
                  color: const Color(0xFF22C55E),
                  shape: BoxShape.circle,
                  border: Border.all(color: c.background, width: 1.5)),
            )),
      if (isSelf)
        Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: size * 0.32,
              height: size * 0.32,
              decoration: BoxDecoration(
                  color: c.card,
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: const Color(0xFFF59E0B), width: 1.5)),
              child: Icon(LucideIcons.bookmark,
                  size: size * 0.16, color: const Color(0xFFF59E0B)),
            )),
    ]);
  }
}

// ─── Last Message ─────────────────────────────────────────────────────────────
class _LastMessage extends StatelessWidget {
  final Conversation conv;
  final AlsamosColors c;
  final bool unread;
  const _LastMessage(
      {required this.conv, required this.c, required this.unread});
  @override
  Widget build(BuildContext context) {
    final localDraft = chatDrafts[conv.id];
    final draft = localDraft?.trim().isNotEmpty == true ? localDraft : conv.draft;
    if (draft != null && draft.trim().isNotEmpty) {
      return Text.rich(
        TextSpan(children: [
          const TextSpan(
              text: 'Qoralama: ',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.w500)),
          TextSpan(
              text: draft,
              style:
                  TextStyle(color: unread ? c.foreground : c.mutedForeground)),
        ]),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13),
      );
    }

    final msg = conv.lastMessage;
    if (msg == null || msg.isEmpty) {
      return Text('Hali xabar yo\'q',
          style: TextStyle(fontSize: 12, color: c.mutedForeground),
          maxLines: 1,
          overflow: TextOverflow.ellipsis);
    }
    IconData? icon;
    Color iconColor = c.mutedForeground;
    String text = msg;
    if (msg.startsWith('{') && msg.contains('"type"')) {
      try {
        final d = jsonDecode(msg) as Map<String, dynamic>;
        final t = d['type'] as String?;
        if (t == 'video' || t == 'audio') {
          final isVideo = t == 'video';
          final status = d['status'] as String?;
          switch (status) {
            case 'missed':
              text = isVideo
                  ? "O'tkazib yuborilgan video"
                  : "O'tkazib yuborilgan qo'ng'iroq";
              icon = LucideIcons.phoneMissed;
              iconColor = Colors.red;
              break;
            case 'declined':
              text = isVideo ? "Rad etilgan video" : "Rad etilgan qo'ng'iroq";
              icon = LucideIcons.phoneOff;
              iconColor = Colors.orange;
              break;
            default:
              text = isVideo ? "Video qo'ng'iroq" : "Qo'ng'iroq";
              final dur = d['duration'];
              if (dur is num) {
                final m = dur ~/ 60;
                final s = (dur.toInt() % 60).toString().padLeft(2, '0');
                text += ' ($m:$s)';
              }
              icon = isVideo ? LucideIcons.video : LucideIcons.phone;
              iconColor = Colors.green;
          }
        }
      } catch (_) {}
    }
    return Row(children: [
      if (icon != null) ...[
        Icon(icon, size: 13, color: iconColor),
        const SizedBox(width: 3)
      ],
      Expanded(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12,
                  color: unread ? c.foreground : c.mutedForeground,
                  fontWeight: unread ? FontWeight.w500 : FontWeight.normal))),
    ]);
  }
}

// ─── Helper Widgets ───────────────────────────────────────────────────────────
class _HeaderBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool isPrimary;
  final AlsamosColors c;
  const _HeaderBtn(
      {required this.icon,
      required this.tooltip,
      required this.onTap,
      required this.c,
      this.isPrimary = false});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 44,
          height: 44,
          margin: const EdgeInsets.only(left: 4),
          decoration: BoxDecoration(
            color: isPrimary ? theme.colorScheme.primary : c.muted,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isPrimary
                  ? theme.colorScheme.primary.withValues(alpha: 0.48)
                  : c.border.withValues(alpha: 0.46),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isPrimary ? 0.09 : 0.04),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Icon(icon,
              size: 18,
              color: isPrimary ? theme.colorScheme.onPrimary : c.foreground),
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
    return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle),
          child: Icon(LucideIcons.messageCircle,
              size: 36, color: theme.colorScheme.primary)),
      const SizedBox(height: 16),
      Text('Suhbat tanlang',
          style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w600, color: c.foreground)),
      const SizedBox(height: 6),
      Text('Chap tomondagi ro\'yxatdan suhbat tanlang',
          style: TextStyle(fontSize: 13, color: c.mutedForeground)),
    ]));
  }
}

class _EmptyState extends StatelessWidget {
  final String tab;
  final AlsamosColors c;
  final VoidCallback onNewChat;
  const _EmptyState(
      {required this.tab, required this.c, required this.onNewChat});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    IconData icon;
    String title, sub;
    switch (tab) {
      case 'archived':
        icon = LucideIcons.archive;
        title = 'Arxiv bo\'sh';
        sub = 'Arxivlangan suhbatlar bu yerda ko\'rinadi';
        break;
      case 'requests':
        icon = LucideIcons.inbox;
        title = 'So\'rovlar yo\'q';
        sub = 'Yangi xabar so\'rovlari bu yerda ko\'rinadi';
        break;
      default:
        icon = LucideIcons.messageCircle;
        title = 'Suhbatlar yo\'q';
        sub = 'Birinchi suhbatni boshlang!';
    }
    return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle),
          child: Icon(icon, size: 28, color: theme.colorScheme.primary)),
      const SizedBox(height: 12),
      Text(title,
          style: TextStyle(
              fontWeight: FontWeight.w600, fontSize: 15, color: c.foreground)),
      const SizedBox(height: 4),
      Text(sub,
          style: TextStyle(fontSize: 12, color: c.mutedForeground),
          textAlign: TextAlign.center),
      if (tab == 'private') ...[
        const SizedBox(height: 16),
        ElevatedButton.icon(
            onPressed: onNewChat,
            icon: const Icon(LucideIcons.plus, size: 16),
            label: const Text('Yangi suhbat')),
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
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    if (q.length < 2) {
      setState(() => _results = []);
      return;
    }
    setState(() => _loading = true);
    try {
      final res = await Supabase.instance.client
          .from('profiles')
          .select('id, username, display_name, avatar_url, is_verified')
          .or('username.ilike.%$q%,display_name.ilike.%$q%')
          .limit(20);
      final userId = ref.read(authProvider).user?.id;
      setState(() {
        _results = (res as List)
            .where((p) => p['id'] != userId)
            .cast<Map<String, dynamic>>()
            .toList();
      });
    } catch (_) {
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _start(Map<String, dynamic> profile) async {
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) return;
    setState(() => _loading = true);
    try {
      final convId = await const MessagesRepository()
          .createPrivateConversation(userId, profile['id'] as String);
      if (convId != null && mounted) {
        await ref.read(conversationsProvider.notifier).load();
        final convs = ref.read(conversationsProvider).valueOrNull ?? [];
        final conv = convs.where((c) => c.id == convId).firstOrNull;
        if (conv != null && mounted) {
          widget.onCreated(conv);
        }
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final theme = Theme.of(context);
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      margin: const EdgeInsets.all(0),
      decoration: BoxDecoration(
          color: c.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(children: [
        Container(
            margin: const EdgeInsets.only(top: 10, bottom: 8),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
                color: c.border, borderRadius: BorderRadius.circular(2))),
        Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(children: [
              const Icon(LucideIcons.userPlus, size: 20),
              const SizedBox(width: 8),
              const Text('Yangi suhbat',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const Spacer(),
              IconButton(
                  icon: const Icon(LucideIcons.x),
                  onPressed: () => Navigator.pop(context)),
            ])),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              onChanged: _search,
              decoration: InputDecoration(
                hintText: 'Foydalanuvchi qidirish...',
                prefixIcon: const Icon(LucideIcons.search, size: 18),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: c.border)),
                filled: true,
                fillColor: c.muted,
              ),
            )),
        const SizedBox(height: 8),
        Expanded(
          child: _loading
              ? Center(
                  child: CircularProgressIndicator(
                      color: theme.colorScheme.primary))
              : _searchCtrl.text.isEmpty
                  ? ListView(
                      children: [
                        ListTile(
                          leading: const CircleAvatar(
                              backgroundColor: Colors.blue,
                              child: Icon(LucideIcons.users,
                                  color: Colors.white, size: 20)),
                          title: const Text('Yangi guruh',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: const Text(
                              'A\'zolar qo\'shing va muloqot boshlang',
                              style: TextStyle(fontSize: 12)),
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
                          leading: const CircleAvatar(
                              backgroundColor: Colors.orange,
                              child: Icon(LucideIcons.megaphone,
                                  color: Colors.white, size: 20)),
                          title: const Text('Yangi kanal',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: const Text('Ommaga xabar tarqating',
                              style: TextStyle(fontSize: 12)),
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
                      ? Center(
                          child: Text('Topilmadi',
                              style: TextStyle(color: c.mutedForeground)))
                      : ListView.builder(
                          itemCount: _results.length,
                          itemBuilder: (_, i) {
                            final p = _results[i];
                            final name = p['display_name'] as String? ??
                                p['username'] as String? ??
                                'Unknown';
                            final avatar = p['avatar_url'] as String?;
                            return ListTile(
                              leading: avatar != null && avatar.isNotEmpty
                                  ? CircleAvatar(
                                      backgroundImage: NetworkImage(avatar))
                                  : CircleAvatar(
                                      backgroundColor:
                                          theme.colorScheme.primary,
                                      child: Text(name[0].toUpperCase(),
                                          style: const TextStyle(
                                              color: Colors.white))),
                              title: Text(name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              subtitle: p['username'] != null
                                  ? Text('@${p['username']}',
                                      style: TextStyle(
                                          color: c.mutedForeground,
                                          fontSize: 12))
                                  : null,
                              trailing: p['is_verified'] == true
                                  ? const VerifiedBadge(size: 16)
                                  : null,
                              onTap: () => _start(p),
                            );
                          },
                        ),
        ),
      ]),
    );
  }
}
