import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../domain/ai_message.dart';
import '../providers/ai_agent_provider.dart';

/// Bitta kompyuter vazifasi uchun tasdiq kartasi.
class AiComputerApprovalCard extends ConsumerWidget {
  const AiComputerApprovalCard({super.key, required this.task});

  final ComputerTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AlsamosColors.of(context);
    final actions = ref.read(computerTaskActionsProvider);
    final payload = task.payload;
    final details = payload == null || payload.isEmpty
        ? null
        : const JsonEncoder.withIndent('  ').convert(payload);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFDC2626).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDC2626).withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.monitor, size: 15, color: Color(0xFFDC2626)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Kompyuter vazifasi: ${task.action}',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: c.foreground),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Tasdiqlasangiz, Alsamos Bridge uni kompyuteringizda bajaradi.',
            style: TextStyle(fontSize: 11.5, color: c.mutedForeground),
          ),
          if (details != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: c.muted.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                details,
                maxLines: 8,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, height: 1.4, color: c.mutedForeground),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => actions.reject(task.id, reason: 'Foydalanuvchi rad etdi'),
                  icon: const Icon(LucideIcons.x, size: 14),
                  label: const Text('Rad etish', style: TextStyle(fontSize: 12.5)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => actions.approve(task.id),
                  icon: const Icon(LucideIcons.check, size: 14),
                  label: const Text('Tasdiqlash', style: TextStyle(fontSize: 12.5)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Tasdiq kutayotgan barcha vazifalar ro'yxati (kompozer tepasida ko'rinadi).
class AiComputerTasksBanner extends ConsumerWidget {
  const AiComputerTasksBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(pendingComputerTasksProvider);
    return tasks.maybeWhen(
      data: (list) => list.isEmpty
          ? const SizedBox.shrink()
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: list
                  .take(3)
                  .map((task) => AiComputerApprovalCard(task: task))
                  .toList(),
            ),
      orElse: () => const SizedBox.shrink(),
    );
  }
}
