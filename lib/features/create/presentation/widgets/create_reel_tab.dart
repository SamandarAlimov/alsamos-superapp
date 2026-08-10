import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/stories/story_avatar_ring.dart';
import 'create_empty_media_stage.dart';
import 'create_media_chip.dart';
import 'create_media_preview_stage.dart';
import 'create_publish_banners.dart';
import 'music_picker.dart';

class CreateReelTab extends StatelessWidget {
  const CreateReelTab({
    super.key,
    required this.colors,
    required this.primary,
    required this.contentController,
    required this.identityRow,
    required this.composerField,
    required this.metaInputs,
    required this.onEditMedia,
    required this.onRemoveMedia,
    required this.onPickVideo,
    required this.onPickMusic,
    required this.onClearMusic,
    required this.onFocusCaption,
    this.selectedMedia,
    this.musicTrack,
    this.profileUserId,
    this.profileAvatarUrl,
    this.profileFallback = 'U',
    this.profileUsername = 'user',
  });

  final AlsamosColors colors;
  final Color primary;
  final XFile? selectedMedia;
  final TextEditingController contentController;
  final Widget identityRow;
  final Widget composerField;
  final Widget metaInputs;
  final MusicTrack? musicTrack;
  final String? profileUserId;
  final String? profileAvatarUrl;
  final String profileFallback;
  final String profileUsername;
  final VoidCallback onEditMedia;
  final VoidCallback onRemoveMedia;
  final VoidCallback onPickVideo;
  final VoidCallback onPickMusic;
  final VoidCallback onClearMusic;
  final VoidCallback onFocusCaption;

  @override
  Widget build(BuildContext context) {
    final selected = selectedMedia;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 110),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1020),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 860;
              final preview = Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: AspectRatio(
                    aspectRatio: 9 / 16,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: colors.border),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 34,
                            offset: const Offset(0, 18),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: selected == null
                          ? CreateEmptyMediaStage(
                              title: 'Reel video tanlang',
                              subtitle:
                                  'Instagramdek 9:16 qisqa video. Keyin brend nomini shu oqimga bog\'laymiz.',
                              primary: primary,
                              onVideo: onPickVideo,
                            )
                          : Stack(
                              fit: StackFit.expand,
                              children: [
                                CreateLocalMediaFrame(
                                  file: selected,
                                  aspectRatio: 9 / 16,
                                  forceReel: true,
                                  onEdit: onEditMedia,
                                  onRemove: onRemoveMedia,
                                ),
                                Positioned(
                                  left: 14,
                                  right: 72,
                                  bottom: 18,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        children: [
                                          StoryAvatarRing(
                                            userId: profileUserId,
                                            avatarUrl: profileAvatarUrl,
                                            fallback: profileFallback,
                                            size: 34,
                                          ),
                                          const SizedBox(width: 8),
                                          Flexible(
                                            child: Text(
                                              '@$profileUsername',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 5,
                                            ),
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                              border: Border.all(
                                                color: Colors.white70,
                                              ),
                                            ),
                                            child: const Text(
                                              'Follow',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w800,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      ValueListenableBuilder<TextEditingValue>(
                                        valueListenable: contentController,
                                        builder: (_, value, __) {
                                          final text = value.text.trim();
                                          return Text(
                                            text.isEmpty
                                                ? 'Reel tavsifi shu yerda ko\'rinadi'
                                                : text,
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w600,
                                              height: 1.25,
                                              shadows: [
                                                Shadow(
                                                  color: Colors.black54,
                                                  blurRadius: 8,
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                      if (musicTrack != null) ...[
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            const Icon(
                                              LucideIcons.music,
                                              color: Colors.white,
                                              size: 14,
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                musicTrack!.title,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const Positioned(
                                  right: 12,
                                  bottom: 24,
                                  child: Column(
                                    children: [
                                      _ReelActionIcon(icon: LucideIcons.heart),
                                      _ReelActionIcon(
                                          icon: LucideIcons.messageCircle),
                                      _ReelActionIcon(icon: LucideIcons.send),
                                      _ReelActionIcon(
                                          icon: LucideIcons.repeat2),
                                      _ReelActionIcon(
                                          icon: LucideIcons.bookmark),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              );

              final controls = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  identityRow,
                  const SizedBox(height: 16),
                  composerField,
                  if (musicTrack != null)
                    CreateMusicBanner(
                      track: musicTrack!,
                      onClear: onClearMusic,
                    ),
                  const SizedBox(height: 10),
                  metaInputs,
                  const SizedBox(height: 14),
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
                          icon: LucideIcons.upload,
                          label: selected == null
                              ? 'Video yuklash'
                              : 'Video almashtirish',
                          color: const Color(0xFF3B82F6),
                          onTap: onPickVideo,
                        ),
                        CreateMediaChip(
                          icon: LucideIcons.music,
                          label: 'Musiqa',
                          color: const Color(0xFFEC4899),
                          onTap: onPickMusic,
                        ),
                        CreateMediaChip(
                          icon: LucideIcons.captions,
                          label: 'Caption',
                          color: const Color(0xFFF97316),
                          onTap: onFocusCaption,
                        ),
                      ],
                    ),
                  ),
                ],
              );

              return wide
                  ? Row(
                      key: const Key('create-reel-wide-layout'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: preview),
                        const SizedBox(width: 34),
                        Expanded(child: controls),
                      ],
                    )
                  : Column(
                      key: const Key('create-reel-compact-layout'),
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
}

class _ReelActionIcon extends StatelessWidget {
  const _ReelActionIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Icon(icon, color: Colors.white, size: 28),
    );
  }
}
