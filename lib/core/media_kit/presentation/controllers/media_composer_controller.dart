import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/composer_result.dart';
import '../../domain/entities/media_attachment.dart';
import '../../domain/entities/media_composer_config.dart';

enum ExpressionPanelTab { emoji, stickers, gif }

class MediaComposerState {
  final String text;
  final List<MediaAttachment> attachments;
  final String? replyToId;
  final String? replyPreviewText;
  final bool isRecordingVoice;
  final bool showExpressionPanel;
  final ExpressionPanelTab activeTab;
  final bool isSending;

  const MediaComposerState({
    this.text = '',
    this.attachments = const [],
    this.replyToId,
    this.replyPreviewText,
    this.isRecordingVoice = false,
    this.showExpressionPanel = false,
    this.activeTab = ExpressionPanelTab.emoji,
    this.isSending = false,
  });

  bool get canSend => text.trim().isNotEmpty || attachments.isNotEmpty;
  bool get hasAttachments => attachments.isNotEmpty;

  MediaComposerState copyWith({
    String? text,
    List<MediaAttachment>? attachments,
    String? replyToId,
    String? replyPreviewText,
    bool? isRecordingVoice,
    bool? showExpressionPanel,
    ExpressionPanelTab? activeTab,
    bool? isSending,
    bool clearReply = false,
  }) {
    return MediaComposerState(
      text: text ?? this.text,
      attachments: attachments ?? this.attachments,
      replyToId: clearReply ? null : (replyToId ?? this.replyToId),
      replyPreviewText:
          clearReply ? null : (replyPreviewText ?? this.replyPreviewText),
      isRecordingVoice: isRecordingVoice ?? this.isRecordingVoice,
      showExpressionPanel: showExpressionPanel ?? this.showExpressionPanel,
      activeTab: activeTab ?? this.activeTab,
      isSending: isSending ?? this.isSending,
    );
  }
}

class MediaComposerController extends StateNotifier<MediaComposerState> {
  final MediaComposerConfig config;
  final TextEditingController textController;
  final FocusNode focusNode;

  MediaComposerController({
    required this.config,
    TextEditingController? textController,
    FocusNode? focusNode,
  })  : textController = textController ?? TextEditingController(),
        focusNode = focusNode ?? FocusNode(),
        super(const MediaComposerState()) {
    this.textController.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (!mounted) return;
    state = state.copyWith(text: textController.text);
  }

  void toggleExpressionPanel([ExpressionPanelTab? tab]) {
    if (state.showExpressionPanel && tab == state.activeTab) {
      state = state.copyWith(showExpressionPanel: false);
      focusNode.requestFocus();
    } else {
      state = state.copyWith(
        showExpressionPanel: true,
        activeTab: tab ?? state.activeTab,
      );
      focusNode.unfocus();
    }
  }

  void hideExpressionPanel() {
    if (state.showExpressionPanel) {
      state = state.copyWith(showExpressionPanel: false);
    }
  }

  void switchTab(ExpressionPanelTab tab) {
    state = state.copyWith(activeTab: tab);
  }

  void insertEmoji(String emoji) {
    final sel = textController.selection;
    final text = textController.text;
    final newText = sel.isValid
        ? text.replaceRange(sel.start, sel.end, emoji)
        : text + emoji;
    textController.text = newText;
    final offset = (sel.isValid ? sel.start : text.length) + emoji.length;
    textController.selection = TextSelection.collapsed(offset: offset);
  }

  void addAttachment(MediaAttachment attachment) {
    state = state.copyWith(
      attachments: [...state.attachments, attachment],
    );
  }

  void removeAttachment(int index) {
    final list = [...state.attachments];
    if (index >= 0 && index < list.length) {
      list.removeAt(index);
      state = state.copyWith(attachments: list);
    }
  }

  void clearAttachments() {
    state = state.copyWith(attachments: []);
  }

  void setReply({required String id, String? previewText}) {
    state = state.copyWith(replyToId: id, replyPreviewText: previewText);
  }

  void clearReply() {
    state = state.copyWith(clearReply: true);
  }

  void setRecordingVoice(bool value) {
    state = state.copyWith(isRecordingVoice: value);
  }

  ComposerResult buildResult() {
    return ComposerResult(
      text: textController.text.trim(),
      attachments: state.attachments,
      replyToId: state.replyToId,
    );
  }

  void reset() {
    textController.clear();
    state = const MediaComposerState();
  }

  @override
  void dispose() {
    textController.removeListener(_onTextChanged);
    textController.dispose();
    focusNode.dispose();
    super.dispose();
  }
}

final mediaComposerProvider = StateNotifierProvider.autoDispose
    .family<MediaComposerController, MediaComposerState, MediaComposerConfig>(
  (ref, config) => MediaComposerController(config: config),
);
