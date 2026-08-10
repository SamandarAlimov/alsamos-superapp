import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import 'create_media_chip.dart';

class CreateToolTray extends StatelessWidget {
  const CreateToolTray({
    super.key,
    required this.colors,
    required this.onPickImage,
    required this.onPickVideo,
    required this.onPickFile,
    required this.onCreatePoll,
    required this.onPickMusic,
  });

  final AlsamosColors colors;
  final VoidCallback onPickImage;
  final VoidCallback onPickVideo;
  final VoidCallback onPickFile;
  final VoidCallback onCreatePoll;
  final VoidCallback onPickMusic;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.border),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          CreateMediaChip(
            icon: LucideIcons.image,
            label: 'Rasm',
            color: const Color(0xFF22C55E),
            onTap: onPickImage,
          ),
          CreateMediaChip(
            icon: LucideIcons.video,
            label: 'Video',
            color: const Color(0xFF3B82F6),
            onTap: onPickVideo,
          ),
          CreateMediaChip(
            icon: LucideIcons.fileArchive,
            label: 'Fayl',
            color: const Color(0xFF8B5CF6),
            onTap: onPickFile,
          ),
          CreateMediaChip(
            icon: LucideIcons.barChart3,
            label: 'So\'rovnoma',
            color: const Color(0xFFEC4899),
            onTap: onCreatePoll,
          ),
          CreateMediaChip(
            icon: LucideIcons.music,
            label: 'Musiqa',
            color: const Color(0xFFEAB308),
            onTap: onPickMusic,
          ),
        ],
      ),
    );
  }
}
