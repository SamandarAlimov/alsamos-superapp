import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../core/responsive/breakpoints.dart';
import '../../core/widgets/state_views.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/messages/presentation/widgets/call_invite_listener.dart';
import '../navigation/app_routes.dart';
import 'app_sidebar.dart';
import 'mobile_header.dart';
import 'mobile_menu_drawer.dart';
import '../navigation/bottom_navbar.dart';
import '../widgets/location_permission_dialog.dart';

class AppLayout extends ConsumerStatefulWidget {
  final Widget child;
  const AppLayout({super.key, required this.child});

  @override
  ConsumerState<AppLayout> createState() => _AppLayoutState();
}

class _AppLayoutState extends ConsumerState<AppLayout> {
  bool? _sidebarExpandedPref;
  bool _locationDialogShown = false;

  void _maybeShowLocationDialog(String? userId) {
    if (_locationDialogShown || userId == null) return;
    _locationDialogShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await LocationPermissionDialog.showIfNeeded(context, userId: userId);
    });
  }

  bool _hideMobileHeader(String location) {
    return location == AppRoutes.create ||
        location == AppRoutes.map ||
        location == AppRoutes.videos ||
        location == AppRoutes.messages ||
        location.startsWith('${AppRoutes.messages}/');
  }

  bool _hideBottomNav(String location) {
    return location == AppRoutes.create ||
        location.startsWith('${AppRoutes.messages}/');
  }

  void _toggleSidebarExpansion(bool currentExpanded) {
    setState(() => _sidebarExpandedPref = !currentExpanded);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final c = AlsamosColors.of(context);

    if (auth.isLoading) {
      return Scaffold(
        backgroundColor: c.background,
        body: const LoadingView(label: 'Yuklanmoqda...'),
      );
    }

    if (!auth.isAuthenticated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go(AppRoutes.auth);
      });
      return const SizedBox.shrink();
    }

    _maybeShowLocationDialog(auth.user?.id);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final mode = resolveNavMode(width);
        final location = GoRouterState.of(context).uri.path;

        switch (mode) {
          case NavMode.sidebarExpanded:
            return _buildDockedSidebar(c, location,
                expanded: true, width: width);
          case NavMode.sidebarRail:
            final userWantsExpanded = _sidebarExpandedPref ?? false;
            final canExpand = width >= 1156;
            final expanded = userWantsExpanded && canExpand;
            return _buildDockedSidebar(c, location,
                expanded: expanded, width: width);
          case NavMode.bottomNav:
            return _buildMobileLayout(c, location);
        }
      },
    );
  }

  Widget _buildDockedSidebar(AlsamosColors c, String location,
      {required bool expanded, required double width}) {
    final sidebarWidth = expanded ? 256.0 : 72.0;
    return Scaffold(
      backgroundColor: c.background,
      body: CallInviteListener(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Row(
              children: [
                SizedBox(width: sidebarWidth),
                Expanded(
                  child: SafeArea(
                    left: false,
                    bottom: false,
                    child: widget.child,
                  ),
                ),
              ],
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: sidebarWidth + 32,
              child: AppSidebar(
                expanded: expanded,
                onToggle: () => _toggleSidebarExpansion(expanded),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileLayout(AlsamosColors c, String location) {
    final hideHeader = _hideMobileHeader(location);
    final hideBottomNav = _hideBottomNav(location);
    return Scaffold(
      backgroundColor: c.background,
      appBar: hideHeader
          ? null
          : MobileHeader(onMenu: () => MobileMenuDrawer.open(context)),
      body: CallInviteListener(
        child: SafeArea(top: false, bottom: false, child: widget.child),
      ),
      bottomNavigationBar: hideBottomNav ? null : const BottomNavbar(),
    );
  }
}
