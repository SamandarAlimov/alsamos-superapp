import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/ai_models.dart';
import '../providers/ai_provider.dart';

/// Pixel-perfect port of web `src/pages/AIPage.tsx`.
/// - Sidebar drawer (history, search, new chat, footer profile)
/// - Top bar: sidebar toggle + Chat/Imagine mode pill + Gemini badge
/// - Empty state hero + suggestion cards (chat) or prompt chips (imagine)
/// - Streaming bot replies with copy + regenerate actions
/// - Generated image bubbles
/// - Gradient composer with attach/mic/send affordances
class AIPage extends ConsumerStatefulWidget {
  const AIPage({super.key});
  @override
  ConsumerState<AIPage> createState() => _AIPageState();
}

class _AIPageState extends ConsumerState<AIPage> {
  final _input = TextEditingController();
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  String? _copiedId;
  String _query = '';

  static const _chatSuggestions = <_Suggestion>[
    _Suggestion(LucideIcons.lightbulb, 'Fikr generatsiya', "Yangi g'oyalar yarating",
        "Menga ijtimoiy tarmoq uchun yangi kontent g'oyalarini taklif qil"),
    _Suggestion(LucideIcons.code2, 'Kod yozish', 'Dasturlashda yordam',
        'React komponent yaratishda yordam ber'),
    _Suggestion(LucideIcons.fileText, 'Matn tahriri', 'Professional matnlar',
        'Professional bio yozishda yordam ber'),
    _Suggestion(LucideIcons.globe, 'Tarjima', "Ko'p tilli tarjima",
        'Quyidagi matnni ingliz tiliga tarjima qil'),
  ];

  static const _imagineSuggestions = <(String, String)>[
    ('🎨', 'Fantastik manzara'),
    ('👤', 'Professional portret'),
    ('🏛️', 'Zamonaviy arxitektura'),
    ('🌌', 'Kosmik landshaft'),
  ];

  static const _postSuggestions = <_Suggestion>[
    _Suggestion(LucideIcons.lightbulb, "Shunga o'xshash yoz", '',
        "Shu postga o'xshash kontent yozib ber, lekin yangicha uslubda"),
    _Suggestion(LucideIcons.brain, 'Tahlil qil', '',
        'Bu post haqida chuqur tahlil ber: nima yaxshi, nima yaxshilash mumkin'),
    _Suggestion(LucideIcons.fileText, 'Javob yoz', '',
        'Bu postga professional va qiziqarli javob yozib ber'),
    _Suggestion(LucideIcons.globe, 'Tarjima qil', '',
        'Bu post matnini ingliz tiliga professional tarjima qil'),
  ];

