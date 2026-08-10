import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/stories/story_avatar_ring.dart';
import 'create_media_chip.dart';
import 'create_media_preview_stage.dart';
import 'create_publish_banners.dart';
import 'create_story_text_controls.dart';
import 'music_picker.dart';

class CreateStoryTab extends StatelessWidget {
  const CreateStoryTab({
    super.key,
    required this.colors,
    required this.primary,
    required this.contentController,
    required this.composerField,
    required this.backgroundColor,
    required this.textSize,
    required this.font,
    required this.textAlign,
    required this.textPosition,
    required this.mentions,
    required this.onEditMedia,
    required this.onRemoveMedia,
    required this.onTextPositionChanged,
    required this.onTextAlignChanged,
    required this.onFontChanged,
    required this.onTextSizeChanged,
    required this.onResetTextPosition,
    required this.onBackgroundColorChanged,
    required this.onOpenCamera,
    required this.onRecordVideo,
    required this.onPickPhoto,
    required this.onPickVideo,
    required this.onPickMusic,
    required this.onUseTextMode,
    required this.onAddMention,
    required this.onRemoveMention,
    required this.onClearMusic,
    this.selectedMedia,
    this.musicTrack,
    this.profileUserId,
    this.profileAvatarUrl,
    this.profileFallback = 'U',
    this.profileDisplayName = 'User',
  });

  static const palette = [
    Color(0xFFF97316),
    Color(0xFFEF4444),
    Color(0xFFEC4899),
    Color(0xFF8B5CF6),
    Color(0xFF3B82F6),
    Color(0xFF06B6D4),
    Color(0xFF22C55E),
    Color(0xFFEAB308),
    Color(0xFF111827),
  ];

  static const fonts = [
    ('bold', 'Bold', FontWeight.w900),
    ('classic', 'Classic', FontWeight.w600),
    ('light', 'Light', FontWeight.w300),
    ('serif', 'Serif', FontWeight.w700),
  ];

