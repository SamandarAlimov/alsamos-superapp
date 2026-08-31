import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../domain/ai_message.dart';

/// Agent qaysi vositalarni ishlatganini ko'rsatuvchi jadval.
class AiToolTimeline extends StatefulWidget {
  const AiToolTimeline({super.key, required this.events});

  final List<AIToolEvent> events;

  @override
  State<AiToolTimeline> createState() => _AiToolTimelineState();
}

class _AiToolTimelineState extends State<AiToolTimeline> {
  final Set<String> _expanded = <String>{};

  @override
  Widget build(BuildContext context) {
    if (widget.events.isEmpty) return const SizedBox.shrink();
    final c = AlsamosColors.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: c.muted.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: widget.events.map((e) => _row(c, e)).toList(),
      ),
    );
  }

  Widget _row(AlsamosColors c, AIToolEvent event) {
    final open = _expanded.contains(event.id);
    final sources = ((event.data?['sources'] as List?) ?? const <dynamic>[])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
    final hasDetails = (event.summary?.isNotEmpty ?? false) || sources.isNotEmpty;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: hasDetails
          ? () => setState(() {
                if (open) {
                  _expanded.remove(event.id);
                } else {
                  _expanded.add(event.id);
                }
              })
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _statusIcon(event.status),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    event.label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: c.foreground,
                    ),
                  ),
                ),
                if (event.duration != null)
                  Text(
                    '${(event.duration!.inMilliseconds / 1000).toStringAsFixed(1)}s',
                    style: TextStyle(fontSize: 11, color: c.mutedForeground),
                  ),
                if (hasDetails) ...[
                  const SizedBox(width: 6),
                  Icon(
                    open ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                    size: 14,
                    color: c.mutedForeground,
                  ),
                ],
              ],
            ),
            if (open) ...[
              const SizedBox(height: 8),
              if (event.summary?.isNotEmpty ?? false)
                Text(
                  event.summary!,
                  style: TextStyle(fontSize: 12, height: 1.45, color: c.mutedForeground),
                ),
              if (sources.isNotEmpty) ...[
                const SizedBox(height: 8),
                ...sources.take(5).map(
                      (s) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(LucideIcons.link, size: 12, color: c.mutedForeground),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                (s['title'] ?? s['url'] ?? '').toString(),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11.5, color: c.mutedForeground),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusIcon(AIToolStatus status) {
    switch (status) {
      case AIToolStatus.running:
        return const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case AIToolStatus.done:
        return const Icon(LucideIcons.check, size: 14, color: Color(0xFF16A34A));
      case AIToolStatus.error:
        return const Icon(LucideIcons.x, size: 14, color: Color(0xFFDC2626));
    }
  }
}
