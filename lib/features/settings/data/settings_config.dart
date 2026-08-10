import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

/// Settings item configuration for Telegram-style grouped list
class SettingsItemConfig {
  final String id;
  final IconData icon;
  final Color color;
  final String titleKey; // i18n key
  final String route;
  final String? Function()? trailingValue; // Dynamic badge/value

  const SettingsItemConfig({
    required this.id,
    required this.icon,
    required this.color,
    required this.titleKey,
    required this.route,
    this.trailingValue,
  });
}

/// Settings group configuration
class SettingsGroupConfig {
  final String? titleKey; // i18n key for group header, null = no header
  final List<SettingsItemConfig> items;

  const SettingsGroupConfig({
    this.titleKey,
    required this.items,
  });
}

/// Complete settings configuration - single source of truth
/// NEW: Module-aware IA reflecting Alsamos super-app structure
class SettingsConfig {
  // Predefined colors for icons
  // Group A - Account colors
  static const _profileColor = Color(0xFFEF4444); // Red
  static const _walletColor = Color(0xFF3B82F6); // Blue
  static const _devicesColor = Color(0xFFF97316); // Orange
  static const _securityColor = Color(0xFFF59E0B); // Amber
  static const _historyColor = Color(0xFF10B981); // Emerald
  
  // Group B - App Modules colors
  static const _messagesColor = Color(0xFF22C55E); // Green
  static const _marketplaceColor = Color(0xFFA855F7); // Purple
  static const _mapColor = Color(0xFF06B6D4); // Cyan
  static const _videoColor = Color(0xFFEF4444); // Red
  static const _aiColor = Color(0xFF8B5CF6); // Violet
  
  // Group C - Preferences colors
  static const _notifColor = Color(0xFFEF4444); // Red
  static const _privacyColor = Color(0xFF64748B); // Gray
  static const _appearanceColor = Color(0xFF06B6D4); // Cyan
  static const _dataColor = Color(0xFF22C55E); // Green
  
  // Group D - Admin colors
  static const _adminColor = Color(0xFF9333EA); // Purple

  static List<SettingsGroupConfig> getGroups({
    String? Function()? deviceCountProvider,
    bool isAdmin = false,
  }) {
    final groups = [
      // GROUP A: Account (user identity, wallet, security)
      SettingsGroupConfig(
        titleKey: 'settings.group.account',
        items: [
          SettingsItemConfig(
            id: 'profile',
            icon: LucideIcons.user,
            color: _profileColor,
            titleKey: 'settings.items.profile',
            route: '/settings/profile',
          ),
          SettingsItemConfig(
            id: 'wallet',
            icon: LucideIcons.wallet,
            color: _walletColor,
            titleKey: 'settings.items.wallet',
            route: '/settings/wallet',
          ),
          SettingsItemConfig(
            id: 'devices',
            icon: LucideIcons.smartphone,
            color: _devicesColor,
            titleKey: 'settings.items.devices',
            route: '/settings/devices',
            trailingValue: deviceCountProvider,
          ),
          SettingsItemConfig(
            id: 'security',
            icon: LucideIcons.key,
            color: _securityColor,
            titleKey: 'settings.items.security',
            route: '/settings/security',
          ),
          SettingsItemConfig(
            id: 'history',
            icon: LucideIcons.clock,
            color: _historyColor,
            titleKey: 'settings.items.history',
            route: '/settings/history',
          ),
        ],
      ),
      
      // GROUP B: App Modules (per-module settings for super-app features)
      SettingsGroupConfig(
        titleKey: 'settings.group.modules',
        items: [
          SettingsItemConfig(
            id: 'messages',
            icon: LucideIcons.messageSquare,
            color: _messagesColor,
            titleKey: 'settings.items.messages',
            route: '/settings/messages',
          ),
          SettingsItemConfig(
            id: 'marketplace',
            icon: LucideIcons.shoppingBag,
            color: _marketplaceColor,
            titleKey: 'settings.items.marketplace',
            route: '/settings/marketplace',
          ),
          SettingsItemConfig(
            id: 'map',
            icon: LucideIcons.map,
            color: _mapColor,
            titleKey: 'settings.items.map',
            route: '/settings/map',
          ),
          SettingsItemConfig(
            id: 'video',
            icon: LucideIcons.video,
            color: _videoColor,
            titleKey: 'settings.items.video',
            route: '/settings/video',
          ),
          SettingsItemConfig(
            id: 'ai',
            icon: LucideIcons.bot,
            color: _aiColor,
            titleKey: 'settings.items.ai',
            route: '/settings/ai',
          ),
        ],
      ),
      
      // GROUP C: Preferences (app-wide settings)
      SettingsGroupConfig(
        titleKey: 'settings.group.preferences',
        items: [
          SettingsItemConfig(
            id: 'notifications',
            icon: LucideIcons.bell,
            color: _notifColor,
            titleKey: 'settings.items.notifications',
            route: '/settings/notifications',
          ),
          SettingsItemConfig(
            id: 'privacy',
            icon: LucideIcons.shield,
            color: _privacyColor,
            titleKey: 'settings.items.privacy',
            route: '/settings/privacy',
          ),
          SettingsItemConfig(
            id: 'appearance',
            icon: LucideIcons.palette,
            color: _appearanceColor,
            titleKey: 'settings.items.appearance',
            route: '/settings/appearance',
          ),
          SettingsItemConfig(
            id: 'data',
            icon: LucideIcons.database,
            color: _dataColor,
            titleKey: 'settings.items.dataStorage',
            route: '/settings/data-storage',
          ),
        ],
      ),
    ];
    
    // GROUP D: Admin (only visible to admins)
    if (isAdmin) {
      groups.add(
        SettingsGroupConfig(
          titleKey: 'settings.group.admin',
          items: [
            SettingsItemConfig(
              id: 'admin_panel',
              icon: LucideIcons.shieldCheck,
              color: _adminColor,
              titleKey: 'settings.items.adminPanel',
              route: '/admin',
            ),
          ],
        ),
      );
    }
    
    return groups;
  }
}
