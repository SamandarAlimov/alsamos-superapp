import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../domain/ai_capabilities.dart';
import '../providers/ai_agent_provider.dart';

/// Rejim (Suhbat / Agent) va model tanlash oynasi.
class AiModelSheet extends ConsumerWidget {
  const AiModelSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const AiModelSheet(),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AlsamosColors.of(context);
    final settings = ref.watch(aiAgentSettingsProvider);
    final notifier = ref.read(aiAgentSettingsProvider.notifier);

    return Container(
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: c.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Rejim',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, color: c.mutedForeground)),
            const SizedBox(height: 8),
            Row(
              children: kModeOptions.map((option) {
                final active = settings.mode == option.id;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => notifier.setMode(option.id),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                        decoration: BoxDecoration(
                          color: active
                              ? AppColors.alsamosOrange.withValues(alpha: 0.12)
                              : c.muted.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: active
                                ? AppColors.alsamosOrange.withValues(alpha: 0.5)
                                : c.border.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(option.label,
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: active ? AppColors.alsamosOrange : c.foreground)),
                            const SizedBox(height: 2),
                            Text(option.hint,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11, color: c.mutedForeground)),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            Text('Model',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, color: c.mutedForeground)),
            const SizedBox(height: 4),
            ...kModelOptions.map((option) {
              final active = settings.model == option.id;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                onTap: () {
                  notifier.setModel(option.id);
                  Navigator.of(context).maybePop();
                },
                leading: Icon(
                  active ? LucideIcons.checkCheck : LucideIcons.cpu,
                  size: 18,
                  color: active ? AppColors.alsamosOrange : c.mutedForeground,
                ),
                title: Text(option.label,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                        color: c.foreground)),
                subtitle: Text(option.description,
                    style: TextStyle(fontSize: 11.5, color: c.mutedForeground)),
              );
            }),
          ],
        ),
      ),
    );
  }
}