  @override
  void dispose() {
    _input.dispose();
    _search.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _isMobile => MediaQuery.of(context).size.width < 768;

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    final mode = ref.read(aiProvider).mode;
    _input.clear();
    setState(() {});
    HapticFeedback.lightImpact();
    if (mode == 'imagine') {
      ref.read(aiProvider.notifier).generateImage(text);
    } else {
      ref.read(aiProvider.notifier).sendMessage(text);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent + 300,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _copy(String text, String id) async {
    await Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.selectionClick();
    setState(() => _copiedId = id);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copiedId = null);
    });
  }

  String _formatTime(DateTime d) {
    final diff = DateTime.now().difference(d).inDays;
    if (diff == 0) return 'Bugun';
    if (diff == 1) return 'Kecha';
    if (diff < 7) return '$diff kun oldin';
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final state = ref.watch(aiProvider);
    final mobile = _isMobile;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: c.background,
      drawer: mobile ? _sidebar(c, state, mobile: true) : null,
      body: SafeArea(
        child: Row(
          children: [
            if (!mobile) _sidebar(c, state, mobile: false),
            Expanded(
              child: Column(
                children: [
                  _topBar(c, state, mobile: mobile),
                  Expanded(
                    child: state.messages.isEmpty
                        ? _emptyState(c, state)
                        : _messageList(c, state),
                  ),
                  _composer(c, state),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Sidebar ───────────────────────────────────────────────────────────────
  Widget _sidebar(AlsamosColors c, AiState state, {required bool mobile}) {
    final profile = ref.watch(authProvider).profile;
    final filtered = state.conversations
        .where((conv) => conv.title.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    final width = mobile ? 300.0 : 300.0;

    final body = Container(
      width: width,
      decoration: BoxDecoration(
        color: c.card.withValues(alpha: 0.8),
        border: Border(right: BorderSide(color: c.border.withValues(alpha: 0.5))),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [AppColors.alsamosOrange, AppColors.alsamosOrangeDark],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.alsamosOrange.withValues(alpha: 0.2),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(LucideIcons.sparkles, color: Colors.white, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Alsamos AI',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          Text('Premium Assistant',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: c.mutedForeground,
                                  height: 1.1)),
                        ],
                      ),
                    ),
                    if (mobile)
                      IconButton(
                        icon: const Icon(LucideIcons.chevronLeft, size: 18),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                // New chat gradient button
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      ref.read(aiProvider.notifier).startNew();
                      if (mobile) Navigator.of(context).pop();
                      HapticFeedback.lightImpact();
                    },
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.alsamosOrange, AppColors.alsamosOrangeDark],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.alsamosOrange.withValues(alpha: 0.2),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(LucideIcons.plus, size: 16, color: Colors.white),
                          SizedBox(width: 8),
                          Text('Yangi suhbat',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // Search
                SizedBox(
                  height: 36,
                  child: TextField(
                    controller: _search,
                    onChanged: (v) => setState(() => _query = v),
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'Qidirish...',
                      hintStyle:
                          TextStyle(fontSize: 12, color: c.mutedForeground.withValues(alpha: 0.7)),
                      prefixIcon: Padding(
                        padding: const EdgeInsets.only(left: 12, right: 8),
                        child: Icon(LucideIcons.search, size: 14, color: c.mutedForeground),
                      ),
                      prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      filled: true,
                      fillColor: c.muted.withValues(alpha: 0.5),
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: c.border.withValues(alpha: 0.5)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: c.border.withValues(alpha: 0.5)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: c.border.withValues(alpha: 0.5)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Conversation list
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(LucideIcons.history,
                            size: 32, color: c.mutedForeground.withValues(alpha: 0.4)),
                        const SizedBox(height: 12),
                        Text(
                          _query.isNotEmpty ? 'Natija topilmadi' : "Hali suhbatlar yo'q",
                          style: TextStyle(fontSize: 12, color: c.mutedForeground),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) =>
                        _convTile(c, filtered[i], state, mobile: mobile),
                  ),
          ),
          // Footer
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.border.withValues(alpha: 0.3))),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: c.muted,
                  backgroundImage: (profile?.avatarUrl?.isNotEmpty == true)
                      ? CachedNetworkImageProvider(profile!.avatarUrl!)
                      : null,
                  child: (profile?.avatarUrl?.isNotEmpty != true)
                      ? Icon(LucideIcons.user, size: 14, color: c.mutedForeground)
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile?.displayName ?? profile?.username ?? 'Foydalanuvchi',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      Text('Premium',
                          style: TextStyle(fontSize: 10, color: c.mutedForeground)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return mobile
        ? Drawer(
            backgroundColor: c.background,
            shape: const RoundedRectangleBorder(),
            child: body,
          )
        : body;
  }

  Widget _convTile(AlsamosColors c, AiConversation conv, AiState state,
      {required bool mobile}) {
    final selected = conv.id == state.currentConversationId;
    final primary = Theme.of(context).colorScheme.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          ref.read(aiProvider.notifier).openConversation(conv);
          if (mobile) Navigator.of(context).pop();
        },
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? c.muted.withValues(alpha: 0.8) : null,
            borderRadius: BorderRadius.circular(12),
            boxShadow: selected
                ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4)]
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  conv.type == 'imagine' ? LucideIcons.wand2 : LucideIcons.messageSquare,
                  size: 14,
                  color: primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(conv.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                    Text(_formatTime(conv.updatedAt),
                        style: TextStyle(fontSize: 10, color: c.mutedForeground)),
                  ],
                ),
              ),
              SizedBox(
                width: 28,
                height: 28,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 14,
                  icon: const Icon(LucideIcons.moreHorizontal),
                  onPressed: () => _showConvMenu(c, conv),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showConvMenu(AlsamosColors c, AiConversation conv) {
    showModalBottomSheet(
      context: context,
      backgroundColor: c.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: c.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(LucideIcons.trash2, size: 18, color: c.destructive),
              title: Text("O'chirish",
                  style: TextStyle(color: c.destructive, fontSize: 14)),
              onTap: () {
                Navigator.pop(context);
                ref.read(aiProvider.notifier).deleteConversation(conv.id);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ─── Top Bar ───────────────────────────────────────────────────────────────
  Widget _topBar(AlsamosColors c, AiState state, {required bool mobile}) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: c.background.withValues(alpha: 0.8),
        border: Border(bottom: BorderSide(color: c.border.withValues(alpha: 0.3))),
      ),
      child: Row(
        children: [
          if (mobile)
            IconButton(
              icon: const Icon(LucideIcons.panelLeft, size: 18),
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            ),
          // Chat / Imagine mode pill
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: c.muted.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _modeBtn(c, 'Chat', LucideIcons.brain, state.mode == 'chat',
                  () => ref.read(aiProvider.notifier).setMode('chat'), mobile),
              _modeBtn(c, 'Imagine', LucideIcons.image, state.mode == 'imagine',
                  () => ref.read(aiProvider.notifier).setMode('imagine'), mobile),
            ]),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: c.muted.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(LucideIcons.zap, size: 12, color: AppColors.alsamosOrange),
              if (!mobile) ...[
                const SizedBox(width: 6),
                Text('Gemini 3 Flash',
                    style: TextStyle(fontSize: 10, color: c.mutedForeground)),
              ],
            ]),
          ),
        ],
      ),
    );
  }

  Widget _modeBtn(
      AlsamosColors c, String label, IconData icon, bool active, VoidCallback onTap, bool mobile) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: active ? c.background : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: active
                ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4)]
                : null,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14, color: active ? c.foreground : c.mutedForeground),
            if (!mobile) ...[
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: active ? c.foreground : c.mutedForeground,
                  )),
            ],
          ]),
        ),
      ),
    );
  }

  // ─── Empty State ───────────────────────────────────────────────────────────
  Widget _emptyState(AlsamosColors c, AiState state) {
    final imagine = state.mode == 'imagine';
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Center(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppColors.alsamosOrange,
                            AppColors.alsamosOrangeDark,
                            Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.alsamosOrange.withValues(alpha: 0.3),
                            blurRadius: 32,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Icon(
                        imagine ? LucideIcons.wand2 : LucideIcons.sparkles,
                        size: 44,
                        color: Colors.white,
                      ),
                    ),
                    Positioned(
                      bottom: -4,
                      right: -4,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: const Color(0xFF22C55E),
                          shape: BoxShape.circle,
                          border: Border.all(color: c.background, width: 2),
                        ),
                        child: const Icon(LucideIcons.check, size: 12, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                imagine ? 'Imagine Studio' : 'Alsamos AI',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                imagine
                    ? "Xayolingizni rasmga aylantiring. Tavsif yozing va AI sizning g'oyangizni vizualizatsiya qilsin."
                    : "Professional AI yordamchi. Savol bering, matn yozing, tahlil qiling yoki har qanday vazifada yordam so'rang.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: c.mutedForeground, height: 1.5),
              ),
              const SizedBox(height: 28),
              if (state.forwardedPost != null && !imagine)
                _forwardedPostCard(c, state.forwardedPost!),
              if (state.forwardedPost == null && !imagine) _chatSuggestionGrid(c),
              if (imagine) _imagineChips(c),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _forwardedPostCard(AlsamosColors c, ForwardedPost p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: c.card.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.alsamosOrange.withValues(alpha: 0.3)),
            boxShadow: [
              BoxShadow(
                color: AppColors.alsamosOrange.withValues(alpha: 0.05),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.alsamosOrange.withValues(alpha: 0.1),
                  border: Border(
                    bottom: BorderSide(
                        color: AppColors.alsamosOrange.withValues(alpha: 0.2)),
                  ),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    const Icon(LucideIcons.sparkles,
                        size: 14, color: AppColors.alsamosOrange),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('Post yuborildi',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.alsamosOrange)),
                    ),
                    InkWell(
                      onTap: () =>
                          ref.read(aiProvider.notifier).clearForwardedPost(),
                      child: Icon(LucideIcons.x,
                          size: 14, color: c.mutedForeground),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (p.mediaUrl != null && p.mediaUrl!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: CachedNetworkImage(
                            imageUrl: p.mediaUrl!,
                            height: 180,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    Text('@${p.authorName ?? 'Foydalanuvchi'}',
                        style: TextStyle(fontSize: 12, color: c.mutedForeground)),
                    if ((p.content ?? '').isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(p.content!,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, height: 1.4)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: MediaQuery.of(context).size.width > 540 ? 2 : 1,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 6,
          children: _postSuggestions
              .map((s) => _postChip(c, s))
              .toList(),
        ),
      ],
    );
  }

  Widget _postChip(AlsamosColors c, _Suggestion s) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          _input.text = s.prompt;
          _input.selection =
              TextSelection.fromPosition(TextPosition(offset: _input.text.length));
          _focus.requestFocus();
          setState(() {});
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: c.card.withValues(alpha: 0.5),
            border: Border.all(color: c.border.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(s.icon, size: 16, color: AppColors.alsamosOrange),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  s.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chatSuggestionGrid(AlsamosColors c) {
    final wide = MediaQuery.of(context).size.width > 540;
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: wide ? 2 : 1,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: wide ? 3.6 : 5.4,
      children: _chatSuggestions.map((s) => _suggestionCard(c, s)).toList(),
    );
  }

  Widget _suggestionCard(AlsamosColors c, _Suggestion s) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          _input.text = s.prompt;
          _input.selection =
              TextSelection.fromPosition(TextPosition(offset: _input.text.length));
          _focus.requestFocus();
          setState(() {});
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.card.withValues(alpha: 0.5),
            border: Border.all(color: c.border.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.alsamosOrange.withValues(alpha: 0.1),
                      AppColors.alsamosOrangeDark.withValues(alpha: 0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(s.icon, size: 18, color: AppColors.alsamosOrange),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(s.title,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(s.desc,
                        style:
                            TextStyle(fontSize: 11, color: c.mutedForeground, height: 1.3)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _imagineChips(AlsamosColors c) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: _imagineSuggestions
          .map(
            (p) => Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  _input.text = p.$2;
                  _input.selection = TextSelection.fromPosition(
                      TextPosition(offset: _input.text.length));
                  _focus.requestFocus();
                  setState(() {});
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: c.card.withValues(alpha: 0.5),
                    border: Border.all(color: c.border.withValues(alpha: 0.5)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('${p.$1} ${p.$2}',
                      style:
                          const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  // ─── Message list ──────────────────────────────────────────────────────────
  Widget _messageList(AlsamosColors c, AiState state) {
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      itemCount: state.messages.length + ((state.isLoading || state.isGeneratingImage) ? 1 : 0),
      itemBuilder: (_, i) {
        if (i >= state.messages.length) {
          return _loadingBubble(c, generating: state.isGeneratingImage);
        }
        final msg = state.messages[i];
        return msg.isUser ? _userBubble(c, msg) : _assistantBubble(c, msg, state);
      },
    );
  }

  Widget _userBubble(AlsamosColors c, AiMessage msg) {
    final primary = Theme.of(context).colorScheme.primary;
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
        child: Container(
          margin: const EdgeInsets.only(bottom: 16, left: 60),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: primary,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(6),
            ),
          ),
          child: Text(
            msg.content,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.white,
              height: 1.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _assistantBubble(AlsamosColors c, AiMessage msg, AiState state) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            margin: const EdgeInsets.only(top: 2, right: 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.alsamosOrange, AppColors.alsamosOrangeDark],
              ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: AppColors.alsamosOrange.withValues(alpha: 0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(
              state.mode == 'imagine' ? LucideIcons.wand2 : LucideIcons.bot,
              size: 16,
              color: Colors.white,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (msg.content.isNotEmpty)
                  SelectableText(
                    msg.content,
                    style: const TextStyle(fontSize: 14, height: 1.65),
                  ),
                if (msg.imageUrl != null && msg.imageUrl!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: CachedNetworkImage(
                      imageUrl: msg.imageUrl!,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        height: 240,
                        color: c.muted,
                        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Row(
                  children: [
                    _msgAction(c, _copiedId == msg.id ? LucideIcons.check : LucideIcons.copy,
                        () => _copy(msg.content, msg.id),
                        active: _copiedId == msg.id),
                    _msgAction(c, LucideIcons.rotateCcw,
                        () => ref.read(aiProvider.notifier).regenerate()),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _msgAction(AlsamosColors c, IconData icon, VoidCallback onTap,
      {bool active = false}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(6),
          child: Icon(icon,
              size: 14,
              color: active ? const Color(0xFF22C55E) : c.mutedForeground),
        ),
      ),
    );
  }

  Widget _loadingBubble(AlsamosColors c, {required bool generating}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            margin: const EdgeInsets.only(top: 2, right: 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.alsamosOrange, AppColors.alsamosOrangeDark],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(LucideIcons.bot, size: 16, color: Colors.white),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: c.card.withValues(alpha: 0.5),
              border: Border.all(color: c.border.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _BouncingDots(),
                const SizedBox(width: 10),
                Text(
                  generating ? 'Rasm yaratilmoqda...' : "O'ylayapman...",
                  style: TextStyle(fontSize: 12, color: c.mutedForeground),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Composer ──────────────────────────────────────────────────────────────
  Widget _composer(AlsamosColors c, AiState state) {
    final imagine = state.mode == 'imagine';
    final busy = state.isLoading || state.isGeneratingImage;
    final hasText = _input.text.trim().isNotEmpty;
    final mobile = _isMobile;
    final borderColor = imagine
        ? const Color(0xFFEC4899).withValues(alpha: 0.2)
        : c.border.withValues(alpha: 0.5);
    final focusBorderColor = imagine
        ? const Color(0xFFEC4899).withValues(alpha: 0.5)
        : AppColors.alsamosOrange.withValues(alpha: 0.5);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: c.background.withValues(alpha: 0.8),
        border: Border(top: BorderSide(color: c.border.withValues(alpha: 0.2))),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                decoration: BoxDecoration(
                  color: c.card.withValues(alpha: 0.8),
                  border: Border.all(
                      color: _focus.hasFocus ? focusBorderColor : borderColor),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48, maxHeight: 180),
                        child: TextField(
                          controller: _input,
                          focusNode: _focus,
                          minLines: 1,
                          maxLines: 6,
                          enabled: !busy,
                          textInputAction: TextInputAction.send,
                          onChanged: (_) => setState(() {}),
                          onSubmitted: (_) => _send(),
                          style: const TextStyle(fontSize: 14, height: 1.4),
                          decoration: InputDecoration(
                            hintText: imagine
                                ? 'Qanday rasm yaratmoqchisiz...'
                                : 'Xabar yozing...',
                            hintStyle: TextStyle(
                                fontSize: 14,
                                color: c.mutedForeground.withValues(alpha: 0.6)),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.fromLTRB(16, 14, 0, 14),
                          ),
                        ),
                      ),
                    ),
                    if (!mobile) ...[
                      _toolBtn(c, LucideIcons.paperclip, null),
                      _toolBtn(c, LucideIcons.mic, null),
                    ],
                    Padding(
                      padding: const EdgeInsets.fromLTRB(2, 0, 8, 8),
                      child: _sendButton(c, hasText: hasText, busy: busy, imagine: imagine),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Alsamos AI xato qilishi mumkin. Muhim ma'lumotlarni tekshiring.",
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 10, color: c.mutedForeground.withValues(alpha: 0.7)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toolBtn(AlsamosColors c, IconData icon, VoidCallback? onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
        width: 32,
        height: 32,
        child: IconButton(
          padding: EdgeInsets.zero,
          iconSize: 16,
          icon: Icon(icon, color: c.mutedForeground),
          onPressed: onTap,
        ),
      ),
    );
  }

  Widget _sendButton(AlsamosColors c,
      {required bool hasText, required bool busy, required bool imagine}) {
    final enabled = hasText && !busy;
    final gradient = imagine
        ? const LinearGradient(
            colors: [Color(0xFFEC4899), Color(0xFFF97316)],
          )
        : const LinearGradient(
            colors: [AppColors.alsamosOrange, AppColors.alsamosOrangeDark],
          );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled ? _send : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            gradient: enabled ? gradient : null,
            color: enabled ? null : c.muted,
            borderRadius: BorderRadius.circular(12),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: AppColors.alsamosOrange.withValues(alpha: 0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: busy
              ? const Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  ),
                )
              : Icon(
                  LucideIcons.arrowUp,
                  size: 16,
                  color: enabled ? Colors.white : c.mutedForeground,
                ),
        ),
      ),
    );
  }
}

class _Suggestion {
  final IconData icon;
  final String title;
  final String desc;
  final String prompt;
  const _Suggestion(this.icon, this.title, this.desc, this.prompt);
}

class _BouncingDots extends StatefulWidget {
  const _BouncingDots();
  @override
  State<_BouncingDots> createState() => _BouncingDotsState();
}

class _BouncingDotsState extends State<_BouncingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 8,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(3, (i) {
              final t = ((_ctrl.value + i * 0.2) % 1.0);
              final scale = 0.6 + 0.4 * (1 - (2 * t - 1).abs());
              return Transform.scale(
                scale: scale,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.alsamosOrange,
                    shape: BoxShape.circle,
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
