import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/communication/voice/voice_recorder_manager.dart';
import '../../domain/entities/composer_result.dart';
import '../../domain/entities/media_attachment.dart';
import '../../domain/entities/media_composer_config.dart';
import '../controllers/media_composer_controller.dart';
import 'expression_panel.dart';
import 'video_note_recorder.dart';
import 'voice_recorder_bar.dart';

class MediaComposerBar extends ConsumerStatefulWidget {
  final MediaComposerConfig config;
  final ValueChanged<ComposerResult> onSend;
  final ValueChanged<MediaAttachment>? onStickerSend;
  final ValueChanged<MediaAttachment>? onGifSend;
  final ValueChanged<MediaAttachment>? onVoiceSend;
  final ValueChanged<MediaAttachment>? onVideoNoteSend;
  final String? replyToId;
  final String? replyPreviewText;
  final VoidCallback? onCancelReply;

  const MediaComposerBar({
    super.key,
    required this.config,
    required this.onSend,
    this.onStickerSend,
    this.onGifSend,
    this.onVoiceSend,
    this.onVideoNoteSend,
    this.replyToId,
    this.replyPreviewText,
    this.onCancelReply,
  });

  @override
  ConsumerState<MediaComposerBar> createState() => _MediaComposerBarState();
}

class _MediaComposerBarState extends ConsumerState<MediaComposerBar> {
  late final TextEditingController _textCtrl;
  late final FocusNode _focusNode;
  bool _showPanel = false;
  ExpressionPanelTab _activeTab = ExpressionPanelTab.emoji;
  VoiceBarMode _voiceMode = VoiceBarMode.idle;
  double _slideX = 0;
  double _slideY = 0;

  static const _lockThreshold = 80.0;
  static const _cancelThreshold = 100.0;

