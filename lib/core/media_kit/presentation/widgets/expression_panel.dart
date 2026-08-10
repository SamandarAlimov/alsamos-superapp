import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/communication/emoji/emoji_picker_widget.dart';
import '../../../../shared/communication/gif/gif_picker_widget.dart';
import '../../../../shared/communication/stickers/sticker_picker_widget.dart';
import '../../domain/entities/media_attachment.dart';
import '../../domain/entities/media_composer_config.dart';
import '../controllers/media_composer_controller.dart';
import 'sticker_store_sheet.dart';

class ExpressionPanel extends ConsumerWidget {
  final MediaComposerConfig config;
  final ExpressionPanelTab activeTab;
  final ValueChanged<ExpressionPanelTab> onTabChanged;
  final ValueChanged<String> onEmojiSelected;
  final ValueChanged<MediaAttachment> onStickerSelected;
  final ValueChanged<MediaAttachment> onGifSelected;

  const ExpressionPanel({
    super.key,
    required this.config,
    required this.activeTab,
    required this.onTabChanged,
    required this.onEmojiSelected,
    required this.onStickerSelected,
    required this.onGifSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AlsamosColors.of(context);
    return Container(
      height: 280,
      decoration: BoxDecoration(
        color: c.card,
        border: Border(top: BorderSide(color: c.border, width: 0.5)),
      ),
      child: Column(
        children: [
          _buildTabs(c, context),
          Expanded(child: _buildContent(ref)),
        ],
      ),
    );
  }

  Widget _buildTabs(AlsamosColors c, BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border, width: 0.5)),
      ),
      child: Row(
        children: [
          _tabButton('Emoji', ExpressionPanelTab.emoji, c),
          if (config.allowStickers) ...[
            const SizedBox(width: 4),
            _tabButton('Stikerlar', ExpressionPanelTab.stickers, c),
          ],
          if (config.allowGif) ...[
            const SizedBox(width: 4),
            _tabButton('GIF', ExpressionPanelTab.gif, c),
          ],
          const Spacer(),
          if (config.allowStickers)
            GestureDetector(
              onTap: () => StickerStoreSheet.show(context),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(LucideIcons.plus, size: 18, color: c.mutedForeground),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tabButton(String label, ExpressionPanelTab tab, AlsamosColors c) {
    final active = activeTab == tab;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTabChanged(tab);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: active ? c.primary.withValues(alpha: 0.12) : Colors.transparent,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            color: active ? c.primary : c.mutedForeground,
          ),
        ),
      ),
    );
  }

  Widget _buildContent(WidgetRef ref) {
    switch (activeTab) {
      case ExpressionPanelTab.emoji:
        return EmojiPickerWidget(
          onSelect: onEmojiSelected,
          style: EmojiPickerStyle.inline,
        );
      case ExpressionPanelTab.stickers:
        return StickerPickerWidget(
          onSelect: (sticker) {
            onStickerSelected(MediaAttachment(
              type: MediaAttachmentType.sticker,
              remoteUrl: sticker.imageUrl,
              metadata: {'sticker_id': sticker.id, 'pack_id': sticker.packId},
            ));
          },
        );
      case ExpressionPanelTab.gif:
        return GifPickerWidget(
          onSelect: (gif) {
            onGifSelected(MediaAttachment(
              type: MediaAttachmentType.gif,
              remoteUrl: gif.url,
              thumbnailUrl: gif.previewUrl,
              metadata: {'gif_id': gif.id, 'title': gif.title},
            ));
          },
          style: GifPickerStyle.inline,
        );
    }
  }
}
