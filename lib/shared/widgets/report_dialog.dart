import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/app_colors.dart';

/// v44: Enhanced ReportDialog — web parity.
/// 6 ta sabab kategoriya + qo'shimcha tafsilot textarea + 2 bosqichli (select → confirm)
class ReportTarget {
  final String type; // 'post' | 'user' | 'comment' | 'message'
  final String targetId;
  final String? targetLabel;
  const ReportTarget({
    required this.type,
    required this.targetId,
    this.targetLabel,
  });
}

class ReportReason {
  final String id;
  final String label;
  final IconData icon;
  final Color color;
  const ReportReason(this.id, this.label, this.icon, this.color);
}

class ReportDialog {
  static const List<ReportReason> reasons = [
    ReportReason('spam', 'Spam', LucideIcons.mail, Color(0xFF60A5FA)),
    ReportReason('harassment', 'Tahqirlash', LucideIcons.userX, Color(0xFFEF4444)),
    ReportReason('hate', 'Nafrat tili', LucideIcons.flag, Color(0xFFF59E0B)),
    ReportReason('violence', 'Zo\'ravonlik', LucideIcons.shieldAlert, Color(0xFFDC2626)),
    ReportReason('nudity', 'Nomaqbul kontent', LucideIcons.eyeOff, Color(0xFFA855F7)),
    ReportReason('scam', 'Aldash', LucideIcons.alertTriangle, Color(0xFFFB923C)),
    ReportReason('other', 'Boshqa', LucideIcons.moreHorizontal, Color(0xFF9CA3AF)),
  ];

  static Future<String?> show(
    BuildContext context, {
    required ReportTarget target,
    Future<bool> Function(String reasonId, String details)? onSubmit,
  }) async {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ReportSheet(target: target, onSubmit: onSubmit),
    );
  }
}

class _ReportSheet extends StatefulWidget {
  final ReportTarget target;
  final Future<bool> Function(String, String)? onSubmit;
  const _ReportSheet({required this.target, this.onSubmit});
  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  ReportReason? _selected;
  final _details = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selected == null || _submitting) return;
    setState(() => _submitting = true);
    final ok = await (widget.onSubmit?.call(_selected!.id, _details.text.trim()) ??
        Future.value(true));
    if (!mounted) return;
    Navigator.pop(context, ok ? _selected!.id : null);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Shikoyat qabul qilindi, rahmat.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final theme = Theme.of(context);
    final kb = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: kb),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(20),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.muted,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Shikoyat qilish',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                widget.target.targetLabel ?? 'Sababini tanlang',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: c.mutedForeground),
              ),
              const SizedBox(height: 12),
              ...ReportDialog.reasons.map((r) => _reasonTile(r, c, theme)),
              const SizedBox(height: 12),
              TextField(
                controller: _details,
                maxLines: 3,
                maxLength: 280,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Qo\'shimcha tafsilot (ixtiyoriy)',
                  filled: true,
                  fillColor: c.muted.withValues(alpha: 0.4),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _submitting
                          ? null
                          : () => Navigator.pop(context, null),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Bekor qilish'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed:
                          (_selected == null || _submitting) ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.alsamosOrange,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation(Colors.white),
                              ),
                            )
                          : const Text('Yuborish'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _reasonTile(ReportReason r, AlsamosColors c, ThemeData theme) {
    final selected = _selected?.id == r.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Semantics(
        selected: selected,
        button: true,
        label: r.label,
        child: InkWell(
          onTap: () => setState(() => _selected = r),
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: selected
                  ? r.color.withValues(alpha: 0.12)
                  : c.muted.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? r.color : Colors.transparent,
                width: 1.4,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: r.color.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(r.icon, size: 18, color: r.color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    r.label,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w500),
                  ),
                ),
                if (selected)
                  Icon(LucideIcons.checkCircle2, size: 18, color: r.color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