  final AlsamosColors colors;
  final Color primary;
  final XFile? selectedMedia;
  final TextEditingController contentController;
  final Widget composerField;
  final Color backgroundColor;
  final double textSize;
  final String font;
  final TextAlign textAlign;
  final Offset textPosition;
  final List<String> mentions;
  final MusicTrack? musicTrack;
  final String? profileUserId;
  final String? profileAvatarUrl;
  final String profileFallback;
  final String profileDisplayName;
  final VoidCallback onEditMedia;
  final VoidCallback onRemoveMedia;
  final ValueChanged<Offset> onTextPositionChanged;
  final ValueChanged<TextAlign> onTextAlignChanged;
  final ValueChanged<String> onFontChanged;
  final ValueChanged<double> onTextSizeChanged;
  final VoidCallback onResetTextPosition;
  final ValueChanged<Color> onBackgroundColorChanged;
  final VoidCallback onOpenCamera;
  final VoidCallback onRecordVideo;
  final VoidCallback onPickPhoto;
  final VoidCallback onPickVideo;
  final VoidCallback onPickMusic;
  final VoidCallback onUseTextMode;
  final VoidCallback onAddMention;
  final ValueChanged<String> onRemoveMention;
  final VoidCallback onClearMusic;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 110),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 820;
              final storyWeight = fonts
                  .firstWhere(
                    (candidate) => candidate.$1 == font,
                    orElse: () => fonts.first,
                  )
                  .$3;
              final preview = _buildPreview(storyWeight);
              final controls = _buildControls();

              return wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: preview),
                        const SizedBox(width: 32),
                        Expanded(child: controls),
                      ],
                    )
                  : Column(
                      children: [
                        preview,
                        const SizedBox(height: 24),
                        controls,
                      ],
                    );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPreview(FontWeight storyWeight) {
    final selected = selectedMedia;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: AspectRatio(
          aspectRatio: 9 / 16,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: selected == null ? backgroundColor : Colors.black,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 30,
                    offset: const Offset(0, 18),
                  ),
                ],
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (selected != null)
                    CreateLocalMediaFrame(
                      file: selected,
                      aspectRatio: 9 / 16,
                      forceReel: true,
                      onEdit: onEditMedia,
                      onRemove: onRemoveMedia,
                    ),
                  if (selected == null)
                    Container(
                      padding: const EdgeInsets.all(28),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            backgroundColor,
                            Color.lerp(backgroundColor, Colors.black, 0.28)!,
                          ],
                        ),
                      ),
                    ),
                  Positioned.fill(child: _buildMovableText(storyWeight)),
                  if (musicTrack != null)
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 18,
                      child: _StoryPreviewPill(
                        icon: LucideIcons.music,
                        label:
                            '${musicTrack!.title}${musicTrack!.artist == null ? '' : ' - ${musicTrack!.artist}'}',
                      ),
                    ),
                  if (mentions.isNotEmpty)
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: musicTrack == null ? 18 : 58,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 76),
                        child: SingleChildScrollView(
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final mention in mentions)
                                _StoryPreviewPill(
                                  icon: LucideIcons.atSign,
                                  label: mention,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    left: 14,
                    right: 14,
                    top: 14,
                    child: Row(
                      children: [
                        StoryAvatarRing(
                          userId: profileUserId,
                          avatarUrl: profileAvatarUrl,
                          fallback: profileFallback,
                          size: 34,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            profileDisplayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const Icon(
                          LucideIcons.moreHorizontal,
                          color: Colors.white,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMovableText(FontWeight storyWeight) {
    return LayoutBuilder(
      builder: (context, storyBox) {
        final textWidth = math.min(storyBox.maxWidth - 40, 292.0);
        final left = (textPosition.dx * storyBox.maxWidth - textWidth / 2)
            .clamp(20.0, storyBox.maxWidth - textWidth - 20);
        final top = (textPosition.dy * storyBox.maxHeight - 64)
            .clamp(72.0, storyBox.maxHeight - 180);
        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              width: textWidth,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (details) {
                  onTextPositionChanged(
                    Offset(
                      (textPosition.dx + details.delta.dx / storyBox.maxWidth)
                          .clamp(0.08, 0.92),
                      (textPosition.dy + details.delta.dy / storyBox.maxHeight)
                          .clamp(0.16, 0.84),
                    ),
                  );
                },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: contentController,
                    builder: (_, value, __) {
                      final text = value.text.trim();
                      return Text(
                        text.isEmpty
                            ? 'Story matni shu yerda ko\'rinadi'
                            : text,
                        textAlign: textAlign,
                        maxLines: 7,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: textSize,
                          fontWeight: storyWeight,
                          fontFamily: font == 'serif' ? 'Georgia' : null,
                          height: 1.12,
                          shadows: const [
                            Shadow(
                              color: Colors.black54,
                              blurRadius: 12,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        composerField,
        const SizedBox(height: 14),
        CreateStoryTextControls(
          colors: colors,
          primary: primary,
          textAlign: textAlign,
          onTextAlignChanged: onTextAlignChanged,
          selectedFont: font,
          fonts: fonts,
          onFontChanged: onFontChanged,
          textSize: textSize,
          onTextSizeChanged: onTextSizeChanged,
          onResetPosition: onResetTextPosition,
        ),
        const SizedBox(height: 14),
        Text(
          'Fon rangi',
          style: TextStyle(
            color: colors.mutedForeground,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: palette.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, index) {
              final color = palette[index];
              final active = color.toARGB32() == backgroundColor.toARGB32();
              return GestureDetector(
                onTap: () => onBackgroundColorChanged(color),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: active ? Colors.white : colors.border,
                      width: active ? 3 : 1,
                    ),
                    boxShadow: active
                        ? [
                            BoxShadow(
                              color: color.withValues(alpha: 0.45),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ]
                        : null,
                  ),
                  child: active
                      ? const Icon(
                          LucideIcons.check,
                          color: Colors.white,
                          size: 20,
                        )
                      : null,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: colors.border),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              CreateMediaChip(
                icon: LucideIcons.camera,
                label: 'Camera',
                color: const Color(0xFF111827),
                onTap: onOpenCamera,
              ),
              CreateMediaChip(
                icon: LucideIcons.video,
                label: 'Record',
                color: const Color(0xFF7C3AED),
                onTap: onRecordVideo,
              ),
              CreateMediaChip(
                icon: LucideIcons.image,
                label: 'Photo',
                color: const Color(0xFF22C55E),
                onTap: onPickPhoto,
              ),
              CreateMediaChip(
                icon: LucideIcons.video,
                label: 'Video',
                color: const Color(0xFF3B82F6),
                onTap: onPickVideo,
              ),
              CreateMediaChip(
                icon: LucideIcons.music,
                label: 'Music',
                color: const Color(0xFFEC4899),
                onTap: onPickMusic,
              ),
              CreateMediaChip(
                icon: LucideIcons.type,
                label: 'Text',
                color: const Color(0xFFF97316),
                onTap: onUseTextMode,
              ),
              CreateMediaChip(
                icon: LucideIcons.atSign,
                label: 'Mention',
                color: const Color(0xFF0EA5E9),
                onTap: onAddMention,
              ),
            ],
          ),
        ),
        if (mentions.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final mention in mentions)
                InputChip(
                  label: Text(mention),
                  avatar: const Icon(LucideIcons.atSign, size: 14),
                  onDeleted: () => onRemoveMention(mention),
                ),
            ],
          ),
        ],
        if (musicTrack != null) ...[
          const SizedBox(height: 12),
          CreateMusicBanner(
            track: musicTrack!,
            onClear: onClearMusic,
          ),
        ],
      ],
    );
  }
}

class _StoryPreviewPill extends StatelessWidget {
  const _StoryPreviewPill({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
