// Family Circle Panel - Life360-style family tracking
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../data/social_map_service.dart';

final _socialMapServiceProvider = Provider((ref) => SocialMapService());

final _familyCirclesProvider = FutureProvider<List<FamilyCircle>>((ref) async {
  final service = ref.read(_socialMapServiceProvider);
  return await service.getUserFamilyCircles();
});

/// Family Circle Panel
class FamilyCirclePanel extends ConsumerWidget {
  const FamilyCirclePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final circlesAsync = ref.watch(_familyCirclesProvider);

    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(LucideIcons.users, color: primary, size: 24),
                const SizedBox(width: 12),
                Text(
                  'Oila doiralari',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: c.foreground,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(LucideIcons.plus, size: 20),
                  onPressed: () => _showCreateCircleDialog(context, ref),
                ),
              ],
            ),
          ),

          Divider(height: 1, color: c.border),

          // Circles list
          Expanded(
            child: circlesAsync.when(
              data: (circles) => circles.isEmpty
                  ? _EmptyState(c: c)
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: circles.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final circle = circles[index];
                        return _CircleCard(
                          circle: circle,
                          onTap: () =>
                              _showCircleDetails(context, ref, circle),
                          c: c,
                          primary: primary,
                        );
                      },
                    ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, s) => Center(child: Text('Xatolik: $e')),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showCreateCircleDialog(
      BuildContext context, WidgetRef ref) async {
    final nameController = TextEditingController();
    final descController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yangi doira yaratish'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Nom *',
                hintText: 'Masalan: Oilam',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Tavsif (ixtiyoriy)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Bekor qilish'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yaratish'),
          ),
        ],
      ),
    );

    if (confirmed == true && nameController.text.isNotEmpty) {
      try {
        final service = ref.read(_socialMapServiceProvider);
        final currentUser = Supabase.instance.client.auth.currentUser!;

        final circle = FamilyCircle(
          id: '',
          name: nameController.text,
          description: descController.text.isEmpty
              ? null
              : descController.text,
          creatorId: currentUser.id,
          adminIds: [currentUser.id],
          memberIds: [currentUser.id],
          createdAt: DateTime.now(),
        );

        await service.createFamilyCircle(circle);
        ref.invalidate(_familyCirclesProvider);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Doira yaratildi')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Xatolik: $e')),
          );
        }
      }
    }
  }

  void _showCircleDetails(
      BuildContext context, WidgetRef ref, FamilyCircle circle) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _CircleDetailsSheet(circle: circle),
    );
  }
}

class _CircleCard extends StatelessWidget {
  final FamilyCircle circle;
  final VoidCallback onTap;
  final AlsamosColors c;
  final Color primary;

