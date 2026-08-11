import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/media_kit/domain/entities/media_attachment.dart';
import '../../../../core/media_kit/domain/entities/media_composer_config.dart';
import '../../../../core/media_kit/presentation/controllers/media_composer_controller.dart';
import '../../../../core/media_kit/presentation/widgets/expression_panel.dart';
import '../../../../core/media_kit/presentation/widgets/video_note_recorder.dart';
import '../../../../shared/communication/voice/voice_recorder_manager.dart';
import 'gif_picker.dart';
import 'mention_autocomplete.dart';
import 'hashtag_autocomplete.dart';
import 'schedule_message_dialog.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../../../shared/widgets/error_mapper.dart';
import '../../../../shared/services/camera_capability.dart';

// Telegram-style message composer — matches web messages/MessageInput.tsx behavior.
class MessageInput extends ConsumerStatefulWidget {
  final String conversationId;
  final Future<void> Function(String text,
      {List<String>? mediaUrls,
      String? mediaType,
      DateTime? scheduledFor}) onSend;
  final void Function(bool)? onTyping;
  final String? replyingTo;
  final VoidCallback? onCancelReply;
  final String? editingMessageId;
  final String? editingInitial;
  final VoidCallback? onCancelEdit;
  final void Function(MediaAttachment)? onMediaSend;
  const MessageInput(
      {super.key,
      required this.conversationId,
      required this.onSend,
      this.onTyping,
      this.replyingTo,
      this.onCancelReply,
      this.editingMessageId,
      this.editingInitial,
      this.onCancelEdit,
      this.onMediaSend});

  @override
  ConsumerState<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends ConsumerState<MessageInput> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  Timer? _typingTimer;
  bool _isUploading = false;
  bool _showMentionPopover = false;
  bool _showHashtagPopover = false;
  String _queryFragment = '';
  bool _showExpressionPanel = false;
  ExpressionPanelTab _expressionTab = ExpressionPanelTab.emoji;
  bool _isRecordingVoice = false;
  double _voiceSlideX = 0;

  @override
  void initState() {
    super.initState();
    if (widget.editingInitial != null) _ctrl.text = widget.editingInitial!;
    _ctrl.addListener(_onChanged);
    _focus.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (_focus.hasFocus && _showExpressionPanel) {
      setState(() => _showExpressionPanel = false);
    }
  }

  @override
  void didUpdateWidget(covariant MessageInput old) {
    super.didUpdateWidget(old);
    if (widget.editingMessageId != old.editingMessageId &&
        widget.editingInitial != null) {
      _ctrl.text = widget.editingInitial ?? '';
      _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
      _focus.requestFocus();
    }
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _ctrl.removeListener(_onChanged);
    _focus.removeListener(_onFocusChanged);
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged() {
    final text = _ctrl.text;
    final selection = _ctrl.selection.baseOffset;
    if (selection < 0) {
      _hidePopovers();
      return;
    }
    final before = text.substring(0, selection);
    final lastAt = before.lastIndexOf('@');
    final lastHash = before.lastIndexOf('#');
    final lastSpace = before.lastIndexOf(' ');
    if (mounted) {
      setState(() {
        if (lastAt > lastSpace && lastAt != -1) {
          _queryFragment = before.substring(lastAt + 1);
          _showMentionPopover = true;
          _showHashtagPopover = false;
        } else if (lastHash > lastSpace && lastHash != -1) {
          _queryFragment = before.substring(lastHash + 1);
          _showHashtagPopover = true;
          _showMentionPopover = false;
        } else {
          _showMentionPopover = false;
          _showHashtagPopover = false;
        }
      });
    }
    widget.onTyping?.call(text.trim().isNotEmpty);
    _typingTimer?.cancel();
    _typingTimer =
        Timer(const Duration(seconds: 2), () => widget.onTyping?.call(false));
  }

  void _hidePopovers() {
    setState(() {
      _showMentionPopover = false;
      _showHashtagPopover = false;
    });
  }

  void _insertAtCursor(String inserted, {int replaceLastWith = 0}) {
    final sel = _ctrl.selection.baseOffset.clamp(0, _ctrl.text.length);
    final before = _ctrl.text.substring(0, sel - replaceLastWith);
    final after = _ctrl.text.substring(sel);
    final newText = before + inserted + after;
    _ctrl.text = newText;
    _ctrl.selection =
        TextSelection.collapsed(offset: (before + inserted).length);
    _focus.requestFocus();
  }

  Future<void> _send({DateTime? scheduledFor}) async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    HapticFeedback.lightImpact();
    _ctrl.clear();
    widget.onTyping?.call(false);
    _hidePopovers();
    await widget.onSend(text, scheduledFor: scheduledFor);
  }

