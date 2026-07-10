import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/messages/presentation/widgets/call_invite_listener.dart';
import '../navigation/app_routes.dart';
import 'app_sidebar.dart';
import 'mobile_header.dart';
import 'mobile_menu_drawer.dart';
import '../navigation/bottom_navbar.dart';
import '../widgets/location_permission_dialog.dart';

/// Ported 1:1 from web `AppLayout.tsx`.
/// - Auth-gated (redirect to / if not authenticated; spinner while loading).
/// - Hide MobileHeader on /messages, /map, /videos.
/// - Desktop: collapsible sidebar. Mobile: header + bottom navbar.
/// - Sidebar auto-collapses below 1100px.
class AppLayout extends ConsumerStatefulWidget {
  final Widget child;
  const AppLayout({super.key, required this.child});

  @override
  ConsumerState<AppLayout> createState() => _AppLayoutState();
}

class _AppLayoutState extends ConsumerState<AppLayout> {
  bool _sidebarExpanded = true;
  bool _locationDialogShown = false; // v43: bir martalik ko'rsatish

  void _maybeShowLocationDialog(String? userId) {
    // v43: auth tayyor bo'lgandan keyin bir marta ko'rsatamiz
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

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final c = AlsamosColors.of(context);

    if (auth.isLoading) {
      return Scaffold(
        backgroundColor: c.background,
        body: Center(
          child: CircularProgressIndicator(
              color: Theme.of(context).colorScheme.primary),
        ),
      );
    }

    if (!auth.isAuthenticated) {
      // Defer navigation to after build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go(AppRoutes.auth);
      });
      return const SizedBox.shrink();
    }

    // v43: Auth tayyor — LocationPermissionDialog (bir martalik) ulanadi
    _maybeShowLocationDialog(auth.user?.id);

    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 768; // md breakpoint
    final autoCollapse = width < 1100;
    final expanded = _sidebarExpanded && !autoCollapse;
    final sidebarWidth = expanded ? 256.0 : 72.0;
    final location = GoRouterState.of(context).uri.path;
    final hideHeader = _hideMobileHeader(location);

    if (isDesktop) {
      return Scaffold(
        backgroundColor: c.background,
        body: CallInviteListener(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                left: sidebarWidth,
                child: widget.child,
              ),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: sidebarWidth + 32,
                child: AppSidebar(
                  expanded: expanded,
                  onToggle: () =>
                      setState(() => _sidebarExpanded = !_sidebarExpanded),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Mobile
    final hideBottomNav = _hideBottomNav(location);
    return Scaffold(
      backgroundColor: c.background,
      extendBody: true, // Allow body to extend behind bottom navbar (webdagi fixed overlay kabi)
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
