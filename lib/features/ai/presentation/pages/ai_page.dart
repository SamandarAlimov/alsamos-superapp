import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/responsive/breakpoints.dart';
import '../providers/ai_provider.dart';
import '../widgets/ai_composer.dart';
import '../widgets/ai_empty_state.dart';
import '../widgets/ai_message_bubble.dart';
import '../widgets/ai_sidebar.dart';

class AIPage extends ConsumerStatefulWidget {
  const AIPage({super.key});
  @override
  ConsumerState<AIPage> createState() => _AIPageState();
}

class _AIPageState extends ConsumerState<AIPage> {
  final _scroll = ScrollController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  bool get _isMobile => !context.responsive.isDesktop;

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent + 200,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final state = ref.watch(aiProvider);
    final mobile = _isMobile;

    ref.listen<AiState>(aiProvider, (prev, next) {
      if ((prev?.messages.length ?? 0) < next.messages.length) {
        _scrollToBottom();
      }
    });

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: c.background,
      drawer: mobile
          ? Drawer(
              backgroundColor: c.background,
              shape: const RoundedRectangleBorder(),
              width: 300,
              child: const AiSidebar(isMobile: true),
            )
          : null,
      body: SafeArea(
        child: Row(
          children: [
            if (!mobile && !state.sidebarCollapsed) const AiSidebar(),
            if (!mobile && state.sidebarCollapsed) _collapsedRail(c),
            Expanded(
              child: Column(
                children: [
                  _topBar(c, state, mobile: mobile),
                  Expanded(
                    child: state.messages.isEmpty
                        ? const AiEmptyState()
                        : _messageList(c, state),
                  ),
                  AiComposer(onSend: _scrollToBottom),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _collapsedRail(AlsamosColors c) {
    return Container(
      width: 56,
      decoration: BoxDecoration(
        color: c.sidebarBackground,
        border: Border(right: BorderSide(color: c.sidebarBorder)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.alsamosOrange, AppColors.alsamosOrangeDark],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(LucideIcons.sparkles, color: Colors.white, size: 16),
          ),
          const SizedBox(height: 16),
          _railBtn(c, LucideIcons.plus, () {
            ref.read(aiProvider.notifier).startNew();
            HapticFeedback.lightImpact();
          }, tooltip: 'Yangi suhbat'),
          const SizedBox(height: 8),
          _railBtn(c, LucideIcons.search, () {},
              tooltip: 'Qidirish'),
          const Spacer(),
          _railBtn(c, LucideIcons.panelLeftOpen, () {
            ref.read(aiProvider.notifier).toggleSidebarCollapsed();
          }, tooltip: 'Sidebar ochish'),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _railBtn(AlsamosColors c, IconData icon, VoidCallback onTap,
      {String? tooltip}) {
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 16, color: c.sidebarForeground),
          ),
        ),
      ),
    );
  }

  Widget _topBar(AlsamosColors c, AiState state, {required bool mobile}) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: c.background,
        border: Border(bottom: BorderSide(color: c.border.withValues(alpha: 0.2))),
      ),
      child: Row(
        children: [
          if (mobile)
            IconButton(
              icon: const Icon(LucideIcons.panelLeft, size: 18),
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            ),
          if (!mobile && state.sidebarCollapsed)
            const SizedBox(width: 4),
          if (state.currentConversationId != null) ...[
            Icon(LucideIcons.messageSquare, size: 14, color: c.mutedForeground),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _currentTitle(state),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.foreground),
              ),
            ),
          ] else ...[
            const Icon(LucideIcons.sparkles, size: 14, color: AppColors.alsamosOrange),
            const SizedBox(width: 8),
            Text('Yangi suhbat',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.foreground)),
            const Spacer(),
          ],
          if (state.currentConversationId != null)
            IconButton(
              icon: const Icon(LucideIcons.squarePen, size: 16),
              onPressed: () {
                ref.read(aiProvider.notifier).startNew();
                HapticFeedback.lightImpact();
              },
              tooltip: 'Yangi suhbat',
            ),
        ],
      ),
    );
  }

  String _currentTitle(AiState state) {
    if (state.currentConversationId == null) return 'Yangi suhbat';
    final conv = state.conversations
        .where((c) => c.id == state.currentConversationId)
        .firstOrNull;
    return conv?.title ?? 'Suhbat';
  }

  Widget _messageList(AlsamosColors c, AiState state) {
    final itemCount =
        state.messages.length + (state.isBusy ? 1 : 0);
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      itemCount: itemCount,
      itemBuilder: (_, i) {
        if (i >= state.messages.length) {
          return AiLoadingBubble(isImageGen: state.isGeneratingImage);
        }
        return AiMessageBubble(
          message: state.messages[i],
          isLast: i == state.messages.length - 1,
        );
      },
    );
  }
}