  Future<void> _pickAndUpload(ImageSource source, {bool video = false}) async {
    var effectiveSource = source;
    if (source == ImageSource.camera &&
        !CameraCapability.supportsImagePickerCapture) {
      AppToast.warning(context, CameraCapability.unsupportedCaptureMessage);
      effectiveSource = ImageSource.gallery;
    }
    final picker = ImagePicker();
    final file = video
        ? await picker.pickVideo(source: effectiveSource)
        : await picker.pickImage(source: effectiveSource, imageQuality: 85);
    if (file == null) return;
    if (mounted) setState(() => _isUploading = true);
    try {
      final supa = Supabase.instance.client;
      final uid = supa.auth.currentUser?.id ?? 'anon';
      final path = '$uid/${DateTime.now().millisecondsSinceEpoch}_${file.name}';
      final bytes = await file.readAsBytes();
      await supa.storage.from('chat-media').uploadBinary(path, bytes);
      final url = supa.storage.from('chat-media').getPublicUrl(path);
      await widget.onSend(_ctrl.text.trim(),
          mediaUrls: [url], mediaType: video ? 'video' : 'image');
      _ctrl.clear();
    } catch (e) {
      if (mounted) AppToast.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _toggleExpressionPanel() {
    HapticFeedback.selectionClick();
    setState(() {
      if (_showExpressionPanel) {
        _showExpressionPanel = false;
        _focus.requestFocus();
      } else {
        _showExpressionPanel = true;
        _focus.unfocus();
      }
    });
  }

  void _onExpressionEmojiSelected(String emoji) {
    _insertAtCursor(emoji);
  }

  void _onStickerSelected(MediaAttachment sticker) {
    setState(() => _showExpressionPanel = false);
    widget.onMediaSend?.call(sticker);
  }

  void _onGifSelected(MediaAttachment gif) {
    setState(() => _showExpressionPanel = false);
    if (gif.remoteUrl != null) {
      widget.onSend('', mediaUrls: [gif.remoteUrl!], mediaType: 'gif');
    }
  }

  Future<void> _recordVideoNote() async {
    final result = await VideoNoteRecorder.show(context);
    if (result != null) {
      widget.onMediaSend?.call(result);
    }
  }

  Future<void> _onVoiceLongPressStart(LongPressStartDetails _) async {
    HapticFeedback.heavyImpact();
    final recorder = ref.read(voiceRecorderManagerProvider.notifier);
    final started = await recorder.start();
    if (!started) return;
    setState(() {
      _isRecordingVoice = true;
      _voiceSlideX = 0;
    });
  }

  void _onVoiceLongPressMoveUpdate(LongPressMoveUpdateDetails d) {
    if (!_isRecordingVoice) return;
    setState(() => _voiceSlideX = d.offsetFromOrigin.dx.clamp(-200.0, 0.0));
    if (_voiceSlideX < -100) {
      _cancelVoiceRecording();
    }
  }

  Future<void> _onVoiceLongPressEnd(LongPressEndDetails _) async {
    if (!_isRecordingVoice) return;
    final recorder = ref.read(voiceRecorderManagerProvider.notifier);
    final result = await recorder.stop();
    setState(() => _isRecordingVoice = false);
    if (result != null) {
      final attachment = MediaAttachment(
        type: MediaAttachmentType.voiceNote,
        localPath: result.path,
        mimeType: result.mimeType,
        durationMs: result.duration.inMilliseconds,
        waveform: result.waveform,
      );
      widget.onMediaSend?.call(attachment);
    }
  }

  Future<void> _cancelVoiceRecording() async {
    final recorder = ref.read(voiceRecorderManagerProvider.notifier);
    await recorder.cancel();
    setState(() => _isRecordingVoice = false);
  }

  void _showAttachSheet() {
    final colors = AlsamosColors.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheetCtx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
            leading: const Icon(LucideIcons.image, color: Color(0xFF22C55E)),
            title: const Text('Photo'),
            onTap: () {
              Navigator.pop(sheetCtx);
              _pickAndUpload(ImageSource.gallery);
            }),
        ListTile(
            leading: const Icon(LucideIcons.camera, color: Color(0xFFEAB308)),
            title: const Text('Camera'),
            onTap: () {
              Navigator.pop(sheetCtx);
              _pickAndUpload(ImageSource.camera);
            }),
        ListTile(
            leading: const Icon(LucideIcons.video, color: Color(0xFF3B82F6)),
            title: const Text('Video'),
            onTap: () {
              Navigator.pop(sheetCtx);
              _pickAndUpload(ImageSource.gallery, video: true);
            }),
        ListTile(
            leading: const Icon(LucideIcons.gift, color: Color(0xFFEC4899)),
            title: const Text('GIF'),
            onTap: () {
              Navigator.pop(sheetCtx);
              GifPickerSheet.show(
                  context,
                  (url) =>
                      widget.onSend('', mediaUrls: [url], mediaType: 'gif'));
            }),
        ListTile(
            leading: const Icon(LucideIcons.circle, color: Color(0xFF06B6D4)),
            title: const Text('Video xabar'),
            onTap: () {
              Navigator.pop(sheetCtx);
              _recordVideoNote();
            }),
        ListTile(
            leading: const Icon(LucideIcons.clock, color: Color(0xFF8B5CF6)),
            title: const Text('Schedule message'),
            onTap: () {
              Navigator.pop(sheetCtx);
              ScheduleMessageDialog.show(context,
                  messagePreview: _ctrl.text,
                  onSchedule: (when) => _send(scheduledFor: when));
            }),
      ])),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final hasText = _ctrl.text.trim().isNotEmpty;
    final isEditing = widget.editingMessageId != null;

    // Web: <div className="bg-card p-3 relative z-10">
    return Container(
      decoration: BoxDecoration(
          color: colors.card,
          border: Border(top: BorderSide(color: colors.border))),
      padding: const EdgeInsets.all(12),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Reply Preview — web: mb-2 px-3 py-2 bg-muted/50 rounded-lg border-l-2 border-primary
        if (widget.replyingTo != null && widget.replyingTo!.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
                color: colors.muted.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
                border: Border(left: BorderSide(color: primary, width: 2))),
            child: Row(children: [
              // Web: NO Reply icon — only sender_name + content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // sender_name placeholder (we only have content string)
                    Text('Replying to',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: primary)),
                    Text(widget.replyingTo!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        // Web: text-sm text-muted-foreground truncate
                        style: TextStyle(
                            fontSize: 14, color: colors.mutedForeground)),
                  ],
                ),
              ),
              // Web: h-6 w-6 close button
              SizedBox(
                width: 24,
                height: 24,
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 24, minHeight: 24),
                  icon: Icon(LucideIcons.x,
                      size: 16, color: colors.mutedForeground),
                  onPressed: widget.onCancelReply,
                ),
              ),
            ]),
          ),
        if (isEditing)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
                color: colors.muted.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
                // Amber-500 for editing (web pattern)
                border: Border(
                    left:
                        BorderSide(color: const Color(0xFFF59E0B), width: 2))),
            child: Row(children: [
              const Icon(LucideIcons.pencil,
                  size: 14, color: Color(0xFFF59E0B)),
              const SizedBox(width: 8),
              const Expanded(
                  child: Text('Editing message',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w500))),
              SizedBox(
                width: 24,
                height: 24,
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 24, minHeight: 24),
                  icon: Icon(LucideIcons.x,
                      size: 16, color: colors.mutedForeground),
                  onPressed: () {
                    _ctrl.clear();
                    widget.onCancelEdit?.call();
                  },
                ),
              ),
            ]),
          ),
        // Mention/Hashtag autocomplete popovers
        if (_showMentionPopover && _queryFragment.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(
                color: colors.card,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.border)),
            child: MentionAutocomplete(
                query: _queryFragment,
                onSelect: (u) {
                  _insertAtCursor('$u  ',
                      replaceLastWith: _queryFragment.length);
                  _hidePopovers();
                }),
          ),
        if (_showHashtagPopover && _queryFragment.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(
                color: colors.card,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.border)),
            child: HashtagAutocomplete(
                query: _queryFragment,
                onSelect: (t) {
                  _insertAtCursor('$t ',
                      replaceLastWith: _queryFragment.length);
                  _hidePopovers();
                }),
          ),
        // Web: <div className="flex items-end gap-2">
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          // Attachment button — web: h-10 w-10 Paperclip
          SizedBox(
            width: 40,
            height: 40,
            child: IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              icon: _isUploading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(LucideIcons.paperclip,
                      size: 20, color: colors.mutedForeground),
              onPressed: _isUploading ? null : _showAttachSheet,
            ),
          ),
          const SizedBox(width: 8),
          // Message input — web: w-full px-4 py-2.5 pr-12 rounded-2xl bg-muted/50 border border-border text-sm
          Expanded(
            child: Container(
              // Web: min-h-[44px] max-h-[120px]
              constraints: const BoxConstraints(maxHeight: 120, minHeight: 44),
              decoration: BoxDecoration(
                  color: colors.muted.withValues(alpha: 0.5),
                  // Web: rounded-2xl (16px)
                  borderRadius: BorderRadius.circular(16)),
              padding: const EdgeInsets.symmetric(
                  // Web: px-4 py-2.5 pr-12 (room for emoji icon on right)
                  horizontal: 16,
                  vertical: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    focusNode: _focus,
                    minLines: 1,
                    maxLines: 5,
                    // Web: text-sm (14px)
                    style: const TextStyle(fontSize: 14),
                    decoration: const InputDecoration(
                      hintText: 'Message',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                      isDense: true,
                    ),
                  ),
                ),
                SizedBox(
                  width: 32,
                  height: 32,
                  child: IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                    icon: Icon(
                        _showExpressionPanel
                            ? LucideIcons.keyboard
                            : LucideIcons.smile,
                        size: 18,
                        color: _showExpressionPanel
                            ? primary
                            : colors.mutedForeground),
                    onPressed: _toggleExpressionPanel,
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(width: 8),
          // Send / Mic button — web: h-10 w-10 rounded-full
          if (hasText || isEditing)
            SizedBox(
              width: 40,
              height: 40,
              child: Material(
                color: primary,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => _send(),
                  onLongPress: () {
                    // Web: long-press send to open schedule dialog
                    HapticFeedback.mediumImpact();
                    ScheduleMessageDialog.show(
                      context,
                      messagePreview: _ctrl.text,
                      onSchedule: (when) => _send(scheduledFor: when),
                    );
                  },
                  child: Icon(isEditing ? LucideIcons.check : LucideIcons.send,
                      color: Colors.white, size: 20),
                ),
              ),
            )
          else
            GestureDetector(
              onLongPressStart: _onVoiceLongPressStart,
              onLongPressMoveUpdate: _onVoiceLongPressMoveUpdate,
              onLongPressEnd: _onVoiceLongPressEnd,
              onTap: () {
                HapticFeedback.lightImpact();
                AppToast.info(context, "Ovoz yozish uchun bosib turing");
              },
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _isRecordingVoice
                      ? Colors.red.withValues(alpha: 0.1)
                      : colors.muted,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  LucideIcons.mic,
                  size: 20,
                  color:
                      _isRecordingVoice ? Colors.red : colors.mutedForeground,
                ),
              ),
            ),
        ]),
        if (_isUploading)
          const Padding(
              padding: EdgeInsets.only(top: 6),
              child: LinearProgressIndicator(minHeight: 2)),
        if (_showExpressionPanel)
          ExpressionPanel(
            config: MediaComposerConfig.chat,
            activeTab: _expressionTab,
            onTabChanged: (tab) => setState(() => _expressionTab = tab),
            onEmojiSelected: _onExpressionEmojiSelected,
            onStickerSelected: _onStickerSelected,
            onGifSelected: _onGifSelected,
          ),
      ]),
    );
  }
}