  const _CircleCard({
    required this.circle,
    required this.onTap,
    required this.c,
    required this.primary,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.border),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(LucideIcons.users, color: primary, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    circle.name,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: c.foreground,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${circle.memberIds.length} a\'zo',
                    style: TextStyle(
                      fontSize: 13,
                      color: c.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
            Icon(LucideIcons.chevronRight, color: c.mutedForeground, size: 20),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final AlsamosColors c;

  const _EmptyState({required this.c});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.users, size: 64, color: c.mutedForeground),
            const SizedBox(height: 16),
            Text(
              'Oila doirasi yo\'q',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: c.foreground,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Oila a\'zolaringiz bilan joylashuvni ulashish uchun doira yarating',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: c.mutedForeground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleDetailsSheet extends ConsumerStatefulWidget {
  final FamilyCircle circle;

  const _CircleDetailsSheet({required this.circle});

  @override
  ConsumerState<_CircleDetailsSheet> createState() =>
      _CircleDetailsSheetState();
}

class _CircleDetailsSheetState extends ConsumerState<_CircleDetailsSheet> {
  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: c.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(LucideIcons.users, color: primary, size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.circle.name,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: c.foreground,
                        ),
                      ),
                      Text(
                        '${widget.circle.memberIds.length} a\'zo',
                        style: TextStyle(
                          fontSize: 14,
                          color: c.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(LucideIcons.x),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          Divider(height: 1, color: c.border),

          // Content
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Description
                if (widget.circle.description != null) ...[
                  Text(
                    widget.circle.description!,
                    style: TextStyle(
                      fontSize: 14,
                      color: c.mutedForeground,
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // Members section
                Row(
                  children: [
                    Text(
                      'A\'zolar',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: c.foreground,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => _showInviteMemberDialog(),
                      icon: const Icon(LucideIcons.userPlus, size: 16),
                      label: const Text('Taklif qilish'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Members list
                ...widget.circle.memberIds.map((memberId) => _MemberCard(
                      memberId: memberId,
                      isAdmin: widget.circle.adminIds.contains(memberId),
                      isCreator: memberId == widget.circle.creatorId,
                      c: c,
                    )),

                const SizedBox(height: 24),

                // Settings
                _SettingsSection(
                  circle: widget.circle,
                  onUpdate: () => setState(() {}),
                  c: c,
                  primary: primary,
                ),

                const SizedBox(height: 24),

                // Delete button
                if (widget.circle.creatorId ==
                    Supabase.instance.client.auth.currentUser?.id)
                  OutlinedButton(
                    onPressed: () => _deleteCircle(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFEF4444),
                      side: const BorderSide(color: Color(0xFFEF4444)),
                    ),
                    child: const Text('Doirani o\'chirish'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showInviteMemberDialog() {
    // User search and invitation will be implemented in future phase
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Taklif funksiyasi tez orada qo\'shiladi')),
    );
  }

  Future<void> _deleteCircle() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Doirani o\'chirish'),
        content:
            const Text('Haqiqatan ham bu doirani o\'chirmoqchimisiz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Yo\'q'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
            ),
            child: const Text('Ha, o\'chirish'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ref
            .read(_socialMapServiceProvider)
            .deleteFamilyCircle(widget.circle.id);
        ref.invalidate(_familyCirclesProvider);

        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Doira o\'chirildi')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Xatolik: $e')),
          );
        }
      }
    }
  }
}

class _MemberCard extends StatelessWidget {
  final String memberId;
  final bool isAdmin;
  final bool isCreator;
  final AlsamosColors c;

  const _MemberCard({
    required this.memberId,
    required this.isAdmin,
    required this.isCreator,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: c.muted,
            child: Icon(LucideIcons.user, size: 20, color: c.mutedForeground),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'User $memberId',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: c.foreground,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (isCreator)
                  Text(
                    'Yaratuvchi',
                    style: TextStyle(
                      fontSize: 12,
                      color: c.mutedForeground,
                    ),
                  )
                else if (isAdmin)
                  Text(
                    'Admin',
                    style: TextStyle(
                      fontSize: 12,
                      color: c.mutedForeground,
                    ),
                  ),
              ],
            ),
          ),
          Icon(LucideIcons.mapPin, size: 16, color: c.mutedForeground),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final FamilyCircle circle;
  final VoidCallback onUpdate;
  final AlsamosColors c;
  final Color primary;

  const _SettingsSection({
    required this.circle,
    required this.onUpdate,
    required this.c,
    required this.primary,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sozlamalar',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: c.foreground,
          ),
        ),
        const SizedBox(height: 12),
        _SettingTile(
          title: 'Joylashuvni avtomatik ulashish',
          subtitle: 'Doira a\'zolari bilan real-time',
          value: circle.settings['auto_share_location'] as bool? ?? true,
          onChanged: (v) => onUpdate(),
          c: c,
        ),
        _SettingTile(
          title: 'Batareya holatini ko\'rsatish',
          subtitle: 'A\'zolarning batareya foizini',
          value: circle.settings['show_battery'] as bool? ?? true,
          onChanged: (v) => onUpdate(),
          c: c,
        ),
        _SettingTile(
          title: 'Haydash holatini ko\'rsatish',
          subtitle: 'Mashina haydayotgan a\'zolarni',
          value: circle.settings['show_driving_status'] as bool? ?? true,
          onChanged: (v) => onUpdate(),
          c: c,
        ),
      ],
    );
  }
}

class _SettingTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final AlsamosColors c;

  const _SettingTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: c.foreground,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: c.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
