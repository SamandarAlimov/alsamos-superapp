import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme/app_theme.dart';
import 'animated_sticker_renderer.dart';

class StickerPreviewPopup {
  static OverlayEntry? _entry;

  static void show(
    BuildContext context, {
    required String url,
    String? thumbnailUrl,
    String type = 'animated',
    String? packTitle,
    String? emoji,
  }) {
    hide();
    HapticFeedback.mediumImpact();
    final overlay = Overlay.of(context);
    _entry = OverlayEntry(
      builder: (ctx) => _StickerPreviewContent(
        url: url,
        thumbnailUrl: thumbnailUrl,
        type: type,
        packTitle: packTitle,
        emoji: emoji,
        onDismiss: hide,
      ),
    );
    overlay.insert(_entry!);
  }

  static void hide() {
    _entry?.remove();
    _entry = null;
  }
}

class _StickerPreviewContent extends StatefulWidget {
  final String url;
  final String? thumbnailUrl;
  final String type;
  final String? packTitle;
  final String? emoji;
  final VoidCallback onDismiss;

  const _StickerPreviewContent({
    required this.url,
    this.thumbnailUrl,
    required this.type,
    this.packTitle,
    this.emoji,
    required this.onDismiss,
  });

  @override
  State<_StickerPreviewContent> createState() => _StickerPreviewContentState();
}

class _StickerPreviewContentState extends State<_StickerPreviewContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..forward();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    await _anim.reverse();
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    return GestureDetector(
      onTap: _dismiss,
      onPanEnd: (_) => _dismiss(),
      child: AnimatedBuilder(
        animation: _anim,
        builder: (_, child) => Container(
          color: Colors.black.withValues(alpha: 0.6 * _anim.value),
          child: Center(
            child: Transform.scale(
              scale: 0.5 + 0.5 * Curves.easeOutBack.transform(_anim.value),
              child: Opacity(
                opacity: _anim.value.clamp(0.0, 1.0),
                child: child,
              ),
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(20),
              child: AnimatedStickerRenderer(
                url: widget.url,
                thumbnailUrl: widget.thumbnailUrl,
                type: widget.type,
                size: 160,
                loop: true,
              ),
            ),
            if (widget.packTitle != null || widget.emoji != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: c.card.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.emoji != null)
                      Text(
                        widget.emoji!,
                        style: const TextStyle(fontSize: 20),
                      ),
                    if (widget.packTitle != null)
                      Text(
                        widget.packTitle!,
                        style: TextStyle(
                          fontSize: 12,
                          color: c.mutedForeground,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
