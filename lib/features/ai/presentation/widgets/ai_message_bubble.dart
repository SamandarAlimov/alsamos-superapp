import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../data/ai_models.dart';
import '../providers/ai_provider.dart';

class AiMessageBubble extends ConsumerStatefulWidget {
  final AiMessage message;
  final bool isLast;

  const AiMessageBubble({super.key, required this.message, this.isLast = false});

  @override
  ConsumerState<AiMessageBubble> createState() => _AiMessageBubbleState();
}

class _AiMessageBubbleState extends ConsumerState<AiMessageBubble> {
  bool _copied = false;

  void _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.message.content));
    HapticFeedback.selectionClick();
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.message.isUser ? _userBubble(context) : _assistantBubble(context);
  }

  Widget _userBubble(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        child: Container(
          margin: const EdgeInsets.only(bottom: 16, left: 60),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: primary,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(6),
            ),
            boxShadow: [
              BoxShadow(
                color: primary.withValues(alpha: 0.15),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: SelectableText(
            widget.message.content,
            style: const TextStyle(fontSize: 14, color: Colors.white, height: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _assistantBubble(BuildContext context) {
    final c = AlsamosColors.of(context);
    final msg = widget.message;
    final hasImage = msg.imageUrl != null && msg.imageUrl!.isNotEmpty;
    final hasCode = _containsCodeBlock(msg.content);

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _avatar(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (msg.content.isNotEmpty)
                  hasCode ? _renderRichContent(c, msg.content) : _renderText(c, msg.content),
                if (hasImage) ...[
                  const SizedBox(height: 10),
                  _imageCard(c, msg.imageUrl!),
                ],
                const SizedBox(height: 6),
                _actions(c),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatar() {
    return Container(
      width: 30,
      height: 30,
      margin: const EdgeInsets.only(top: 2),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.alsamosOrange, AppColors.alsamosOrangeDark],
        ),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: AppColors.alsamosOrange.withValues(alpha: 0.2),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Icon(LucideIcons.sparkles, size: 14, color: Colors.white),
    );
  }

  Widget _renderText(AlsamosColors c, String text) {
    return SelectableText(
      text,
      style: TextStyle(fontSize: 14, height: 1.65, color: c.foreground),
    );
  }

  Widget _renderRichContent(AlsamosColors c, String text) {
    final segments = _parseContent(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: segments.map((seg) {
        if (seg.isCode) {
          return _codeBlock(c, seg.content, seg.language);
        }
        return SelectableText(
          seg.content,
          style: TextStyle(fontSize: 14, height: 1.65, color: c.foreground),
        );
      }).toList(),
    );
  }

  Widget _codeBlock(AlsamosColors c, String code, String? language) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: c.muted,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: c.muted.withValues(alpha: 0.8),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(bottom: BorderSide(color: c.border.withValues(alpha: 0.3))),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.code, size: 12, color: c.mutedForeground),
                const SizedBox(width: 6),
                Text(
                  language ?? 'code',
                  style: TextStyle(fontSize: 10, color: c.mutedForeground, fontWeight: FontWeight.w500),
                ),
                const Spacer(),
                InkWell(
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: code));
                    HapticFeedback.selectionClick();
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.copy, size: 11, color: c.mutedForeground),
                      const SizedBox(width: 4),
                      Text('Nusxa', style: TextStyle(fontSize: 10, color: c.mutedForeground)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              code.trim(),
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                height: 1.5,
                color: c.foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _imageCard(AlsamosColors c, String url) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        children: [
          CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            width: double.infinity,
            placeholder: (_, __) => Container(
              height: 240,
              color: c.muted,
              child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            errorWidget: (_, __, ___) => Container(
              height: 120,
              color: c.muted,
              child: Center(
                child: Icon(LucideIcons.imageOff, color: c.mutedForeground),
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _imageActionBtn(c, LucideIcons.download, () {}),
                const SizedBox(width: 4),
                _imageActionBtn(c, LucideIcons.maximize2, () {}),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _imageActionBtn(AlsamosColors c, IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 14, color: Colors.white),
        ),
      ),
    );
  }

  Widget _actions(AlsamosColors c) {
    return Row(
      children: [
        _actionBtn(c, _copied ? LucideIcons.check : LucideIcons.copy, _copy,
            active: _copied, tooltip: 'Nusxa olish'),
        _actionBtn(c, LucideIcons.rotateCcw,
            () => ref.read(aiProvider.notifier).regenerate(),
            tooltip: 'Qayta yaratish'),
        _actionBtn(c, LucideIcons.thumbsUp, () {}, tooltip: 'Yoqdi'),
        _actionBtn(c, LucideIcons.thumbsDown, () {}, tooltip: 'Yoqmadi'),
      ],
    );
  }

  Widget _actionBtn(AlsamosColors c, IconData icon, VoidCallback onTap,
      {bool active = false, String? tooltip}) {
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon,
                size: 13,
                color: active ? const Color(0xFF22C55E) : c.mutedForeground.withValues(alpha: 0.6)),
          ),
        ),
      ),
    );
  }

  bool _containsCodeBlock(String text) {
    return text.contains('```');
  }

  List<_ContentSegment> _parseContent(String text) {
    final segments = <_ContentSegment>[];
    final regex = RegExp(r'```(\w*)\n?([\s\S]*?)```');
    var lastEnd = 0;

    for (final match in regex.allMatches(text)) {
      if (match.start > lastEnd) {
        final before = text.substring(lastEnd, match.start).trim();
        if (before.isNotEmpty) {
          segments.add(_ContentSegment(content: before, isCode: false));
        }
      }
      segments.add(_ContentSegment(
        content: match.group(2) ?? '',
        isCode: true,
        language: match.group(1)?.isNotEmpty == true ? match.group(1) : null,
      ));
      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      final remaining = text.substring(lastEnd).trim();
      if (remaining.isNotEmpty) {
        segments.add(_ContentSegment(content: remaining, isCode: false));
      }
    }

    return segments;
  }
}

class _ContentSegment {
  final String content;
  final bool isCode;
  final String? language;
  const _ContentSegment({required this.content, required this.isCode, this.language});
}

class AiLoadingBubble extends StatefulWidget {
  final bool isImageGen;
  const AiLoadingBubble({super.key, this.isImageGen = false});

  @override
  State<AiLoadingBubble> createState() => _AiLoadingBubbleState();
}

class _AiLoadingBubbleState extends State<AiLoadingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.alsamosOrange, AppColors.alsamosOrangeDark],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(LucideIcons.sparkles, size: 14, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: c.card,
              border: Border.all(color: c.border.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _dots(),
                const SizedBox(width: 10),
                Text(
                  widget.isImageGen ? 'Rasm yaratilmoqda...' : "O'ylayapman...",
                  style: TextStyle(fontSize: 12, color: c.mutedForeground),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dots() {
    return SizedBox(
      width: 32,
      height: 8,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(3, (i) {
            final t = ((_ctrl.value + i * 0.2) % 1.0);
            final scale = 0.6 + 0.4 * (1 - (2 * t - 1).abs());
            return Transform.scale(
              scale: scale,
              child: Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: AppColors.alsamosOrange,
                  shape: BoxShape.circle,
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
