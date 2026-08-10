import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../app/i18n/app_strings.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/settings_config.dart';
import '../providers/admin_role_provider.dart';

/// Telegram-style settings list page - used on ALL breakpoints (no tab bar!)
/// This is the primary settings navigation on mobile, tablet, and desktop.
class SettingsListPage extends ConsumerStatefulWidget {
  /// Optional selected item ID for desktop master-detail highlighting
  final String? selectedItemId;

  const SettingsListPage({super.key, this.selectedItemId});

  @override
  ConsumerState<SettingsListPage> createState() => _SettingsListPageState();
}

class _SettingsListPageState extends ConsumerState<SettingsListPage> {
  int _deviceCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDeviceCount());
  }

  Future<void> _loadDeviceCount() async {
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) return;
    try {
      final result = await Supabase.instance.client
          .from('user_sessions')
          .select('id')
          .eq('user_id', userId)
          .count(CountOption.exact);
      if (!mounted) return;
      setState(() => _deviceCount = (result as dynamic).count ?? 0);
    } catch (_) {
      // Table may not exist
    }
  }

  String? _getDeviceCountString() {
    return _deviceCount > 0 ? _deviceCount.toString() : null;
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    
    // Watch admin role state
    final isAdmin = ref.watch(adminRoleStateProvider);

    // Get groups with device count provider and admin status
    final groups = SettingsConfig.getGroups(
      deviceCountProvider: _getDeviceCountString,
      isAdmin: isAdmin,
    );

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: groups.length,
      itemBuilder: (context, groupIndex) {
        final group = groups[groupIndex];
        return Padding(
          padding: EdgeInsets.only(bottom: groupIndex < groups.length - 1 ? 16 : 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Group header (if titleKey is provided)
              if (group.titleKey != null)
                Padding(
                  padding: const EdgeInsets.only(left: 20, bottom: 8),
                  child: Text(
                    AppStrings.of(ref).t(group.titleKey!),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: c.mutedForeground,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              _SettingsGroupCard(
                c: c,
                primary: primary,
                group: group,
                selectedItemId: widget.selectedItemId,
                onItemTap: (item) => context.push(item.route),
                ref: ref,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Settings group card with Telegram-style rows
class _SettingsGroupCard extends StatelessWidget {
  final AlsamosColors c;
  final Color primary;
  final SettingsGroupConfig group;
  final String? selectedItemId;
  final Function(SettingsItemConfig) onItemTap;
  final WidgetRef ref;

  const _SettingsGroupCard({
    required this.c,
    required this.primary,
    required this.group,
    required this.selectedItemId,
    required this.onItemTap,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
        boxShadow: [
          BoxShadow(
            color: c.foreground.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: group.items.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          final isSelected = selectedItemId == item.id;
          final isLast = index == group.items.length - 1;

          return Column(
            children: [
              _SettingsListTile(
                c: c,
                primary: primary,
                item: item,
                isSelected: isSelected,
                onTap: () => onItemTap(item),
                ref: ref,
              ),
              if (!isLast)
                Padding(
                  padding: const EdgeInsets.only(left: 64),
                  child: Divider(height: 1, thickness: 1, color: c.border),
                ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

/// Individual settings list tile (Telegram-style)
class _SettingsListTile extends StatelessWidget {
  final AlsamosColors c;
  final Color primary;
  final SettingsItemConfig item;
  final bool isSelected;
  final VoidCallback onTap;
  final WidgetRef ref;

  const _SettingsListTile({
    required this.c,
    required this.primary,
    required this.item,
    required this.isSelected,
    required this.onTap,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    final trailingValue = item.trailingValue?.call();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: isSelected
              ? BoxDecoration(
                  color: primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                )
              : null,
          child: Row(
            children: [
              // Rounded colored icon
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: item.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(item.icon, size: 18, color: item.color),
              ),
              const SizedBox(width: 14),
              // Title
              Expanded(
                child: Text(
                  AppStrings.of(ref).t(item.titleKey),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: c.foreground,
                  ),
                ),
              ),
              // Trailing value (badge)
              if (trailingValue != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: c.mutedForeground.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    trailingValue,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: c.mutedForeground,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              // Chevron
              Icon(
                LucideIcons.chevronRight,
                size: 20,
                color: c.mutedForeground.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
