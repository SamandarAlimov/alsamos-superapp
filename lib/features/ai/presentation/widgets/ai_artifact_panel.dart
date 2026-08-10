import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';

class AiArtifactPanel extends StatelessWidget {
  final String title;
  final String content;
  final String? language;
  final VoidCallback onClose;

  const AiArtifactPanel({
    super.key,
    required this.title,
    required this.content,
    this.language,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);

    return Container(
      width: 420,
      decoration: BoxDecoration(
        color: c.background,
        border: Border(left: BorderSide(color: c.border)),
      ),
      child: Column(
        children: [
          _header(c),
          Expanded(child: _body(c)),
          _footer(c),
        ],
      ),
    );
  }

  Widget _header(AlsamosColors c) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border.withValues(alpha: 0.5))),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.fileCode, size: 16, color: AppColors.alsamosOrange),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          if (language != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: c.muted,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(language!,
                  style: TextStyle(fontSize: 10, color: c.mutedForeground)),
            ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(LucideIcons.x, size: 16),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }

  Widget _body(AlsamosColors c) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SelectableText(
        content,
        style: TextStyle(
          fontSize: 12,
          fontFamily: 'monospace',
          height: 1.6,
          color: c.foreground,
        ),
      ),
    );
  }

  Widget _footer(AlsamosColors c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.border.withValues(alpha: 0.5))),
      ),
      child: Row(
        children: [
          _footerBtn(c, LucideIcons.copy, 'Nusxa', () {
            Clipboard.setData(ClipboardData(text: content));
            HapticFeedback.selectionClick();
          }),
          const SizedBox(width: 8),
          _footerBtn(c, LucideIcons.download, 'Yuklab olish', () {}),
          const Spacer(),
          _footerBtn(c, LucideIcons.share2, 'Ulashish', () {}),
        ],
      ),
    );
  }

  Widget _footerBtn(AlsamosColors c, IconData icon, String label, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: c.mutedForeground),
              const SizedBox(width: 5),
              Text(label, style: TextStyle(fontSize: 11, color: c.mutedForeground)),
            ],
          ),
        ),
      ),
    );
  }
}