  @override
  void initState() {
    super.initState();
    _textCtrl = TextEditingController();
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _textCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus && _showPanel) {
      setState(() => _showPanel = false);
    }
  }

  bool get _canSend => _textCtrl.text.trim().isNotEmpty;

  bool get _isVoiceActive =>
      _voiceMode == VoiceBarMode.recording ||
      _voiceMode == VoiceBarMode.locked ||
      _voiceMode == VoiceBarMode.preview;

  void _togglePanel([ExpressionPanelTab? tab]) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_showPanel && tab == _activeTab) {
        _showPanel = false;
        _focusNode.requestFocus();
      } else {
        _showPanel = true;
        _activeTab = tab ?? _activeTab;
        _focusNode.unfocus();
      }
    });
  }

  void _onEmojiSelected(String emoji) {
    final sel = _textCtrl.selection;
    final text = _textCtrl.text;
    final newText = sel.isValid
        ? text.replaceRange(sel.start, sel.end, emoji)
        : text + emoji;
    _textCtrl.text = newText;
    final offset = (sel.isValid ? sel.start : text.length) + emoji.length;
    _textCtrl.selection = TextSelection.collapsed(offset: offset);
    setState(() {});
  }

  void _onStickerSelected(MediaAttachment sticker) {
    if (widget.onStickerSend != null) {
      widget.onStickerSend!(sticker);
    } else {
      widget.onSend(ComposerResult(attachments: [sticker]));
    }
    setState(() => _showPanel = false);
  }

  void _onGifSelected(MediaAttachment gif) {
    if (widget.onGifSend != null) {
      widget.onGifSend!(gif);
    } else {
      widget.onSend(ComposerResult(attachments: [gif]));
    }
    setState(() => _showPanel = false);
  }

  void _send() {
    if (!_canSend) return;
    HapticFeedback.lightImpact();
    widget.onSend(ComposerResult(
      text: _textCtrl.text.trim(),
      replyToId: widget.replyToId,
    ));
    _textCtrl.clear();
    setState(() {});
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    final attachment = MediaAttachment(
      type: MediaAttachmentType.image,
      localPath: file.path,
      mimeType: file.mimeType,
    );
    widget.onSend(ComposerResult(
      text: _textCtrl.text.trim(),
      attachments: [attachment],
      replyToId: widget.replyToId,
    ));
    _textCtrl.clear();
    setState(() {});
  }

  Future<void> _showAttachMenu() async {
    final c = AlsamosColors.of(context);
    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 12),
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: c.mutedForeground.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              if (widget.config.allowImage) _attachOption(ctx, LucideIcons.image, 'Rasm', 'image', c),
              if (widget.config.allowVideo) _attachOption(ctx, LucideIcons.video, 'Video', 'video', c),
              if (widget.config.allowVideoNote) _attachOption(ctx, LucideIcons.circle, 'Video xabar', 'video_note', c),
              if (widget.config.allowFileDocument) _attachOption(ctx, LucideIcons.file, 'Hujjat', 'file', c),
              if (widget.config.allowLocation) _attachOption(ctx, LucideIcons.mapPin, 'Joylashuv', 'location', c),
              if (widget.config.allowPolls) _attachOption(ctx, LucideIcons.barChart3, 'So\'rovnoma', 'poll', c),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
    if (result == null || !mounted) return;
    await _handleAttachResult(result);
  }

  Widget _attachOption(BuildContext ctx, IconData icon, String label, String value, AlsamosColors c) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: c.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 20, color: c.primary),
      ),
      title: Text(label, style: TextStyle(fontSize: 15, color: c.foreground)),
      onTap: () => Navigator.pop(ctx, value),
    );
  }

  Future<void> _handleAttachResult(String type) async {
    switch (type) {
      case 'image':
        await _pickImage();
        break;
      case 'video':
        final picker = ImagePicker();
        final file = await picker.pickVideo(source: ImageSource.gallery);
        if (file == null) return;
        widget.onSend(ComposerResult(
          attachments: [
            MediaAttachment(
              type: MediaAttachmentType.video,
              localPath: file.path,
              mimeType: file.mimeType,
            )
          ],
          replyToId: widget.replyToId,
        ));
        break;
      case 'video_note':
        final result = await VideoNoteRecorder.show(context);
        if (result != null) {
          if (widget.onVideoNoteSend != null) {
            widget.onVideoNoteSend!(result);
          } else {
            widget.onSend(ComposerResult(attachments: [result]));
          }
        }
        break;
      case 'file':
      case 'location':
      case 'poll':
        break;
    }
  }

  Future<void> _onVoiceLongPressStart(LongPressStartDetails _) async {
    HapticFeedback.heavyImpact();
    final recorder = ref.read(voiceRecorderManagerProvider.notifier);
    final started = await recorder.start();
    if (!started) return;
    setState(() {
      _voiceMode = VoiceBarMode.recording;
      _slideX = 0;
      _slideY = 0;
    });
  }

  void _onVoiceLongPressMoveUpdate(LongPressMoveUpdateDetails d) {
    if (_voiceMode != VoiceBarMode.recording) return;
    setState(() {
      _slideX += d.offsetFromOrigin.dx < _slideX ? d.offsetFromOrigin.dx - _slideX : 0;
      _slideX = d.offsetFromOrigin.dx.clamp(-200.0, 0.0);
      _slideY = d.offsetFromOrigin.dy.clamp(-200.0, 0.0);
    });

    if (_slideX < -_cancelThreshold) {
      _cancelVoice();
      return;
    }
    if (_slideY < -_lockThreshold) {
      HapticFeedback.mediumImpact();
      setState(() => _voiceMode = VoiceBarMode.locked);
    }
  }

  Future<void> _onVoiceLongPressEnd(LongPressEndDetails _) async {
    if (_voiceMode == VoiceBarMode.recording) {
      await _stopAndSendVoice();
    }
    setState(() {
      _slideX = 0;
      _slideY = 0;
    });
  }

  Future<void> _stopAndSendVoice() async {
    final recorder = ref.read(voiceRecorderManagerProvider.notifier);
    final result = await recorder.stop();
    setState(() => _voiceMode = VoiceBarMode.idle);
    if (result == null) return;
    final attachment = MediaAttachment(
      type: MediaAttachmentType.voiceNote,
      localPath: result.path,
      mimeType: result.mimeType,
      durationMs: result.duration.inMilliseconds,
      waveform: result.waveform,
    );
    if (widget.onVoiceSend != null) {
      widget.onVoiceSend!(attachment);
    } else {
      widget.onSend(ComposerResult(attachments: [attachment]));
    }
  }

  Future<void> _cancelVoice() async {
    final recorder = ref.read(voiceRecorderManagerProvider.notifier);
    await recorder.cancel();
    setState(() {
      _voiceMode = VoiceBarMode.idle;
      _slideX = 0;
      _slideY = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final voiceState = ref.watch(voiceRecorderManagerProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.replyToId != null) _buildReplyPreview(c),
        if (_isVoiceActive)
          _buildVoiceBar(c, voiceState)
        else
          _buildInputBar(c, voiceState),
        if (_showPanel && !_isVoiceActive)
          ExpressionPanel(
            config: widget.config,
            activeTab: _activeTab,
            onTabChanged: (tab) => setState(() => _activeTab = tab),
            onEmojiSelected: _onEmojiSelected,
            onStickerSelected: _onStickerSelected,
            onGifSelected: _onGifSelected,
          ),
      ],
    );
  }

  Widget _buildReplyPreview(AlsamosColors c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: c.card,
        border: Border(top: BorderSide(color: c.border, width: 0.5)),
      ),
      child: Row(
        children: [
          Container(width: 3, height: 32, color: c.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Javob',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: c.primary)),
                if (widget.replyPreviewText != null)
                  Text(
                    widget.replyPreviewText!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: c.mutedForeground),
                  ),
              ],
            ),
          ),
          GestureDetector(
            onTap: widget.onCancelReply,
            child: Icon(LucideIcons.x, size: 18, color: c.mutedForeground),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceBar(AlsamosColors c, VoiceRecorderState voiceState) {
    if (_voiceMode == VoiceBarMode.locked) {
      return VoiceRecorderBar(
        onSend: (attachment) {
          if (widget.onVoiceSend != null) {
            widget.onVoiceSend!(attachment);
          } else {
            widget.onSend(ComposerResult(attachments: [attachment]));
          }
          setState(() => _voiceMode = VoiceBarMode.idle);
        },
        onCancel: () => setState(() => _voiceMode = VoiceBarMode.idle),
      );
    }

    final minutes = voiceState.elapsed.inMinutes.toString().padLeft(2, '0');
    final seconds = (voiceState.elapsed.inSeconds % 60).toString().padLeft(2, '0');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: c.card,
        border: Border(top: BorderSide(color: c.border, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '$minutes:$seconds',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: c.foreground,
              ),
            ),
            const Spacer(),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 150),
              opacity: _slideX < -20 ? 1.0 : 0.5,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.chevronLeft, size: 14, color: c.mutedForeground),
                  Text('Bekor', style: TextStyle(fontSize: 12, color: c.mutedForeground)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 150),
              opacity: _slideY < -20 ? 1.0 : 0.4,
              child: Icon(LucideIcons.lock, size: 16, color: c.mutedForeground),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar(AlsamosColors c, VoiceRecorderState voiceState) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: c.card,
        border: Border(top: BorderSide(color: c.border, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _emojiButton(c),
            if (widget.config.hasMediaOptions) _attachButton(c),
            Expanded(child: _textField(c)),
            if (_canSend)
              _sendButton(c)
            else if (widget.config.allowAudio)
              _micButton(c),
          ],
        ),
      ),
    );
  }

  Widget _emojiButton(AlsamosColors c) {
    final isActive = _showPanel;
    return GestureDetector(
      onTap: () => _togglePanel(ExpressionPanelTab.emoji),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(
          isActive ? LucideIcons.keyboard : LucideIcons.smile,
          size: 22,
          color: isActive ? c.primary : c.mutedForeground,
        ),
      ),
    );
  }

  Widget _attachButton(AlsamosColors c) {
    return GestureDetector(
      onTap: _showAttachMenu,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(LucideIcons.paperclip, size: 22, color: c.mutedForeground),
      ),
    );
  }

  Widget _textField(AlsamosColors c) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 120),
      decoration: BoxDecoration(
        color: c.muted,
        borderRadius: BorderRadius.circular(20),
      ),
      child: TextField(
        controller: _textCtrl,
        focusNode: _focusNode,
        maxLines: null,
        textInputAction: TextInputAction.newline,
        style: TextStyle(fontSize: 15, color: c.foreground),
        decoration: InputDecoration(
          hintText: widget.config.hintText,
          hintStyle: TextStyle(fontSize: 15, color: c.mutedForeground),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          isDense: true,
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _sendButton(AlsamosColors c) {
    return GestureDetector(
      onTap: _send,
      child: Container(
        margin: const EdgeInsets.only(left: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: c.primary,
          shape: BoxShape.circle,
        ),
        child: const Icon(LucideIcons.sendHorizontal,
            size: 20, color: Colors.white),
      ),
    );
  }

  Widget _micButton(AlsamosColors c) {
    return GestureDetector(
      onLongPressStart: _onVoiceLongPressStart,
      onLongPressMoveUpdate: _onVoiceLongPressMoveUpdate,
      onLongPressEnd: _onVoiceLongPressEnd,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(LucideIcons.mic, size: 22, color: c.mutedForeground),
      ),
    );
  }
}
