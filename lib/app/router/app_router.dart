import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/pages/auth_page.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/home/presentation/pages/home_page.dart';
import '../../features/home/presentation/pages/post_details_page.dart';
import '../../features/messages/data/models/conversation_model.dart';
import '../../features/messages/presentation/pages/messages_page.dart';
import '../../features/messages/presentation/pages/chat_page.dart';
import '../../features/create/presentation/create_page.dart';
import '../../features/videos/presentation/pages/videos_page.dart';
import '../../features/profile/presentation/pages/profile_page.dart';
import '../../features/notifications/presentation/pages/notifications_page.dart';
import '../../features/search/presentation/pages/search_page.dart';
import '../../features/discover/presentation/discover_page.dart';
import '../../features/marketplace/presentation/pages/marketplace_page.dart';
import '../../features/ads/presentation/pages/ads_page.dart';
import '../../features/settings/presentation/pages/settings_page.dart';
import '../../features/ai/presentation/pages/ai_page.dart';
import '../../features/map/presentation/pages/map_page.dart';
import '../../features/activity/presentation/pages/activity_page.dart';
import '../../features/admin/presentation/pages/admin_page.dart';
import '../../features/payment/presentation/pages/payment_page.dart';
import '../../features/channels/presentation/pages/channels_page.dart';
import '../../features/miniapps/presentation/pages/mini_apps_page.dart';
import '../../features/orders/presentation/pages/orders_page.dart';
import '../../features/profile/presentation/pages/user_profile_page.dart';
import '../../features/stories/presentation/pages/story_archive_page.dart';
import '../../features/not_found/presentation/pages/not_found_page.dart';
import '../../shared/layout/app_layout.dart';
import '../../shared/navigation/app_routes.dart';
import 'page_transitions.dart';

/// v45: Every shell route uses `fadeSlidePage` (fade + 4% slide-from-right,
/// 280ms easeOutCubic). Modal-style routes like chat/create slide up.
///
/// Ported from web `App.tsx` <Routes>. AppLayout wraps the authenticated
/// shell; auth page lives outside the shell.
final goRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterAuthRefresh();
  ref.listen<AuthState>(authProvider, (_, __) => refresh.notify());
  ref.onDispose(refresh.dispose);

  return GoRouter(
    refreshListenable: refresh,
    errorBuilder: (context, state) => NotFoundPage(path: state.uri.toString()),
    initialLocation: AppRoutes.auth,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      if (auth.isLoading) return null;
      final loggingIn = state.matchedLocation == AppRoutes.auth;
      if (!auth.isAuthenticated) return loggingIn ? null : AppRoutes.auth;
      if (loggingIn) return AppRoutes.home;
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.auth,
        pageBuilder: (c, s) => fadeSlidePage(c, s, const AuthPage()),
      ),
      ShellRoute(
        builder: (context, state, child) => AppLayout(child: child),
        routes: [
          GoRoute(
            path: AppRoutes.home,
            pageBuilder: (c, s) => fadeSlidePage(c, s, const HomePage()),
          ),
          GoRoute(
            path: '/post/:id',
            pageBuilder: (c, s) => fadeSlidePage(
              c,
              s,
              PostDetailsPage(postId: s.pathParameters['id']!),
            ),
          ),
          GoRoute(
            path: AppRoutes.messages,
            pageBuilder: (c, s) => fadeSlidePage(c, s, const MessagesPage()),
          ),
          GoRoute(
            path: '/messages/:id',
            pageBuilder: (c, s) => modalUpPage(
              c,
              s,
              ChatPage(
                conversationId: s.pathParameters['id']!,
                conversation:
                    s.extra is Conversation ? s.extra as Conversation : null,
              ),
            ),
          ),
          GoRoute(
            path: AppRoutes.create,
            pageBuilder: (c, s) => modalUpPage(c, s, const CreatePage()),
          ),
          GoRoute(
            path: AppRoutes.videos,
            pageBuilder: (c, s) => fadeSlidePage(c, s, const VideosPage()),
          ),
          GoRoute(
            path: AppRoutes.profile,
            pageBuilder: (c, s) => fadeSlidePage(c, s, const ProfilePage()),
          ),
          GoRoute(
            path: '/profile/:id',
            pageBuilder: (c, s) => fadeSlidePage(
              c,
              s,
              ProfilePage(userId: s.pathParameters['id']),
            ),
          ),
          GoRoute(
            path: AppRoutes.notifications,
            pageBuilder: (c, s) =>
                fadeSlidePage(c, s, const NotificationsPage()),
          ),
          GoRoute(
            path: AppRoutes.search,
            pageBuilder: (c, s) => fadeSlidePage(c, s, const SearchPage()),
          ),
          GoRoute(
            path: AppRoutes.discover,
            pageBuilder: (c, s) => fadeSlidePage(c, s, const DiscoverPage()),
          ),
          GoRoute(
            path: AppRoutes.marketplace,
            pageBuilder: (c, s) => fadeSlidePage(c, s, const MarketplacePage()),
          ),
          GoRoute(
            path: AppRoutes.map,
            pageBuilder: (c, s) => fadeSlidePage(c, s, const MapPage()),
          ),
          GoRoute(
            path: AppRoutes.payment,
            pageBuilder: (c, s) => fadeSlidePage(c, s, const PaymentPage()),
          ),
          GoRoute(
            path: AppRoutes.ai,
            pageBuilder: (c, s) => fadeSlidePage(c, s, const AIPage()),
          ),
          GoRoute(
            path: AppRoutes.miniApps,
            pageBuilder: (c, s) => fadeSlidePage(c, s, const MiniAppsPage()),
          ),
          GoRoute(
            path: AppRoutes.admin,
            pageBuilder: (c, s) => fadeSlidePage(c, s, const AdminPage()),
          ),
          GoRoute(
            path: AppRoutes.ads,
            pageBuilder: (c, s) => fadeSlidePage(c, s, const AdsPage()),
          ),
          GoRoute(
            path: AppRoutes.settings,
            pageBuilder: (c, s) => fadeSlidePage(c, s, const SettingsPage()),
          ),
          GoRoute(
            path: '/settings/payment',
            pageBuilder: (c, s) => fadeSlidePage(c, s, const PaymentPage()),
          ),
          GoRoute(
            path: AppRoutes.activity,
            pageBuilder: (c, s) => fadeSlidePage(c, s, const ActivityPage()),
          ),
          GoRoute(
            path: AppRoutes.channels,
            pageBuilder: (c, s) => fadeSlidePage(c, s, const ChannelsPage()),
          ),
          GoRoute(
            path: AppRoutes.orders,
            pageBuilder: (c, s) => fadeSlidePage(c, s, const OrdersPage()),
          ),
          GoRoute(
            path: AppRoutes.storyArchive,
            pageBuilder: (c, s) =>
                fadeSlidePage(c, s, const StoryArchivePage()),
          ),
          GoRoute(
            path: '/user/:username',
            pageBuilder: (c, s) => fadeSlidePage(
              c,
              s,
              UserProfilePage(usernameOrId: s.pathParameters['username']!),
            ),
          ),
        ],
      ),
    ],
  );
});

class _RouterAuthRefresh extends ChangeNotifier {
  void notify() => notifyListeners();
}
