import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_theme.dart';

// Activity stats provider (placeholder - uses Supabase)
final activityStatsProvider = FutureProvider((ref) async {
  return {
    'posts': 24, 'likes': 183, 'followers': 1240, 'following': 320,
    'impressions': 8410, 'reach': 5200, 'profile_visits': 1430,
    'link_clicks': 87,
  };
});

/// Pixel-perfect port of web pages/ActivityPage.tsx + components/activity/ActivityDashboard.tsx
class ActivityPage extends ConsumerWidget {
  const ActivityPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final statsAsync = ref.watch(activityStatsProvider);

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
              decoration: BoxDecoration(
                  color: c.card, border: Border(bottom: BorderSide(color: c.border))),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
                    icon: const Icon(LucideIcons.arrowLeft, size: 22),
                  ),
                  const Expanded(
                    child: Text('Sizning faolligingiz',
                        style: TextStyle(
                            fontFamily: 'SpaceGrotesk',
                            fontWeight: FontWeight.bold, fontSize: 18)),
                  ),
                  Icon(LucideIcons.barChart3, color: primary, size: 22),
                ],
              ),
            ),
            Expanded(
              child: statsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('$e')),
                data: (stats) => ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Period chip
                    Row(
                      children: [
                        const Text('So\'nggi 28 kun',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(LucideIcons.calendar, size: 14, color: primary),
                              const SizedBox(width: 5),
                              Text('28 kun', style: TextStyle(color: primary, fontSize: 12, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Stats grid (2x2)
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 1.5,
                      children: [
                        _StatCard(icon: LucideIcons.users, label: 'Taassurotlar',
                            value: _fmt(stats['impressions']!), color: const Color(0xFF6366F1), c: c),
                        _StatCard(icon: LucideIcons.eye, label: 'Qamrov',
                            value: _fmt(stats['reach']!), color: const Color(0xFF22C55E), c: c),
                        _StatCard(icon: LucideIcons.userCheck, label: 'Profil tashrifi',
                            value: _fmt(stats['profile_visits']!), color: const Color(0xFFF59E0B), c: c),
                        _StatCard(icon: LucideIcons.link, label: 'Link bosishlari',
                            value: _fmt(stats['link_clicks']!), color: const Color(0xFFEF4444), c: c),
                      ],
                    ),
                    const SizedBox(height: 24),
                    // Audience growth
                    Text('Auditoriya o\'sishi',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 12),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 1.6,
                      children: [
                        _StatCard(icon: LucideIcons.userPlus, label: 'Yangi obunachilar',
                            value: '+${_fmt(stats['followers']!)}', color: primary, c: c),
                        _StatCard(icon: LucideIcons.heart, label: "Yoqtirishlar",
                            value: _fmt(stats['likes']!), color: const Color(0xFFEF4444), c: c),
                        _StatCard(icon: LucideIcons.fileText, label: 'Postlar',
                            value: _fmt(stats['posts']!), color: const Color(0xFF8B5CF6), c: c),
                        _StatCard(icon: LucideIcons.trendingUp, label: 'Obunalar',
                            value: _fmt(stats['following']!), color: const Color(0xFF06B6D4), c: c),
                      ],
                    ),
                    const SizedBox(height: 24),
                    // Engagement bar (mock)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: c.card,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: c.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Engagement Rate',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          const SizedBox(height: 4),
                          Text('Haftalik o\'rtacha', style: TextStyle(color: c.mutedForeground, fontSize: 12)),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Text('4.8%',
                                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: primary)),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF22C55E).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(LucideIcons.trendingUp, size: 13, color: Color(0xFF22C55E)),
                                    const SizedBox(width: 3),
                                    const Text('+2.1%', style: TextStyle(color: Color(0xFF22C55E), fontSize: 12, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              value: 0.48,
                              minHeight: 8,
                              backgroundColor: c.muted,
                              valueColor: AlwaysStoppedAnimation(primary),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(num n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final AlsamosColors c;
  const _StatCard({required this.icon, required this.label, required this.value, required this.color, required this.c});
  @override
  Widget build(BuildContext context) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 18),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                Text(label, style: TextStyle(color: c.mutedForeground, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ],
        ),
      );
}