/// Voice mic button with web parity: 40x40 circle, scale-95 active + pulse ring during long-press.
class _VoiceMicButton extends StatefulWidget {
  final Color mutedColor;
  final Color iconColor;
  final Color primary;
  final VoidCallback onTapShowHint;
  final VoidCallback onLongPressStart;
  const _VoiceMicButton({
    required this.mutedColor,
    required this.iconColor,
    required this.primary,
    required this.onTapShowHint,
    required this.onLongPressStart,
  });

  @override
  State<_VoiceMicButton> createState() => _VoiceMicButtonState();
}

class _VoiceMicButtonState extends State<_VoiceMicButton>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;
  bool _recording = false;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTapShowHint,
      onLongPressStart: (_) {
        widget.onLongPressStart();
        setState(() => _recording = true);
        _pulse.repeat(reverse: true);
      },
      onLongPressEnd: (_) {
        setState(() => _recording = false);
        _pulse.stop();
        _pulse.reset();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (_, __) {
            final pulseScale = _recording ? 1.0 + (_pulse.value * 0.15) : 1.0;
            return SizedBox(
              width: 40,
              height: 40,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Web: animate-pulse ring while recording
                  if (_recording)
                    Transform.scale(
                      scale: pulseScale,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                        ),
                      ),
                    ),
                  Material(
                    color: _recording
                        ? const Color(0xFFEF4444)
                        : widget.mutedColor,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: widget.onTapShowHint,
                      child: SizedBox(
                        width: 40,
                        height: 40,
                        child: Icon(
                          LucideIcons.mic,
                          color: _recording ? Colors.white : widget.iconColor,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
