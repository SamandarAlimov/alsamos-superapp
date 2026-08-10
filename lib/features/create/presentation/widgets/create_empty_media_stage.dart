import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import 'create_media_chip.dart';

class CreateEmptyMediaStage extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color primary;
  final VoidCallback? onImage;
  final VoidCallback? onVideo;
  final VoidCallback? onFile;

  const CreateEmptyMediaStage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.primary,
    this.onImage,
    this.onVideo,
    this.onFile,
  });

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 420),
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F172A), Color(0xFF020617)],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.14),
                shape: BoxShape.circle,
                border: Border.all(color: primary.withValues(alpha: 0.35)),
              ),
              child: Icon(LucideIcons.uploadCloud, color: primary, size: 36),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                if (onImage != null)
                  CreateMediaChip(
                    icon: LucideIcons.image,
                    label: 'Rasm',
                    color: const Color(0xFF22C55E),
                    onTap: onImage!,
                  ),
                if (onVideo != null)
                  CreateMediaChip(
                    icon: LucideIcons.video,
                    label: 'Video',
                    color: const Color(0xFF3B82F6),
                    onTap: onVideo!,
                  ),
                if (onFile != null)
                  CreateMediaChip(
                    icon: LucideIcons.file,
                    label: 'Fayl',
                    color: const Color(0xFF8B5CF6),
                    onTap: onFile!,
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Drag/drop keyin ulanadi. Hozir gallery va file picker tayyor.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.mutedForeground,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
