import 'package:flutter/material.dart';
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
import '../../features/marketplace/presentation/pages/my_orders_page.dart';
import '../../features/marketplace/presentation/pages/shipping_addresses_page.dart';
import '../../features/marketplace/presentation/pages/store_profile_page.dart';
import '../../features/ads/presentation/pages/ads_page.dart';
import '../../features/settings/presentation/pages/settings_page.dart';
import '../../features/settings/presentation/pages/profile_settings_page.dart';
import '../../features/settings/presentation/pages/wallet_settings_page.dart';
import '../../features/settings/presentation/pages/notifications_settings_page.dart';
import '../../features/settings/presentation/pages/privacy_settings_page.dart';
import '../../features/settings/presentation/pages/devices_settings_page.dart';
import '../../features/settings/presentation/pages/appearance_settings_page.dart';
import '../../features/settings/presentation/pages/security_settings_page.dart';
import '../../features/settings/presentation/pages/history_page.dart';
import '../../features/settings/presentation/pages/messages_settings_page.dart';
import '../../features/settings/presentation/pages/marketplace_settings_page.dart';
import '../../features/settings/presentation/pages/map_settings_page.dart';
import '../../features/settings/presentation/pages/video_settings_page.dart';
import '../../features/settings/presentation/pages/ai_settings_page.dart';
import '../../features/settings/presentation/pages/data_storage_settings_page.dart';
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
      
      // Admin route guard: check if user has admin role
      if (state.matchedLocation.startsWith('/admin')) {
        final isAdmin = auth.profile?.isAdmin ?? false;
        if (!isAdmin) {
          // Non-admin trying to access admin panel -> redirect to settings
          return AppRoutes.settings;
        }
      }
      
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
            path: '/edit-post/:id',
            pageBuilder: (c, s) {
              final postId = s.pathParameters['id']!;
              final editData = s.extra as Map<String, dynamic>?;
              return modalUpPage(
                c,
                s,
                CreatePage(editPostId: postId, editData: editData),
              );
            },
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
          // Marketplace sub-pages
          GoRoute(
            path: '/marketplace/my-orders',
            pageBuilder: (c, s) => fadeSlidePage(c, s, const MyOrdersPage()),
          ),
          GoRoute(
            path: '/marketplace/shipping-addresses',
            pageBuilder: (c, s) => fadeSlidePage(c, s, const ShippingAddressesPage()),
          ),
          GoRoute(
            path: '/marketplace/store-profile',
            pageBuilder: (c, s) => fadeSlidePage(c, s, const StoreProfilePage()),
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
          // Settings sub-pages (Telegram-style navigation)
          GoRoute(
            path: '/settings/profile',
            pageBuilder: (c, s) => fadeSlidePage(c, s, const ProfileSettingsPage()),
          ),
          GoRoute(
            path: '/settings/wallet',
            pageBuilder: (c, s) => fadeSlidePage(c, s, const WalletSettingsPage()),
          ),
          GoRoute(
            path: '/settings/devices',
            pageBuilder: (c, s) => fadeSlidePage(c, s, const DevicesSettingsPage()),
          ),
          GoRoute(
            path: '/settings/security',
            pageBuilder: (c, s) => fadeSlidePage(c, s, const SecuritySettingsPage()),
          ),
          GoRoute(
            path: '/settings/history',
            pageBuilder: (c, s) => fadeSlidePage(c, s, const HistoryPage()),
          ),
          GoRoute(
            path: '/settings/messages',
            pageBuilder: (c, s) => fadeSlidePage(c, s, const MessagesSettingsPage()),
          ),
          GoRoute(
            path: '/settings/marketplace',
            pageBuilder: (c, s) => fadeSlidePage(c, s, const MarketplaceSettingsPage()),
          ),
          GoRoute(
            path: '/settings/map',
            pageBuilder: (c, s) => fadeSlidePage(c, s, const MapSettingsPage()),
          ),
          GoRoute(
            path: '/settings/video',
            pageBuilder: (c, s) => fadeSlidePage(c, s, const VideoSettingsPage()),
          ),
          GoRoute(
            path: '/settings/ai',
            pageBuilder: (c, s) => fadeSlidePage(c, s, const AISettingsPage()),
          ),
          GoRoute(
            path: '/settings/notifications',
            pageBuilder: (c, s) => fadeSlidePage(c, s, const NotificationsSettingsPage()),
          ),
          GoRoute(
            path: '/settings/privacy',
            pageBuilder: (c, s) => fadeSlidePage(c, s, const PrivacySettingsPage()),
          ),
          GoRoute(
            path: '/settings/appearance',
            pageBuilder: (c, s) => fadeSlidePage(c, s, const AppearanceSettingsPage()),
          ),
          GoRoute(
            path: '/settings/data-storage',
            pageBuilder: (c, s) => fadeSlidePage(c, s, const DataStorageSettingsPage()),
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
