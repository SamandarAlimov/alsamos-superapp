import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../app/i18n/app_strings.dart';
import '../../../../core/responsive/breakpoints.dart';
import '../../../../core/widgets/state_views.dart';
import 'settings_list_page.dart';

/// Responsive settings shell - handles mobile, tablet, and desktop layouts
/// Mobile: Full-screen list with push navigation
/// Desktop: Master-detail (persistent left list + right detail pane)
/// NO TAB BAR on any platform!
class SettingsShellPage extends ConsumerWidget {
  /// Currently selected sub-page widget (for desktop master-detail)
  final Widget? detailPage;

  /// Currently selected item ID (for highlighting in desktop list)
  final String? selectedItemId;

  const SettingsShellPage({
    super.key,
    this.detailPage,
    this.selectedItemId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AlsamosColors.of(context);
    final responsive = context.responsive;
    final isDesktop = responsive.isDesktop;
    final listWidth = (MediaQuery.sizeOf(context).width * 0.32)
        .clamp(300.0, 360.0)
        .toDouble();

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          children: [
            // Header (shared across all breakpoints)
            _buildHeader(context, ref, c, isDesktop),
            // Body: responsive layout
            Expanded(
              child: isDesktop
                  ? _buildDesktopLayout(c, listWidth)
                  : _buildMobileLayout(),
            ),
          ],
        ),
      ),
    );
  }

  /// Header with back button and title
  Widget _buildHeader(
      BuildContext context, WidgetRef ref, AlsamosColors c, bool isDesktop) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      decoration: BoxDecoration(
        color: c.card,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () =>
                context.canPop() ? context.pop() : context.go('/home'),
            icon: const Icon(LucideIcons.arrowLeft, size: 22),
          ),
          Expanded(
            child: Text(
              AppStrings.of(ref).t('settings.title'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'SpaceGrotesk',
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Mobile/Tablet: Full-screen list (push navigation to sub-pages)
  Widget _buildMobileLayout() {
    return SettingsListPage(selectedItemId: selectedItemId);
  }

  /// Desktop: Master-detail layout (persistent left list + right detail pane)
  Widget _buildDesktopLayout(AlsamosColors c, double listWidth) {
    return Row(
      children: [
        // LEFT PANE: Settings list (persistent, Telegram Desktop style)
        SizedBox(
          width: listWidth,
          child: Container(
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: c.border)),
            ),
            child: SettingsListPage(selectedItemId: selectedItemId),
          ),
        ),
        // RIGHT PANE: Selected sub-page detail
        Expanded(
          child: Container(
            color: c.background,
            child: detailPage ??
                EmptyView(
                  icon: LucideIcons.settings,
                  title: 'Sozlamani tanlang',
                  message: 'Chap paneldan sozlamalar bo\'limini tanlang',
                ),
          ),
        ),
      ],
    );
  }
}
