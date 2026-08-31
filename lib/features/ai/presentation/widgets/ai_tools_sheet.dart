import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../domain/ai_capabilities.dart';
import '../providers/ai_agent_provider.dart';

/// Vosita guruhlarini yoqish / o'chirish oynasi.
class AiToolsSheet extends ConsumerWidget {
  const AiToolsSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const AiToolsSheet(),
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
        child: SingleChildScrollView(
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
              const SizedBox(height: 14),
              Row(
                children: [
                  const Icon(LucideIcons.wrench, size: 16, color: AppColors.alsamosOrange),
                  const SizedBox(width: 8),
                  Text('Vositalar',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700, color: c.foreground)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                "Agent shu guruhlardagi vositalardan foydalanadi.",
                style: TextStyle(fontSize: 12, color: c.mutedForeground),
              ),
              const SizedBox(height: 8),
              ...kToolGroups.map((group) {
                final enabled = settings.isEnabled(group.id);
                return SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: enabled,
                  activeColor: AppColors.alsamosOrange,
                  onChanged: (value) => notifier.toggleGroup(group.id, value),
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(group.label,
                            style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: c.foreground)),
                      ),
                      if (group.sensitive) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDC2626).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('tasdiq',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFFDC2626))),
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text(group.description,
                      style: TextStyle(fontSize: 11.5, color: c.mutedForeground)),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}
