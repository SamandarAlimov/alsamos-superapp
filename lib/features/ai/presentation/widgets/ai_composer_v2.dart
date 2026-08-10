import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../data/ai_models_v2.dart';
import '../../data/intent_detector.dart';

/// Unified composer bar for AI input.
/// - Auto-growing multiline text field (1-6 lines)
/// - Attachment support with file chips
/// - Voice input button
/// - Send/stop button with morphing
/// - Intent detection with optional confirmation dialog
/// - Model selector
/// - No more Chat/Imagine toggle — one input for everything
class AIComposerV2 extends ConsumerStatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final VoidCallback? onAttach;
  final VoidCallback? onVoice;
  final bool isGenerating;
  final List<AttachedFile> attachments;
  final Function(int)? onRemoveAttachment;
  final String? selectedModel;
  final VoidCallback? onModelSelect;

  const AIComposerV2({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSend,
    this.onAttach,
    this.onVoice,
    this.isGenerating = false,
    this.attachments = const [],
    this.onRemoveAttachment,
    this.selectedModel,
    this.onModelSelect,
  });

  @override
  ConsumerState<AIComposerV2> createState() => _AIComposerV2State();
}

class _AIComposerV2State extends ConsumerState<AIComposerV2> {
  DetectedIntent? _detectedIntent;
  bool _showIntentHint = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    final text = widget.controller.text.trim();
    if (text.isEmpty) {
      if (_detectedIntent != null || _showIntentHint) {
        setState(() {
          _detectedIntent = null;
          _showIntentHint = false;
        });
      }
      return;
    }

    // Debounce intent detection (only on significant text changes)
    if (text.length > 10) {
      final intent = IntentDetector.detect(text);
      if (intent.type != IntentType.chat && intent.isHighConfidence) {
        if (_detectedIntent?.type != intent.type) {
          setState(() {
            _detectedIntent = intent;
            _showIntentHint = true;
          });
          // Auto-hide hint after 3 seconds
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) {
              setState(() => _showIntentHint = false);
            }
          });
        }
      } else if (_detectedIntent != null) {
        setState(() {
          _detectedIntent = null;
          _showIntentHint = false;
        });
      }
    }
  }

  void _handleSend() {
    final text = widget.controller.text.trim();
    if (text.isEmpty || widget.isGenerating) return;

    final intent = IntentDetector.detect(text);

    // If low confidence on non-chat intent, show disambiguation dialog
    if (intent.requiresConfirmation) {
      _showIntentConfirmation(intent);
    } else {
      widget.onSend();
    }
  }

  void _showIntentConfirmation(DetectedIntent intent) {
    final c = AlsamosColors.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        title: Row(
          children: [
            Icon(
              IntentDetector.getIntentIconData(intent.type),
              color: AppColors.alsamosOrange,
              size: 20,
            ),
            const SizedBox(width: 12),
            Text(
              'Niyatni tasdiqlang',
              style: TextStyle(fontSize: 16, color: c.foreground),
            ),
          ],
        ),
        content: Text(
          "Siz ${IntentDetector.getIntentDescription(intent.type).toLowerCase()} qilmoqchimisiz?",
          style: TextStyle(fontSize: 14, color: c.foreground),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              // User declined, treat as regular chat
              widget.onSend();
            },
            child: Text('Yo\'q, oddiy suhbat',
                style: TextStyle(color: c.mutedForeground)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              widget.onSend();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.alsamosOrange,
              foregroundColor: Colors.white,
            ),
            child: Text(
                'Ha, ${IntentDetector.getIntentDescription(intent.type)}'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final hasText = widget.controller.text.trim().isNotEmpty;
    final hasAttachments = widget.attachments.isNotEmpty;
    final isMobile = MediaQuery.of(context).size.width < 768;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: c.background.withValues(alpha: 0.95),
        border:
            Border(top: BorderSide(color: c.border.withValues(alpha: 0.2))),
      ),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Intent hint banner
                if (_showIntentHint && _detectedIntent != null)
                  _buildIntentHint(c, _detectedIntent!),

                // Attachments row
                if (hasAttachments) _buildAttachments(c),

                // Main input container
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  decoration: BoxDecoration(
                    color: c.card.withValues(alpha: 0.8),
                    border: Border.all(
                      color: widget.focusNode.hasFocus
                          ? AppColors.alsamosOrange.withValues(alpha: 0.5)
                          : c.border.withValues(alpha: 0.5),
                      width: widget.focusNode.hasFocus ? 1.5 : 1,
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Text input
                      Expanded(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                              minHeight: 48, maxHeight: 180),
                          child: TextField(
                            controller: widget.controller,
                            focusNode: widget.focusNode,
                            minLines: 1,
                            maxLines: 6,
                            enabled: !widget.isGenerating,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _handleSend(),
                            style: const TextStyle(fontSize: 14, height: 1.4),
                            decoration: InputDecoration(
                              hintText: _getPlaceholder(),
                              hintStyle: TextStyle(
                                fontSize: 14,
                                color:
                                    c.mutedForeground.withValues(alpha: 0.6),
                              ),
                              border: InputBorder.none,
                              contentPadding:
                                  const EdgeInsets.fromLTRB(16, 14, 0, 14),
                            ),
                          ),
                        ),
                      ),

                      // Attachment button (desktop only)
                      if (!isMobile && widget.onAttach != null)
                        _toolButton(c, LucideIcons.paperclip, widget.onAttach!,
                            enabled: !widget.isGenerating),

                      // Voice button (desktop only)
                      if (!isMobile && widget.onVoice != null)
                        _toolButton(c, LucideIcons.mic, widget.onVoice!,
                            enabled: !widget.isGenerating),

                      // Send / Stop button
                      Padding(
                        padding: const EdgeInsets.fromLTRB(2, 0, 8, 8),
                        child: _buildSendButton(c,
                            hasText: hasText, busy: widget.isGenerating),
                      ),
                    ],
                  ),
                ),

                // Bottom hint + model selector row
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        "Alsamos AI xato qilishi mumkin. Muhim ma'lumotlarni tekshiring.",
                        textAlign: TextAlign.left,
                        style: TextStyle(
                          fontSize: 10,
                          color: c.mutedForeground.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                    if (widget.onModelSelect != null) ...[
                      const SizedBox(width: 8),
                      _buildModelSelector(c),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIntentHint(AlsamosColors c, DetectedIntent intent) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.alsamosOrange.withValues(alpha: 0.1),
            AppColors.alsamosOrangeDark.withValues(alpha: 0.05),
          ],
        ),
        border: Border.all(
          color: AppColors.alsamosOrange.withValues(alpha: 0.3),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            IntentDetector.getIntentIconData(intent.type),
            size: 16,
            color: AppColors.alsamosOrange,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Aniqlandi: ${IntentDetector.getIntentDescription(intent.type)}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.alsamosOrange,
              ),
            ),
          ),
          InkWell(
            onTap: () => setState(() => _showIntentHint = false),
            child: Icon(LucideIcons.x,
                size: 14, color: c.mutedForeground.withValues(alpha: 0.7)),
          ),
        ],
      ),
    );
  }

  Widget _buildAttachments(AlsamosColors c) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: widget.attachments.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => _attachmentChip(c, widget.attachments[i], i),
      ),
    );
  }

  Widget _attachmentChip(AlsamosColors c, AttachedFile file, int index) {
    return Container(
      width: 120,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: c.card,
        border: Border.all(color: c.border.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                _getFileIcon(file.type),
                size: 20,
                color: AppColors.alsamosOrange,
              ),
              const SizedBox(height: 4),
              Text(
                file.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
              ),
              Text(
                file.sizeFormatted,
                style: TextStyle(fontSize: 9, color: c.mutedForeground),
              ),
            ],
          ),
          Positioned(
            top: -4,
            right: -4,
            child: InkWell(
              onTap: () => widget.onRemoveAttachment?.call(index),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: c.destructive,
                  shape: BoxShape.circle,
                ),
                child: const Icon(LucideIcons.x, size: 10, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolButton(
      AlsamosColors c, IconData icon, VoidCallback onTap,
      {bool enabled = true}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
        width: 32,
        height: 32,
        child: IconButton(
          padding: EdgeInsets.zero,
          iconSize: 16,
          icon: Icon(icon,
              color: enabled ? c.mutedForeground : c.mutedForeground.withValues(alpha: 0.4)),
          onPressed: enabled ? onTap : null,
        ),
      ),
    );
  }

  Widget _buildSendButton(AlsamosColors c,
      {required bool hasText, required bool busy}) {
    final enabled = hasText && !busy;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled ? _handleSend : (busy ? null : null),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            gradient: enabled
                ? const LinearGradient(
                    colors: [
                      AppColors.alsamosOrange,
                      AppColors.alsamosOrangeDark
                    ],
                  )
                : null,
            color: enabled ? null : c.muted,
            borderRadius: BorderRadius.circular(12),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: AppColors.alsamosOrange.withValues(alpha: 0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: busy
              ? const Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  ),
                )
              : Icon(
                  LucideIcons.arrowUp,
                  size: 16,
                  color: enabled ? Colors.white : c.mutedForeground,
                ),
        ),
      ),
    );
  }

  Widget _buildModelSelector(AlsamosColors c) {
    return InkWell(
      onTap: widget.onModelSelect,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: c.muted.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.zap, size: 12, color: AppColors.alsamosOrange),
            const SizedBox(width: 6),
            Text(
              widget.selectedModel ?? 'Gemini 3 Flash',
              style: TextStyle(fontSize: 10, color: c.mutedForeground),
            ),
          ],
        ),
      ),
    );
  }

  String _getPlaceholder() {
    if (widget.attachments.isNotEmpty) {
      return 'Bu fayl haqida gap...';
    }
    return 'Xabar yozing, rasm yarating, kod yozing...';
  }

  IconData _getFileIcon(AttachmentType type) {
    switch (type) {
      case AttachmentType.image:
        return LucideIcons.image;
      case AttachmentType.video:
        return LucideIcons.video;
      case AttachmentType.audio:
        return LucideIcons.music;
      case AttachmentType.document:
        return LucideIcons.fileText;
      case AttachmentType.spreadsheet:
        return LucideIcons.sheet;
      case AttachmentType.code:
        return LucideIcons.code;
      case AttachmentType.other:
        return LucideIcons.file;
    }
  }
}
