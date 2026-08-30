import 'dart:convert';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import '../../../../app/theme/app_theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../../shared/stories/story_avatar_ring.dart';
import '../../../../shared/widgets/username_qr_dialog.dart';
import '../../../../shared/widgets/verified_badge.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../../../shared/widgets/error_mapper.dart';
import '../../../../shared/services/camera_capability.dart';
import '../../../../shared/audio/speech_audio_config.dart';
import '../../../../shared/audio/wav_speech_processor.dart';
import '../../../../shared/utils/video_controller_lifecycle.dart';
import '../../data/models/conversation_model.dart';
import '../../data/models/message_interaction_model.dart';
import '../../data/models/message_model.dart';
import '../../data/services/chat_media_upload_service.dart';
import '../../data/services/media_settings_service.dart';
import '../providers/conversations_provider.dart';
import '../providers/conversation_notification_settings_provider.dart';
import '../providers/messages_provider.dart';
import '../providers/conversation_admin_provider.dart';
import '../widgets/call_history_message.dart';
import '../widgets/conversation_admin_panel.dart';
import '../widgets/message_bubble.dart';
import '../widgets/composer_extras.dart';
import '../widgets/emoji_picker_sheet.dart';
import '../widgets/canonical_rich_composer.dart';

import '../widgets/pinned_messages_bar.dart';
import '../providers/pinned_messages_provider.dart';
import '../providers/online_status_provider.dart';
import '../widgets/scheduled_messages_sheet.dart';
import '../widgets/message_search_in_conversation.dart';
import '../../../../shared/widgets/gif_picker.dart';
import '../../../../shared/widgets/hashtag_autocomplete.dart';
import '../../../../shared/communication/emoji/animated_emoji.dart';
import 'webrtc_call_page.dart';
import '../../data/models/sticker_model.dart';
import '../widgets/telegram_sticker_picker.dart';
import 'dart:io' show File;
import 'package:file_picker/file_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:record/record.dart';
import 'dart:async';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:image/image.dart' as img;
import '../../../../shared/widgets/mention_autocomplete.dart';
import '../../../../core/services/app_analytics_service.dart';
import 'package:latlong2/latlong.dart';
import '../widgets/location_share_button.dart'
    show SharedLocation, LocationPickerScreen;
import '../widgets/shared_location_history_sheet.dart';
import '../widgets/chat_wallpaper.dart';
import '../../../settings/presentation/pages/chat_wallpaper_settings_page.dart';

/// Pixel-perfect Flutter port of web `MessagesPage.tsx` chat view
/// — ChatHeader + reply preview + attachment menu + voice UI +
/// date dividers + long-press reactions + edit/delete.
class ChatPage extends ConsumerStatefulWidget {
  final String conversationId;
  final Conversation? conversation;

  /// When true, chat is rendered inside the desktop 2-pane layout (no back arrow).
  final bool embedded;
  const ChatPage({
    super.key,
    required this.conversationId,
    this.conversation,
    this.embedded = false,
  });

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

final Map<String, String> chatDrafts = {};
final Map<String, String> pendingMessageHighlights = {};

class _SendMessageIntent extends Intent {
  const _SendMessageIntent();
}

class _ChatPageState extends ConsumerState<ChatPage>
    with SingleTickerProviderStateMixin {
  final _controller = CanonicalRichComposerController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  bool _hasText = false;
  bool _recordingMedia = false;
  bool _isMediaVideoMode = false;
  bool _showScrollToBottom = false;
  bool _showMessageSearch = false;
  String _messageSearchInitialQuery = '';
  String? _highlightedMessageId;

  // Selection mode (web isSelectionMode, selectedMessages)
  bool _isSelectionMode = false;
  final Set<String> _selectedMessages = {};

  // v33: hashtag/mention autocomplete state (web `HashtagAutocomplete`/`MentionAutocomplete`)
  String? _hashtagQuery; // null = yopiq, '' = trending list
  String? _mentionQuery; // null = yopiq
  int _tokenStart = -1; // # yoki @ belgisining boshlanish index'i
  Duration _voiceDuration = Duration.zero;
  AnimationController? _recPulse;

  final _audioRecorder = AudioRecorder();
  final _tts = FlutterTts();
  Timer? _recordTimer;
  Timer? _amplitudeTimer;
  final List<int> _liveWaveform = [];
  Timer? _typingStopTimer;
  Timer? _draftSyncTimer;
  Timer? _highlightTimer;
  bool _typingSent = false;
  late final MessagesNotifier _messagesNotifier;
  final Map<String, _UploadTask> _uploads = {};
  String? _savedTagFilter;
  bool _edgeSwipeActive = false;
  double _edgeSwipeProgress = 0;
  bool _nextUnreadNavigationQueued = false;
  Conversation? _resolvedConversation;
  bool _resolvingConversation = false;
  bool _conversationResolveScheduled = false;
  bool _draftTouched = false;
  bool _suppressDraftPersistence = false;
  bool _editingComposer = false;
  String? _draftBeforeEditTransport;

  @override
  void initState() {
    super.initState();
    _messagesNotifier =
        ref.read(messagesProvider(widget.conversationId).notifier);
    final initialDraft =
        chatDrafts[widget.conversationId] ?? widget.conversation?.draft;
    if (initialDraft?.trim().isNotEmpty == true) {
      _controller.setTransportText(initialDraft!);
      _hasText = true;
      chatDrafts[widget.conversationId] = initialDraft;
    }
    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
      _sendTypingSignal(has);
      if (!_suppressDraftPersistence && !_editingComposer) {
        _draftTouched = true;
        _scheduleDraftSync();
      }
      _updateAutocomplete();
    });
    _focusNode.addListener(_onInputFocusChanged);
    // Scroll listener for scroll-to-bottom button
    _scrollController.addListener(_onScroll);
    // Initialize recording pulse animation
    _recPulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    _scheduleConversationResolve();
  }

  @override
  void didUpdateWidget(covariant ChatPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversationId != widget.conversationId) {
      _resolvedConversation = null;
      _resolvingConversation = false;
      _conversationResolveScheduled = false;
      _scheduleConversationResolve();
    }
  }

  void _scheduleConversationResolve() {
    if (_conversationResolveScheduled || _resolvingConversation) return;
    if (widget.conversation != null) return;
    _conversationResolveScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _conversationResolveScheduled = false;
      if (mounted) _resolveConversationIfNeeded();
    });
  }

  void _hydrateDraftFromConversation(Conversation conversation) {
    if (_draftTouched || _controller.text.trim().isNotEmpty) return;
    final draft = conversation.draft;
    if (draft?.trim().isNotEmpty != true) return;

    _suppressDraftPersistence = true;
    _controller.setTransportText(draft!);
    _suppressDraftPersistence = false;
    chatDrafts[widget.conversationId] = draft;
    if (mounted) setState(() => _hasText = true);
  }

  Future<void> _resolveConversationIfNeeded() async {
    if (_resolvingConversation) return;
    if (widget.conversation != null) return;
    if (_resolvedConversation?.id == widget.conversationId) return;

    final cached = ref
        .read(conversationsProvider)
        .valueOrNull
        ?.where((conversation) => conversation.id == widget.conversationId)
        .firstOrNull;
    if (cached != null) {
      if (mounted) {
        setState(() => _resolvedConversation = cached);
        _hydrateDraftFromConversation(cached);
      }
      return;
    }

    final userId = ref.read(authProvider).user?.id;
    if (userId == null) return;

    if (mounted) setState(() => _resolvingConversation = true);
    try {
      final conversations =
          await ref.read(messagesRepositoryProvider).fetchConversations(userId);
      final resolved = conversations
          .where((conversation) => conversation.id == widget.conversationId)
          .firstOrNull;
      if (!mounted) return;
      if (resolved != null) {
        setState(() => _resolvedConversation = resolved);
        _hydrateDraftFromConversation(resolved);
      }
    } catch (e) {
      debugPrint('[ChatPage] Could not resolve conversation header: $e');
    } finally {
      if (mounted) {
        setState(() => _resolvingConversation = false);
      } else {
        _resolvingConversation = false;
      }
    }
  }

  void _onInputFocusChanged() {
    if (mounted) setState(() {});
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final distanceFromBottom = _scrollController.position.pixels;
    // Show button when more than 200px from bottom (reverse list: pixels = 0 is bottom)
    final shouldShow = distanceFromBottom > 200;
    if (shouldShow != _showScrollToBottom) {
      setState(() => _showScrollToBottom = shouldShow);
    }
  }

  bool _canStartBackSwipe(DragStartDetails details) {
    if (widget.embedded || _isSelectionMode) return false;
    if (_focusNode.hasFocus) return false;
    return details.localPosition.dx <= 36;
  }

  void _handleBackSwipeStart(DragStartDetails details) {
    if (!_canStartBackSwipe(details)) return;
    setState(() {
      _edgeSwipeActive = true;
      _edgeSwipeProgress = 0;
    });
  }

  void _handleBackSwipeUpdate(DragUpdateDetails details) {
    if (!_edgeSwipeActive) return;
    final next = (_edgeSwipeProgress + (details.primaryDelta ?? 0))
        .clamp(0.0, 140.0)
        .toDouble();
    if (next != _edgeSwipeProgress) {
      setState(() => _edgeSwipeProgress = next);
    }
  }

  void _handleBackSwipeEnd([DragEndDetails? details]) {
    if (!_edgeSwipeActive) return;
    final shouldPop = _edgeSwipeProgress >= 72;
    setState(() {
      _edgeSwipeActive = false;
      _edgeSwipeProgress = 0;
    });
    if (shouldPop) {
      Navigator.of(context).maybePop();
    }
  }

  Conversation? _nextUnreadChannel(List<Conversation> conversations) {
    if (conversations.isEmpty) return null;
    final channels = conversations
        .where((conversation) =>
            conversation.type == 'channel' && !conversation.isArchived)
        .toList();
    if (channels.isEmpty) return null;
    final currentIndex = channels
        .indexWhere((conversation) => conversation.id == widget.conversationId);
    final ordered = <Conversation>[
      if (currentIndex >= 0) ...channels.skip(currentIndex + 1),
      if (currentIndex >= 0) ...channels.take(currentIndex),
      if (currentIndex < 0) ...channels,
    ];
    for (final conversation in ordered) {
      if (conversation.hasUnread && !conversation.isMutedEffective) {
        return conversation;
      }
    }
    return null;
  }

  void _openNextUnreadChannel(Conversation conversation) {
    if (!mounted || _nextUnreadNavigationQueued) return;
    _nextUnreadNavigationQueued = true;
    ref
        .read(conversationsProvider.notifier)
        .markReadLocally(widget.conversationId);
    context
        .push('/messages/${conversation.id}', extra: conversation)
        .whenComplete(
      () {
        if (mounted) _nextUnreadNavigationQueued = false;
      },
    );
  }

  // ignore: unused_element
  String _mediaTitle(Message message) {
    final type = message.mediaType;
    final text = message.content?.trim();
    if (text != null && text.isNotEmpty && !text.startsWith('🎤')) return text;
    if (type == 'voice') return 'Ovozli xabar';
    if (type == 'audio') return 'Audio';
    if (type == 'video_note') return 'Video xabar';
    if (type == 'video') return 'Video';
    return 'Media';
  }

  @override
  void dispose() {
    final text = _editingComposer
        ? (_draftBeforeEditTransport ?? '').trim()
        : _controller.transportText.trim();
    if (text.isNotEmpty) {
      chatDrafts[widget.conversationId] = text;
    } else {
      chatDrafts.remove(widget.conversationId);
    }
    _focusNode.removeListener(_onInputFocusChanged);
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _recPulse?.dispose();
    _recordTimer?.cancel();
    _amplitudeTimer?.cancel();
    _typingStopTimer?.cancel();
    _draftSyncTimer?.cancel();
    _highlightTimer?.cancel();
    _messagesNotifier.syncDraft(text);
    if (_typingSent) {
      _messagesNotifier.sendTyping(false);
      _typingSent = false;
    }
    _audioRecorder.dispose();
    _tts.stop();
    super.dispose();
  }

  Future<void> _speakMessage(String text) async {
    final value = text.trim();
    if (value.isEmpty) return;
    await _tts.setLanguage('uz-UZ');
    await _tts.setSpeechRate(0.48);
    await _tts.speak(value);
  }

  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final dir = await getTemporaryDirectory();
        final path =
            '${dir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.wav';
        await _audioRecorder.start(
          SpeechAudioConfig.voiceRecordConfig,
          path: path,
        );
        setState(() {
          _recordingMedia = true;
          _isMediaVideoMode = false;
          _voiceDuration = Duration.zero;
          _liveWaveform
            ..clear()
            ..addAll(List<int>.filled(12, 18));
        });
        _recPulse?.repeat(reverse: true);
        _recordTimer?.cancel();
        _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          setState(() {
            _voiceDuration = Duration(seconds: timer.tick);
          });
        });
        _amplitudeTimer?.cancel();
        _amplitudeTimer =
            Timer.periodic(const Duration(milliseconds: 120), (_) async {
          try {
            final amplitude = await _audioRecorder.getAmplitude();
            final normalized =
                (((amplitude.current + 60) / 60) * 88 + 12).round();
            if (!mounted || !_recordingMedia) return;
            setState(() {
              _liveWaveform.add(normalized.clamp(12, 100));
              if (_liveWaveform.length > 48) _liveWaveform.removeAt(0);
            });
          } catch (_) {
            // Amplitude is best-effort on some desktop/web codecs.
          }
        });
      } else {
        if (!mounted) return;
        AppToast.error(context, "Mikrofon ruxsati yo'q");
      }
    } catch (e) {
      debugPrint('Start recording error: $e');
    }
  }

  Future<_ChatUploadResult> _uploadChatMediaResult(
    Uint8List bytes,
    String path, {
    String? contentType,
    String? taskId,
  }) async {
    final sb = Supabase.instance.client;
    Object? firstError;
    if (taskId != null) _setUploadProgress(taskId, 0.08);
    final safePath = path
        .replaceAll(RegExp(r'[^a-zA-Z0-9_\-./]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final normalizedContentType =
        _normalizeUploadContentType(contentType, safePath);
    for (final bucket in const ['chat-media', 'message-attachments']) {
      try {
        if (taskId != null && _uploads[taskId]?.cancelled == true) {
          throw const _UploadCancelled();
        }
        if (taskId != null) _setUploadProgress(taskId, 0.22);
        await sb.storage.from(bucket).uploadBinary(
              safePath,
              bytes,
              fileOptions: FileOptions(
                contentType: normalizedContentType,
                upsert: false,
              ),
            );
        if (taskId != null && _uploads[taskId]?.cancelled == true) {
          throw const _UploadCancelled();
        }
        if (taskId != null) _setUploadProgress(taskId, 0.86);
        String url;
        try {
          url = await sb.storage.from(bucket).createSignedUrl(
                safePath,
                60 * 60,
              );
        } catch (error) {
          debugPrint(
            '[ChatPage] signed media url failed for $bucket/$safePath: $error',
          );
          url = sb.storage.from(bucket).getPublicUrl(safePath);
        }
        return _ChatUploadResult(
          url: url,
          bucket: bucket,
          path: safePath,
          contentType: normalizedContentType,
        );
      } catch (e) {
        firstError ??= e;
        final message = e.toString().toLowerCase();
        final canTryNext = bucket != 'message-attachments' &&
            (message.contains('bucket not found') ||
                message.contains('404') ||
                message.contains('invalid_mime_type') ||
                message.contains('mime type') ||
                message.contains('415'));
        if (!canTryNext) {
          rethrow;
        }
      }
    }
    throw firstError ?? StateError('Media upload failed');
  }

  Future<String> _uploadChatMedia(
    Uint8List bytes,
    String path, {
    String? contentType,
    String? taskId,
  }) async {
    final uploaded = await _uploadChatMediaResult(
      bytes,
      path,
      contentType: contentType,
      taskId: taskId,
    );
    return uploaded.url;
  }

  String _beginUpload(String label, Future<void> Function() retry) {
    final id = 'up-${DateTime.now().microsecondsSinceEpoch}';
    setState(() {
      _uploads[id] = _UploadTask(id: id, label: label, retry: retry);
    });
    return id;
  }

  void _setUploadProgress(String id, double progress) {
    if (!mounted) return;
    final task = _uploads[id];
    if (task == null) return;
    setState(() => _uploads[id] = task.copyWith(progress: progress));
  }

  void _finishUpload(String id) {
    if (!mounted) return;
    setState(() => _uploads.remove(id));
  }

  void _failUpload(String id, Object error) {
    if (!mounted) return;
    final task = _uploads[id];
    if (task == null) return;
    setState(() => _uploads[id] = task.copyWith(error: error.toString()));
  }

  void _cancelUpload(String id) {
    final task = _uploads[id];
    if (task == null) return;
    setState(() => _uploads[id] = task.copyWith(cancelled: true));
  }

  String _contentTypeForFile(String name) {
    final ext = name.split('.').last.toLowerCase();
    return switch (ext) {
      'jpg' || 'jpeg' || 'jpe' => 'image/jpeg',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'heic' => 'image/heic',
      'heif' => 'image/heif',
      'mp4' || 'm4v' => 'video/mp4',
      'mov' => 'video/quicktime',
      'webm' => 'video/webm',
      'm4a' => 'audio/mp4',
      'mp3' => 'audio/mpeg',
      'wav' => 'audio/wav',
      'pdf' => 'application/pdf',
      'txt' => 'text/plain',
      _ => 'application/octet-stream',
    };
  }

  String _normalizeUploadContentType(String? contentType, String path) {
    final lower = (contentType ?? '').trim().toLowerCase();
    if (lower == 'image/jpg' || lower == 'image/pjpeg') return 'image/jpeg';
    if (lower == 'video/x-m4v') return 'video/mp4';
    if (lower == 'audio/x-m4a' || lower == 'audio/m4a') return 'audio/mp4';
    if (lower.isNotEmpty && lower != 'application/octet-stream') return lower;
    return _contentTypeForFile(path);
  }

  Future<void> _stopAndSendRecording() async {
    _recordTimer?.cancel();
    _amplitudeTimer?.cancel();
    _recPulse?.stop();
    final path = await _audioRecorder.stop();
    final secs = _voiceDuration.inSeconds;
    final waveform = List<int>.from(_liveWaveform);
    setState(() {
      _recordingMedia = false;
      _voiceDuration = Duration.zero;
      _liveWaveform.clear();
    });

    if (path != null && secs > 0) {
      try {
        final file = File(path);
        WavProcessingResult? processing;
        try {
          processing = await const WavSpeechProcessor().normalizeFile(path);
        } catch (e) {
          debugPrint('[ChatPage] voice normalization skipped: $e');
        }
        final bytes = await file.readAsBytes();
        await ref.read(messagesProvider(widget.conversationId).notifier).send(
          '',
          mediaType: 'voice',
          metadata: {
            'local_media_path': path,
            'duration_ms': secs * 1000,
            'waveform': waveform.isEmpty
                ? ChatMediaUploadService.waveformFromBytes(bytes)
                : waveform,
            'size_bytes': bytes.length,
            'mime_type': 'audio/wav',
            if (processing != null) ...{
              'audio_processing': {
                'target_lufs': SpeechAudioConfig.targetLufs,
                'true_peak_ceiling_dbfs': SpeechAudioConfig.truePeakCeilingDbfs,
                'max_gain_db': SpeechAudioConfig.maxNormalizationGainDb,
                'applied_gain_db': processing.appliedGainDb,
                'normalized': processing.normalized,
                'before': {
                  'peak_dbfs': processing.before.peakDbfs,
                  'rms_dbfs': processing.before.rmsDbfs,
                  'lufs': processing.before.integratedLufs,
                  'noise_floor_dbfs': processing.before.noiseFloorDbfs,
                  'clipped_samples': processing.before.clippedSamples,
                },
                'after': {
                  'peak_dbfs': processing.after.peakDbfs,
                  'rms_dbfs': processing.after.rmsDbfs,
                  'lufs': processing.after.integratedLufs,
                  'noise_floor_dbfs': processing.after.noiseFloorDbfs,
                  'clipped_samples': processing.after.clippedSamples,
                },
              },
            },
            'upload_progress': 0.02,
          },
        );
      } catch (e) {
        if (!mounted) return;
        AppToast.error(context, friendlyError(e));
      }
    }
  }

  Future<void> _cancelRecording() async {
    _recordTimer?.cancel();
    _amplitudeTimer?.cancel();
    _recPulse?.stop();
    await _audioRecorder.stop();
    setState(() {
      _recordingMedia = false;
      _voiceDuration = Duration.zero;
      _liveWaveform.clear();
    });
  }

  // Selection mode handlers (web handleEnterSelectionMode, handleExitSelectionMode, handleSelectMessage)
  void _enterSelectionMode(String messageId) {
    HapticFeedback.mediumImpact();
    setState(() {
      _isSelectionMode = true;
      _selectedMessages.clear();
      _selectedMessages.add(messageId);
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedMessages.clear();
    });
  }

  void _toggleMessageSelection(String messageId) {
    setState(() {
      if (_selectedMessages.contains(messageId)) {
        _selectedMessages.remove(messageId);
      } else {
        _selectedMessages.add(messageId);
      }
    });
  }

  void _forwardSelected() {
    final state = ref.read(messagesProvider(widget.conversationId));
    final selectedMsgs =
        state.messages.where((m) => _selectedMessages.contains(m.id)).toList();
    selectedMsgs.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    _exitSelectionMode();
    _showForwardDialog(selectedMsgs);
  }

  void _deleteSelected() async {
    final state = ref.read(messagesProvider(widget.conversationId));
    final userId = ref.read(authProvider).user?.id;
    final mySelectedMessages = state.messages
        .where((m) => _selectedMessages.contains(m.id) && m.senderId == userId)
        .toList();

    if (mySelectedMessages.isEmpty) {
      AppToast.error(
          context, 'Faqat o\'z xabarlaringizni o\'chirishingiz mumkin');
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${mySelectedMessages.length} ta xabarni o\'chirish?'),
        content: const Text('Bu amalni qaytarib bo\'lmaydi.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Bekor')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("O'chirish", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (ok == true) {
      for (final msg in mySelectedMessages) {
        await ref
            .read(messagesProvider(widget.conversationId).notifier)
            .delete(msg.id);
      }
      _exitSelectionMode();
    }
  }

  void _showForwardDialog(List<Message> messages) {
    final convos = ref.read(conversationsProvider).valueOrNull ?? [];
    final captionCtrl = TextEditingController();
    final selected = <String>{};
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final c = AlsamosColors.of(ctx);
        return StatefulBuilder(builder: (ctx, setSheetState) {
          Future<void> submit() async {
            if (selected.isEmpty) return;
            await ref
                .read(messagesProvider(widget.conversationId).notifier)
                .forwardMessages(
                  messageIds: messages.map((message) => message.id).toList(),
                  conversationIds: selected.toList(),
                  caption: captionCtrl.text.trim(),
                );
            captionCtrl.dispose();
            if (ctx.mounted) Navigator.pop(ctx);
            if (context.mounted) {
              AppToast.success(
                  context, '${selected.length} ta suhbatga uzatildi');
            }
          }

          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.78),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                  child: Row(children: [
                    const Icon(LucideIcons.share2, size: 18),
                    const SizedBox(width: 8),
                    Text("${messages.length} ta xabarni yo'naltirish",
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    IconButton(
                        icon: const Icon(LucideIcons.x),
                        onPressed: () {
                          captionCtrl.dispose();
                          Navigator.pop(ctx);
                        }),
                  ]),
                ),
                if (convos.isNotEmpty)
                  SizedBox(
                    height: 86,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      scrollDirection: Axis.horizontal,
                      itemCount: convos.take(8).length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (_, i) {
                        final conv = convos[i];
                        final active = selected.contains(conv.id);
                        return InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => setSheetState(() {
                            active
                                ? selected.remove(conv.id)
                                : selected.add(conv.id);
                          }),
                          child: SizedBox(
                            width: 64,
                            child: Column(
                              children: [
                                Stack(children: [
                                  StoryAvatarRing(
                                    userId: conv.otherParticipant?.id,
                                    avatarUrl: conv.displayAvatar,
                                    fallback: conv.initial,
                                    size: 48,
                                  ),
                                  if (active)
                                    Positioned(
                                      right: 0,
                                      bottom: 0,
                                      child: CircleAvatar(
                                        radius: 10,
                                        backgroundColor:
                                            Theme.of(ctx).colorScheme.primary,
                                        child: Icon(LucideIcons.check,
                                            size: 12,
                                            color: Theme.of(ctx)
                                                .colorScheme
                                                .onPrimary),
                                      ),
                                    ),
                                ]),
                                const SizedBox(height: 4),
                                Text(conv.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                Divider(color: c.border, height: 1),
                Expanded(
                  child: convos.isEmpty
                      ? Center(
                          child: Text('Suhbatlar yo\'q',
                              style: TextStyle(color: c.mutedForeground)))
                      : ListView.builder(
                          itemCount: convos.length,
                          itemBuilder: (_, i) {
                            final conv = convos[i];
                            final active = selected.contains(conv.id);
                            return CheckboxListTile(
                              value: active,
                              onChanged: (_) => setSheetState(() {
                                active
                                    ? selected.remove(conv.id)
                                    : selected.add(conv.id);
                              }),
                              secondary: StoryAvatarRing(
                                userId: conv.otherParticipant?.id,
                                avatarUrl: conv.displayAvatar,
                                fallback: conv.initial,
                                size: 40,
                              ),
                              title: Text(conv.title,
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(conv.type,
                                  style: TextStyle(
                                      fontSize: 12, color: c.mutedForeground)),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                      16, 10, 16, 12 + MediaQuery.of(ctx).viewInsets.bottom),
                  child: Row(children: [
                    Expanded(
                      child: TextField(
                        controller: captionCtrl,
                        minLines: 1,
                        maxLines: 3,
                        decoration: InputDecoration(
                          hintText: 'Caption qo\'shish...',
                          isDense: true,
                          filled: true,
                          fillColor: c.muted,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed: selected.isEmpty ? null : submit,
                      icon: const Icon(LucideIcons.send, size: 16),
                      label: const Text('Uzatish'),
                    ),
                  ]),
                ),
              ]),
            ),
          );
        });
      },
    );
  }

  // v33: kursor oldidagi `#tag` yoki `@user` token'ini topadi.
  void _updateAutocomplete() {
    final text = _controller.text;
    final sel = _controller.selection;
    final caret = sel.isValid ? sel.start : text.length;
    int start = caret - 1;
    while (start >= 0) {
      final ch = text[start];
      if (ch == '#' || ch == '@') break;
      if (ch == ' ' || ch == '\n' || ch == '\t') {
        start = -1;
        break;
      }
      start--;
    }
    if (start < 0) {
      if (_hashtagQuery != null || _mentionQuery != null) {
        setState(() {
          _hashtagQuery = null;
          _mentionQuery = null;
          _tokenStart = -1;
        });
      }
      return;
    }
    // Token boshi so'z chegarasi (start-1 bo'sh joy yoki matn boshi) bo'lishi shart.
    if (start > 0) {
      final prev = text[start - 1];
      if (prev != ' ' && prev != '\n' && prev != '\t') {
        if (_hashtagQuery != null || _mentionQuery != null) {
          setState(() {
            _hashtagQuery = null;
            _mentionQuery = null;
            _tokenStart = -1;
          });
        }
        return;
      }
    }
    final marker = text[start];
    final query = text.substring(start + 1, caret);
    // Faqat `[a-zA-Z0-9_]` belgilarini ruxsat etamiz.
    if (query.contains(RegExp(r'[^a-zA-Z0-9_]'))) {
      if (_hashtagQuery != null || _mentionQuery != null) {
        setState(() {
          _hashtagQuery = null;
          _mentionQuery = null;
          _tokenStart = -1;
        });
      }
      return;
    }
    setState(() {
      _tokenStart = start;
      if (marker == '#') {
        _hashtagQuery = query;
        _mentionQuery = null;
      } else {
        _mentionQuery = query;
        _hashtagQuery = null;
      }
    });
  }

  void _applyAutocomplete(String token, String prefix) {
    if (_tokenStart < 0) return;
    final text = _controller.text;
    final caret = _controller.selection.isValid
        ? _controller.selection.start
        : text.length;
    final before = text.substring(0, _tokenStart);
    final after = text.substring(caret);
    final insert = '$prefix$token ';
    final newText = '$before$insert$after';
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: before.length + insert.length),
    );
    setState(() {
      _hashtagQuery = null;
      _mentionQuery = null;
      _tokenStart = -1;
    });
  }

  void _openHashtagSearch(String tag) {
    setState(() {
      _messageSearchInitialQuery = '#$tag';
      _showMessageSearch = true;
    });
  }

  void _closeAutocomplete() {
    setState(() {
      _hashtagQuery = null;
      _mentionQuery = null;
      _tokenStart = -1;
    });
  }

  void _clearComposerDraftAfterSend() {
    _draftSyncTimer?.cancel();
    _draftTouched = true;
    _suppressDraftPersistence = true;
    _controller.clearRich();
    _suppressDraftPersistence = false;
    chatDrafts.remove(widget.conversationId);

    // Clear immediately when the message is accepted into the local outbox.
    // This is offline-safe and does not wait for network delivery.
    unawaited(_messagesNotifier.syncDraft(''));

    if (mounted) {
      setState(() {
        _hasText = false;
        _hashtagQuery = null;
        _mentionQuery = null;
        _tokenStart = -1;
      });
    }
  }

  void _send() {
    HapticFeedback.lightImpact();
    final text = _controller.transportText.trim();
    if (text.isEmpty) return;
    final wasEditing = _editingComposer;
    _sendTypingSignal(false, force: true);
    unawaited(
      ref.read(messagesProvider(widget.conversationId).notifier).send(text),
    );
    if (wasEditing) {
      _restoreDraftAfterEdit();
    } else {
      _clearComposerDraftAfterSend();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(0,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _showSendOptions() async {
    if (_editingComposer) {
      _send();
      return;
    }
    final text = _controller.transportText.trim();
    if (text.isEmpty) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final c = AlsamosColors.of(ctx);
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: c.border),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                leading: const Icon(LucideIcons.bellOff),
                title: const Text('Silent yuborish'),
                onTap: () => Navigator.pop(ctx, 'silent'),
              ),
              ListTile(
                leading: const Icon(LucideIcons.calendarClock),
                title: const Text('Rejalashtirish'),
                onTap: () => Navigator.pop(ctx, 'schedule'),
              ),
            ]),
          ),
        );
      },
    );
    if (!mounted || choice == null) return;
    if (choice == 'silent') {
      await ref
          .read(messagesProvider(widget.conversationId).notifier)
          .scheduleMessage(text, DateTime.now(), isSilent: true);
      _clearComposerDraftAfterSend();
      return;
    }
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(minutes: 5)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (!mounted || date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
          DateTime.now().add(const Duration(minutes: 5))),
    );
    if (!mounted || time == null) return;
    final scheduledFor =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    await ref
        .read(messagesProvider(widget.conversationId).notifier)
        .scheduleMessage(text, scheduledFor);
    _clearComposerDraftAfterSend();
  }

  void _scheduleDraftSync() {
    if (_editingComposer) return;
    final text = _controller.transportText;
    if (text.trim().isNotEmpty) {
      chatDrafts[widget.conversationId] = text;
    } else {
      chatDrafts.remove(widget.conversationId);
    }
    _draftSyncTimer?.cancel();
    _draftSyncTimer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      ref
          .read(messagesProvider(widget.conversationId).notifier)
          .syncDraft(text);
    });
  }

  void _sendTypingSignal(bool isTyping, {bool force = false}) {
    if (!mounted && !force) return;
    _typingStopTimer?.cancel();
    if (isTyping) {
      if (!_typingSent || force) {
        _messagesNotifier.sendTyping(true);
        _typingSent = true;
      }
      _typingStopTimer = Timer(const Duration(milliseconds: 1800), () {
        if (!_typingSent) return;
        _messagesNotifier.sendTyping(false);
        _typingSent = false;
      });
      return;
    }
    if (_typingSent || force) {
      _messagesNotifier.sendTyping(false);
      _typingSent = false;
    }
  }

  void _onReply(Message m) {
    ref.read(messagesProvider(widget.conversationId).notifier).setReplyTo(m.id);
    _focusNode.requestFocus();
  }

  void _onEdit(Message m) {
    _draftBeforeEditTransport ??= _controller.transportText;
    _editingComposer = true;
    _suppressDraftPersistence = true;
    _controller.setTransportText(m.content ?? '');
    _suppressDraftPersistence = false;
    ref.read(messagesProvider(widget.conversationId).notifier).setEditing(m.id);
    setState(() => _hasText = _controller.text.trim().isNotEmpty);
    _focusNode.requestFocus();
  }

  void _restoreDraftAfterEdit() {
    final draft = _draftBeforeEditTransport ?? '';
    _editingComposer = false;
    _draftBeforeEditTransport = null;
    _suppressDraftPersistence = true;
    _controller.setTransportText(draft);
    _suppressDraftPersistence = false;

    if (draft.trim().isNotEmpty) {
      chatDrafts[widget.conversationId] = draft;
    } else {
      chatDrafts.remove(widget.conversationId);
    }

    if (mounted) {
      setState(() => _hasText = _controller.text.trim().isNotEmpty);
    }
  }

  void _cancelEditingComposer() {
    ref.read(messagesProvider(widget.conversationId).notifier).setEditing(null);
    _restoreDraftAfterEdit();
  }

  Future<void> _showEditHistory(Message m) async {
    final rows =
        await ref.read(messagesRepositoryProvider).fetchEditHistory(m.id);
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final c = AlsamosColors.of(ctx);
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(12),
            constraints:
                BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.58),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: c.border),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(children: [
                  const Icon(LucideIcons.history, size: 18),
                  const SizedBox(width: 8),
                  const Text('Oldingi versiyalar',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(LucideIcons.x, size: 18),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ]),
              ),
              Divider(height: 1, color: c.border),
              Flexible(
                child: rows.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text('Tarix topilmadi',
                              style: TextStyle(color: c.mutedForeground)),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: rows.length,
                        separatorBuilder: (_, __) =>
                            Divider(height: 1, color: c.border),
                        itemBuilder: (_, i) {
                          final row = rows[i];
                          final content = '${row['previous_content'] ?? ''}';
                          final editedAt = DateTime.tryParse(
                              '${row['edited_at'] ?? row['created_at'] ?? ''}');
                          return ListTile(
                            title: Text(content,
                                maxLines: 3, overflow: TextOverflow.ellipsis),
                            subtitle: editedAt == null
                                ? null
                                : Text(DateFormat('dd.MM.yyyy HH:mm')
                                    .format(editedAt.toLocal())),
                          );
                        },
                      ),
              ),
            ]),
          ),
        );
      },
    );
  }

  void _onDelete(Message m) async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text("Xabarni o'chirish?"),
              content: const Text('Bu amalni qaytarib bo\'lmaydi.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Bekor')),
                TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text("O'chirish",
                        style: TextStyle(color: Colors.red))),
              ],
            ));
    if (ok == true) {
      ref.read(messagesProvider(widget.conversationId).notifier).delete(m.id);
    }
  }

  void _onReact(Message m, String emoji) {
    ref
        .read(messagesProvider(widget.conversationId).notifier)
        .react(m.id, emoji);
  }

  void _showReactionUsers(MessageReactionGroup group) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final c = AlsamosColors.of(ctx);
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(12),
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.52,
            ),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: c.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.16),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                  child: Row(
                    children: [
                      Text(group.emoji, style: const TextStyle(fontSize: 22)),
                      const SizedBox(width: 8),
                      Text(
                        '${group.count} ta reaksiya',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(LucideIcons.x, size: 18),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: c.border),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: group.users.length,
                    itemBuilder: (_, i) {
                      final user = group.users[i];
                      return ListTile(
                        dense: true,
                        leading: StoryAvatarRing(
                          userId: user.userId,
                          avatarUrl: user.avatarUrl,
                          fallback: (user.name ?? '').isNotEmpty
                              ? user.name![0].toUpperCase()
                              : 'U',
                          size: 36,
                        ),
                        title: Text(
                          user.name ?? 'User',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Text(group.emoji,
                            style: const TextStyle(fontSize: 18)),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ignore: unused_element
  void _onLongPress(Message m, bool isMine, Offset position) async {
    HapticFeedback.mediumImpact();
    final text = m.content ?? '';
    final hasLink = RegExp(r'https?://\S+').hasMatch(text);
    final isMedia = m.mediaUrl != null;
    final isImage = m.mediaType == 'image' || m.mediaType == 'gif';
    final isVideo = m.mediaType == 'video' || m.mediaType == 'video_note';
    final isAudio = m.mediaType == 'audio' || m.mediaType == 'voice';

    final actions = <_MessageMenuAction>[
      _MessageMenuAction('reply', LucideIcons.cornerUpLeft, 'Javob yozish'),
      if (text.isNotEmpty)
        _MessageMenuAction('copy', LucideIcons.copy, 'Nusxalash'),
      if (isAudio)
        _MessageMenuAction('save_notifications', LucideIcons.music,
            'Bildirishnomalar uchun saqlash'),
      if (isImage)
        _MessageMenuAction(
            'save_media', LucideIcons.download, 'Rasmni saqlash'),
      if (isVideo)
        _MessageMenuAction(
            'save_media', LucideIcons.download, 'Videoni saqlash'),
      if (!isMedia && text.isNotEmpty)
        _MessageMenuAction('speak', LucideIcons.messageSquare, 'Gapirish'),
      if (text.isNotEmpty)
        _MessageMenuAction('translate', LucideIcons.languages, 'Tarjima'),
      if (isAudio)
        _MessageMenuAction('transcribe', LucideIcons.fileAudio, 'Matnga'),
      if (isMine && !isMedia)
        _MessageMenuAction('edit', LucideIcons.squarePen, 'Tahrirlash'),
      if (m.isEdited)
        _MessageMenuAction(
            'history', LucideIcons.history, 'Oldingi versiyalar'),
      _MessageMenuAction('pin', LucideIcons.pin, 'Qadash'),
      if (hasLink)
        _MessageMenuAction('copy_link', LucideIcons.link, 'Havolani nusxalash'),
      _MessageMenuAction('forward', LucideIcons.forward, 'Uzatish'),
      if (widget.conversation?.isSelfChat ?? false)
        _MessageMenuAction('tag', LucideIcons.tags, "Teg qo'shish"),
      if (!isMine &&
          (widget.conversation?.type == 'group' ||
              widget.conversation?.type == 'channel'))
        _MessageMenuAction(
            'report', LucideIcons.circleAlert, 'Shikoyat qilish'),
      if (isMine)
        _MessageMenuAction('delete', LucideIcons.trash2, "O'chirish",
            destructive: true),
      _MessageMenuAction('select', LucideIcons.circleCheck, 'Tanlash',
          separated: true),
    ];

    final result = await _showMessageActionOverlay(
      anchor: position,
      title: isMine ? _readReceiptTitle(m) : 'Xabar amallari',
      actions: actions,
      onReact: (emoji) => _onReact(m, emoji),
    );

    if (result == null) return;
    switch (result) {
      case 'reply':
        _onReply(m);
        break;
      case 'edit':
        _onEdit(m);
        break;
      case 'history':
        _showEditHistory(m);
        break;
      case 'copy':
        Clipboard.setData(ClipboardData(text: text));
        if (mounted) {
          AppToast.success(context, 'Nusxalandi');
        }
        break;
      case 'copy_link':
        final link = RegExp(r'https?://\S+').firstMatch(text)?.group(0);
        if (link != null) {
          Clipboard.setData(ClipboardData(text: link));
        }
        if (mounted) {
          AppToast.success(context, 'Havola nusxalandi');
        }
        break;
      case 'pin':
        await ref.read(messagesRepositoryProvider).pinMessage(
              conversationId: widget.conversationId,
              messageId: m.id,
            );
        // ignore: unused_result
        ref.refresh(pinnedMessagesProvider(widget.conversationId));
        break;
      case 'speak':
        await _speakMessage(text);
        break;
      case 'translate':
        await ref
            .read(messagesProvider(widget.conversationId).notifier)
            .translate(m.id);
        break;
      case 'transcribe':
        await ref
            .read(messagesProvider(widget.conversationId).notifier)
            .transcribe(m.id);
        break;
      case 'tag':
        await _tagSavedMessage(m);
        break;
      case 'save_media':
        if (m.mediaUrl != null) {
          await launchUrl(Uri.parse(m.mediaUrl!),
              mode: LaunchMode.externalApplication);
        }
        break;
      case 'save_notifications':
        if (m.mediaUrl != null) {
          await Clipboard.setData(ClipboardData(text: m.mediaUrl!));
          if (mounted) {
            AppToast.success(context, 'Media havolasi nusxalandi');
          }
        }
        break;
      case 'report':
        await _reportMessage(m);
        break;
      case 'forward':
        _showForwardSheet(m);
        break;
      case 'select':
        _enterSelectionMode(m.id);
        break;
      case 'delete':
        _onDelete(m);
        break;
    }
  }

  Future<void> _tagSavedMessage(Message message) async {
    final ctrl = TextEditingController();
    final tag = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Teg qo'shish"),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'masalan: ish, oila'),
          onSubmitted: (value) => Navigator.pop(ctx, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Bekor'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Saqlash'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (tag == null || tag.trim().isEmpty) return;
    await ref
        .read(messagesProvider(widget.conversationId).notifier)
        .tagSavedMessage(message.id, tag);
  }

  /// Forward sheet — mirrors web `TelegramForwardDialog.tsx` (shows chat list to forward into).

  String _readReceiptTitle(Message message) {
    final readAt = message.readAt;
    if (readAt == null) {
      return message.status == 'read' ? "O'qilgan" : "Hali o'qilmagan";
    }
    final local = readAt.toLocal();
    final now = DateTime.now();
    final time = DateFormat('HH:mm').format(local);
    final isToday = local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday = local.year == yesterday.year &&
        local.month == yesterday.month &&
        local.day == yesterday.day;
    if (isToday) return "bugun $time da o'qigan";
    if (isYesterday) return "kecha $time da o'qigan";
    return "${DateFormat('dd.MM.yyyy HH:mm').format(local)} da o'qigan";
  }

  Future<String?> _showMessageActionOverlay({
    required Offset anchor,
    required String title,
    required List<_MessageMenuAction> actions,
    required ValueChanged<String> onReact,
  }) {
    final completer = Completer<String?>();
    final overlay = Overlay.of(context);
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    final size = overlayBox?.size ?? MediaQuery.sizeOf(context);
    final localAnchor = overlayBox?.globalToLocal(anchor) ?? anchor;
    const menuWidth = 236.0;
    final reactionWidth = (size.width - 20).clamp(240.0, 360.0).toDouble();
    const reactionHeight = 58.0;
    final menuHeight =
        (38.0 + actions.length * 34.0 + 14.0).clamp(160.0, size.height * 0.58);
    final left = (localAnchor.dx - menuWidth / 2)
        .clamp(10.0, size.width - menuWidth - 10.0);
    final preferAbove = localAnchor.dy > size.height * 0.55;
    final menuTop = preferAbove
        ? (localAnchor.dy - menuHeight - 12)
            .clamp(10.0, size.height - menuHeight - 10.0)
        : (localAnchor.dy + 12).clamp(10.0, size.height - menuHeight - 10.0);
    final reactionTop = (menuTop - reactionHeight - 8)
        .clamp(10.0, size.height - reactionHeight - 10.0);
    final reactionLeft = (localAnchor.dx - reactionWidth / 2)
        .clamp(10.0, size.width - reactionWidth - 10.0);

    late final OverlayEntry entry;
    void close([String? value]) {
      if (entry.mounted) entry.remove();
      if (!completer.isCompleted) completer.complete(value);
    }

    entry = OverlayEntry(
      builder: (ctx) => Stack(children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => close(),
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          left: reactionLeft,
          top: reactionTop,
          width: reactionWidth,
          child: _MessageReactionMenuBar(
            onReact: (emoji) {
              onReact(emoji);
              close();
            },
            onMore: () {
              close();
              Future<void>.microtask(() async {
                if (!mounted) return;
                final emoji = await EmojiPickerSheet.showReactions(context);
                if (emoji == null || emoji.isEmpty) return;
                onReact(emoji);
              });
            },
          ),
        ),
        Positioned(
          left: left,
          top: menuTop,
          width: menuWidth,
          child: _MessageActionPanel(
            title: title,
            actions: actions,
            maxHeight: menuHeight,
            onSelected: close,
          ),
        ),
      ]),
    );
    overlay.insert(entry);
    return completer.future;
  }

  void _showForwardSheet(Message m) {
    _showForwardDialog([m]);
  }

  /// Initiates a real WebRTC call via Supabase Realtime signaling.
  Future<void> _startCall({required String type}) async {
    HapticFeedback.heavyImpact();
    final isVideo = type == 'video';
    final conv = widget.conversation;

    // Show a loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    bool loadingDismissed = false;

    try {
      final sb = Supabase.instance.client;
      final uid = sb.auth.currentUser?.id;
      if (uid == null) throw Exception('Not logged in');

      final callId = await _createCallSession(
        sb: sb,
        uid: uid,
        type: type,
        isVideo: isVideo,
      );
      final participantRows = await sb
          .from('conversation_participants')
          .select('user_id')
          .eq('conversation_id', widget.conversationId)
          .timeout(const Duration(seconds: 12));
      final recipientIds = (participantRows as List)
          .map((p) => p['user_id'] as String?)
          .whereType<String>()
          .where((id) => id != uid)
          .toSet()
          .toList();

      final callerProfile = await sb
          .from('profiles')
          .select('display_name, username, avatar_url')
          .eq('id', uid)
          .maybeSingle()
          .timeout(const Duration(seconds: 8));
      final callerName = (callerProfile?['display_name'] as String?) ??
          (callerProfile?['username'] as String?) ??
          'Alsamos';
      final callerAvatar = callerProfile?['avatar_url'] as String?;

      debugPrint(
          '[ChatPage] Sending call invites to ${recipientIds.length} recipients');

      final inviteChannels = <RealtimeChannel>[];
      for (final recipientId in recipientIds) {
        try {
          await _createCallInvite(
            sb: sb,
            callId: callId,
            callerId: uid,
            recipientId: recipientId,
            type: type,
            callerName: callerName,
            callerAvatar: callerAvatar,
          );
          final channel = sb.channel(
            'call-invite:$recipientId',
            opts: const RealtimeChannelConfig(ack: true),
          );
          inviteChannels.add(channel);
          final inviteCompleter = Completer<void>();
          channel.subscribe((status, [error]) async {
            if (status == RealtimeSubscribeStatus.subscribed) {
              try {
                await channel.sendBroadcastMessage(
                  event: 'incoming_call',
                  payload: {
                    'call_id': callId,
                    'conversation_id': widget.conversationId,
                    'caller_id': uid,
                    'caller_name': callerName,
                    'caller_avatar': callerAvatar,
                    'call_type': type,
                    'created_at': DateTime.now().toUtc().toIso8601String(),
                  },
                );
              } catch (e) {
                debugPrint('[ChatPage] Error broadcasting invite: $e');
              } finally {
                if (!inviteCompleter.isCompleted) inviteCompleter.complete();
              }
            } else if (status == RealtimeSubscribeStatus.timedOut ||
                status == RealtimeSubscribeStatus.channelError) {
              if (!inviteCompleter.isCompleted) inviteCompleter.complete();
            }
          });
          await inviteCompleter.future.timeout(
            const Duration(seconds: 5),
            onTimeout: () {},
          );
        } catch (e) {
          debugPrint('[ChatPage] Error sending invite: $e');
        }
      }
      // Clean up invite channels
      for (final ch in inviteChannels) {
        unawaited(sb.removeChannel(ch));
      }

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // dismiss loading
      loadingDismissed = true;

      // Push call page with real UUID as room ID
      final elapsed =
          await Navigator.of(context, rootNavigator: true).push<Duration>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (ctx) => WebRTCCallPage(
            roomId: callId,
            remoteName: conv?.title,
            remoteAvatar: conv?.displayAvatar,
            isVideo: isVideo,
          ),
        ),
      );

      // WebRTCCallPage already calls leave_video_call. Never force-end a
      // group call here: one participant leaving must not terminate everybody.
      final callRow = await _ensureCallLifecycleFinalized(
        sb: sb,
        callId: callId,
      );

      if (elapsed == null || callRow == null) return;
      final endedAt = callRow['ended_at'];
      final status = callRow['status']?.toString();
      final fullyEnded = endedAt != null || status == 'ended';
      if (!fullyEnded) return;

      await _ensureCallHistoryFallback(
        sb: sb,
        callId: callId,
        type: type,
        elapsed: elapsed,
        callRow: callRow,
      );
    } catch (e) {
      if (mounted) {
        if (!loadingDismissed) {
          Navigator.of(context, rootNavigator: true)
              .pop(); // dismiss loading if not pushed
        }
        AppToast.error(context, friendlyError(e));
      }
    }
  }

  Future<Map<String, dynamic>?> _ensureCallLifecycleFinalized({
    required SupabaseClient sb,
    required String callId,
  }) async {
    Map<String, dynamic>? call;
    try {
      final row = await sb
          .from('video_calls')
          .select('id,host_id,call_type,status,started_at,ended_at,is_group_call')
          .eq('id', callId)
          .maybeSingle()
          .timeout(const Duration(seconds: 8));
      if (row == null) return null;
      call = Map<String, dynamic>.from(row);
    } catch (e) {
      debugPrint('[ChatPage] call finalization lookup failed: $e');
      return null;
    }

    if (call['ended_at'] != null || call['status'] == 'ended') return call;

    // The normal path has already invoked leave_video_call from CallNotifier.
    // This compatibility path only runs when an older backend lacks that RPC.
    try {
      final active = await sb
          .from('call_participants')
          .select('id')
          .eq('call_id', callId)
          .isFilter('left_at', null)
          .timeout(const Duration(seconds: 8));

      final isGroup = call['is_group_call'] == true;
      final activeCount = active is List ? active.length : 0;
      if (!isGroup || activeCount == 0) {
        final now = DateTime.now().toUtc().toIso8601String();
        await sb
            .from('video_calls')
            .update({'status': 'ended', 'ended_at': now})
            .eq('id', callId)
            .isFilter('ended_at', null)
            .timeout(const Duration(seconds: 8));
        call = {...call, 'status': 'ended', 'ended_at': now};
      }
    } catch (e) {
      debugPrint('[ChatPage] compatibility call finalization skipped: $e');
    }

    return call;
  }

  Future<void> _ensureCallHistoryFallback({
    required SupabaseClient sb,
    required String callId,
    required String type,
    required Duration elapsed,
    required Map<String, dynamic> callRow,
  }) async {
    // New backend: record_finished_video_call creates the structured bubble
    // atomically and messages.call_id makes it idempotent.
    try {
      final existing = await sb
          .from('messages')
          .select('id')
          .eq('call_id', callId)
          .eq('media_type', 'call_history')
          .maybeSingle()
          .timeout(const Duration(seconds: 6));
      if (existing != null) return;

      final payload = await _buildCallHistoryPayload(
        sb: sb,
        callId: callId,
        type: type,
        elapsed: elapsed,
        callRow: callRow,
      );
      try {
        await sb.from('messages').insert({
          'conversation_id': widget.conversationId,
          'sender_id': callRow['host_id'],
          'content': jsonEncode(payload),
          'media_type': 'call_history',
          'call_id': callId,
        }).timeout(const Duration(seconds: 8));
        return;
      } catch (e) {
        if (!_isDuplicateConflict(e)) {
          debugPrint('[ChatPage] canonical history insert failed: $e');
        }
        return;
      }
    } catch (e) {
      // messages.call_id is absent on an older schema. Fall through to the
      // legacy sender but keep the CONTENT canonical JSON, never plain text.
      debugPrint('[ChatPage] call history canonical probe unavailable: $e');
    }

    final payload = await _buildCallHistoryPayload(
      sb: sb,
      callId: callId,
      type: type,
      elapsed: elapsed,
      callRow: callRow,
    );
    await ref.read(messagesProvider(widget.conversationId).notifier).send(
          jsonEncode(payload),
          mediaType: 'call_history',
        );
  }

  Future<Map<String, dynamic>> _buildCallHistoryPayload({
    required SupabaseClient sb,
    required String callId,
    required String type,
    required Duration elapsed,
    required Map<String, dynamic> callRow,
  }) async {
    var lifecycleStatus = callRow['started_at'] == null ? 'cancelled' : 'ended';
    String? calleeId;

    try {
      final invite = await sb
          .from('call_invites')
          .select('invitee_id,status')
          .eq('call_id', callId)
          .inFilter('status', ['missed', 'declined'])
          .order('updated_at', ascending: false)
          .limit(1)
          .maybeSingle()
          .timeout(const Duration(seconds: 5));
      if (invite != null) {
        final inviteStatus = invite['status']?.toString();
        if (inviteStatus == 'missed' || inviteStatus == 'declined') {
          lifecycleStatus = inviteStatus!;
        }
        calleeId = invite['invitee_id']?.toString();
      }
    } catch (_) {}

    if (calleeId == null) {
      try {
        final hostId = callRow['host_id']?.toString();
        final members = await sb
            .from('conversation_participants')
            .select('user_id')
            .eq('conversation_id', widget.conversationId)
            .timeout(const Duration(seconds: 5));
        for (final row in members as List) {
          if (row is! Map) continue;
          final id = row['user_id']?.toString();
          if (id != null && id != hostId) {
            calleeId = id;
            break;
          }
        }
      } catch (_) {}
    }

    final endedAt =
        callRow['ended_at']?.toString() ?? DateTime.now().toUtc().toIso8601String();

    return {
      'call_id': callId,
      'type': type == 'audio' ? 'audio' : 'video',
      'status': lifecycleStatus,
      'duration': elapsed.inSeconds > 0 ? elapsed.inSeconds : null,
      'timestamp': endedAt,
      'caller_id': callRow['host_id']?.toString() ?? '',
      'callee_id': calleeId ?? '',
    };
  }

  Future<String> _createCallSession({
    required SupabaseClient sb,
    required String uid,
    required String type,
    required bool isVideo,
  }) async {
    await _expireStaleCallSessions(sb);

    try {
      final result = await sb.rpc('create_video_call', params: {
        'p_conversation_id': widget.conversationId,
        'p_call_type': type,
        'p_is_video_on': isVideo,
      }).timeout(const Duration(seconds: 12));
      final callId = _callIdFromRpcResult(result);
      if (callId != null) {
        await _upsertLocalCallParticipant(
          sb: sb,
          uid: uid,
          callId: callId,
          isVideo: isVideo,
        );
        return callId;
      }
    } catch (e) {
      if (!_isMissingRpc(e)) {
        if (_isDuplicateConflict(e)) {
          final existing = await _findReusableCall(sb);
          if (existing != null) {
            await _upsertLocalCallParticipant(
              sb: sb,
              uid: uid,
              callId: existing,
              isVideo: isVideo,
            );
            return existing;
          }
        }
        rethrow;
      }
      debugPrint(
          '[ChatPage] create_video_call RPC unavailable, using fallback: $e');
    }

    try {
      final callData = await sb
          .from('video_calls')
          .insert({
            'conversation_id': widget.conversationId,
            'host_id': uid,
            'call_type': type,
            'status': 'active',
            'started_at': null,
          })
          .select()
          .single()
          .timeout(const Duration(seconds: 12));

      final callId = callData['id'] as String;
      await _upsertLocalCallParticipant(
        sb: sb,
        uid: uid,
        callId: callId,
        isVideo: isVideo,
      );
      return callId;
    } catch (e) {
      if (!_isDuplicateConflict(e)) rethrow;
      final existing = await _findReusableCall(sb);
      if (existing == null) rethrow;
      await _upsertLocalCallParticipant(
        sb: sb,
        uid: uid,
        callId: existing,
        isVideo: isVideo,
      );
      return existing;
    }
  }

  Future<void> _expireStaleCallSessions(SupabaseClient sb) async {
    final now = DateTime.now().toUtc();
    final staleBefore = now.subtract(const Duration(minutes: 2));
    try {
      await sb
          .from('video_calls')
          .update({
            'status': 'ended',
            'ended_at': now.toIso8601String(),
          })
          .eq('conversation_id', widget.conversationId)
          .inFilter(
            'status',
            ['waiting', 'ringing', 'calling', 'connecting', 'active'],
          )
          .isFilter('ended_at', null)
          .isFilter('started_at', null)
          .lt('created_at', staleBefore.toIso8601String())
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('[ChatPage] stale call cleanup skipped: $e');
    }
  }

  Future<void> _upsertLocalCallParticipant({
    required SupabaseClient sb,
    required String uid,
    required String callId,
    required bool isVideo,
  }) async {
    final participant = {
      'call_id': callId,
      'user_id': uid,
      'joined_at': DateTime.now().toUtc().toIso8601String(),
      'left_at': null,
      'is_muted': false,
      'is_video_on': isVideo,
      'is_screen_sharing': false,
      'is_hand_raised': false,
      'connection_state': 'joining',
      'last_seen_at': DateTime.now().toUtc().toIso8601String(),
    };

    try {
      await sb
          .from('call_participants')
          .upsert(participant, onConflict: 'call_id,user_id')
          .timeout(const Duration(seconds: 12));
      return;
    } catch (e) {
      if (!_isDuplicateConflict(e) && !_isConflictTargetMissing(e)) rethrow;
      debugPrint('[ChatPage] participant upsert fallback: $e');
    }

    final existing = await sb
        .from('call_participants')
        .select('id')
        .eq('call_id', callId)
        .eq('user_id', uid)
        .maybeSingle()
        .timeout(const Duration(seconds: 8));

    if (existing != null && existing['id'] != null) {
      await sb
          .from('call_participants')
          .update(participant)
          .eq('id', existing['id'])
          .timeout(const Duration(seconds: 8));
      return;
    }

    try {
      await sb
          .from('call_participants')
          .insert(participant)
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      if (!_isDuplicateConflict(e)) rethrow;
      await sb
          .from('call_participants')
          .update(participant)
          .eq('call_id', callId)
          .eq('user_id', uid)
          .timeout(const Duration(seconds: 8));
    }
  }

  Future<String?> _findReusableCall(SupabaseClient sb) async {
    const reusableStatuses = {
      'waiting',
      'ringing',
      'calling',
      'connecting',
      'active',
    };

    try {
      final rows = await sb
          .from('video_calls')
          .select('id,status,ended_at')
          .eq('conversation_id', widget.conversationId)
          .isFilter('ended_at', null)
          .order('created_at', ascending: false)
          .limit(5)
          .timeout(const Duration(seconds: 8));

      for (final row in rows as List) {
        if (row is! Map) continue;
        final id = row['id']?.toString();
        if (id == null || id.isEmpty) continue;
        final status = row['status']?.toString();
        if (status == null ||
            status.isEmpty ||
            reusableStatuses.contains(status)) {
          return id;
        }
      }
    } catch (e) {
      debugPrint('[ChatPage] broad reusable call lookup failed: $e');
    }

    final row = await sb
        .from('video_calls')
        .select('id')
        .eq('conversation_id', widget.conversationId)
        .inFilter('status', reusableStatuses.toList())
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle()
        .timeout(const Duration(seconds: 8));
    return row?['id'] as String?;
  }

  Future<void> _createCallInvite({
    required SupabaseClient sb,
    required String callId,
    required String callerId,
    required String recipientId,
    required String type,
    required String callerName,
    required String? callerAvatar,
  }) async {
    final metadata = <String, dynamic>{
      'caller_name': callerName,
      if (callerAvatar != null) 'caller_avatar': callerAvatar,
    };
    try {
      await sb.rpc('invite_to_video_call', params: {
        'p_call_id': callId,
        'p_invitee_id': recipientId,
        'p_call_type': type,
      }).timeout(const Duration(seconds: 8));
      return;
    } catch (e) {
      if (!_isMissingRpc(e)) {
        debugPrint('[ChatPage] invite_to_video_call RPC failed: $e');
      }
    }

    // Compatibility with older call backends.
    try {
      await sb.rpc('create_call_invite', params: {
        'p_call_id': callId,
        'p_invitee_id': recipientId,
        'p_conversation_id': widget.conversationId,
        'p_call_type': type,
        'p_metadata': metadata,
      }).timeout(const Duration(seconds: 8));
      return;
    } catch (e) {
      if (!_isMissingRpc(e)) {
        debugPrint('[ChatPage] legacy create_call_invite RPC failed: $e');
      }
    }

    final invite = {
      'call_id': callId,
      'conversation_id': widget.conversationId,
      'inviter_id': callerId,
      'invitee_id': recipientId,
      'status': 'ringing',
      'call_type': type,
      'metadata': metadata,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    try {
      await sb
          .from('call_invites')
          .upsert(invite, onConflict: 'call_id,invitee_id')
          .timeout(const Duration(seconds: 8));
      return;
    } catch (e) {
      if (!_isDuplicateConflict(e) && !_isConflictTargetMissing(e)) {
        debugPrint('[ChatPage] call_invites fallback failed: $e');
        return;
      }
      debugPrint('[ChatPage] call_invites upsert fallback: $e');
    }

    try {
      final existing = await sb
          .from('call_invites')
          .select('id')
          .eq('call_id', callId)
          .eq('invitee_id', recipientId)
          .maybeSingle()
          .timeout(const Duration(seconds: 8));

      if (existing != null && existing['id'] != null) {
        await sb
            .from('call_invites')
            .update(invite)
            .eq('id', existing['id'])
            .timeout(const Duration(seconds: 8));
        return;
      }

      await sb
          .from('call_invites')
          .insert(invite)
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      if (!_isDuplicateConflict(e)) {
        debugPrint('[ChatPage] call_invites update/insert fallback failed: $e');
        return;
      }
      await sb
          .from('call_invites')
          .update(invite)
          .eq('call_id', callId)
          .eq('invitee_id', recipientId)
          .timeout(const Duration(seconds: 8));
    }
  }

  String? _callIdFromRpcResult(Object? result) {
    if (result == null) return null;
    if (result is String && result.isNotEmpty) return result;
    if (result is Map) {
      return (result['call_id'] ?? result['id'])?.toString();
    }
    return result.toString().isEmpty ? null : result.toString();
  }

  bool _isMissingRpc(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('pgrst202') ||
        message.contains('42883') ||
        (message.contains('function') && message.contains('does not exist')) ||
        message.contains('could not find the function');
  }

  bool _isDuplicateConflict(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('23505') ||
        message.contains('duplicate key') ||
        message.contains('already exists') ||
        message.contains('allaqachon');
  }

  bool _isConflictTargetMissing(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('42p10') ||
        message.contains('no unique or exclusion constraint');
  }

  /// v30: image_picker bilan rasm/video tanlaydi, Supabase Storage `chat-media`
  /// bucket'ga yuklaydi, so'ng `messages` jadvalga `media_url`/`media_type` bilan yuboradi.
  Future<void> _pickAndSendMedia(ImageSource source,
      {required bool isVideo}) async {
    Future<void> retry() => _pickAndSendMedia(source, isVideo: isVideo);
    String? taskId;
    try {
      var effectiveSource = source;
      if (source == ImageSource.camera &&
          !CameraCapability.supportsImagePickerCapture) {
        AppToast.warning(context, CameraCapability.unsupportedCaptureMessage);
        effectiveSource = ImageSource.gallery;
      }
      final picker = ImagePicker();
      final imageQuality =
          await ref.read(mediaSettingsServiceProvider).imageQuality();
      final XFile? file = isVideo
          ? await picker.pickVideo(
              source: effectiveSource, maxDuration: const Duration(minutes: 3))
          : await picker.pickImage(
              source: effectiveSource,
              imageQuality: imageQuality,
              maxWidth: 1920);
      if (file == null) return;
      if (!mounted) return;
      taskId = _beginUpload(
          isVideo ? 'Video yuklanmoqda' : 'Rasm yuklanmoqda', retry);
      final sb = Supabase.instance.client;
      final uid = sb.auth.currentUser?.id ?? 'anon';
      final ext = file.name.contains('.')
          ? file.name.split('.').last
          : (isVideo ? 'mp4' : 'jpg');
      final path = '$uid/${DateTime.now().millisecondsSinceEpoch}.$ext';
      final bytes = await file.readAsBytes();

      if (isVideo) {
        final meta = await _prepareVideoMessage(file, bytes.length);
        await ref.read(messagesProvider(widget.conversationId).notifier).send(
          '',
          mediaType: 'video',
          thumbnailUrl: meta.thumbnailPreviewUrl,
          metadata: {
            'local_media_path': file.path,
            if (meta.localThumbPath != null)
              'local_thumb_path': meta.localThumbPath,
            if (meta.thumbnailPreviewUrl != null)
              'thumbnail_url': meta.thumbnailPreviewUrl,
            'duration_ms': meta.duration.inMilliseconds,
            if (meta.width != null) 'width': meta.width,
            if (meta.height != null) 'height': meta.height,
            'size_bytes': bytes.length,
            'mime_type': _contentTypeForFile(file.name),
            'upload_progress': 0.02,
          },
        );
        _finishUpload(taskId);
        return;
      }

      // Thumbnail avtomatik yaratish
      String? thumbnailUrl;
      try {
        Uint8List? thumbBytes;
        if (isVideo) {
          thumbBytes = await VideoThumbnail.thumbnailData(
            video: file.path,
            imageFormat: ImageFormat.JPEG,
            maxWidth: 320,
            quality: 70,
          );
        } else {
          final original = img.decodeImage(bytes);
          if (original != null) {
            final resized = img.copyResize(original, width: 320);
            thumbBytes =
                Uint8List.fromList(img.encodeJpg(resized, quality: 70));
          }
        }

        if (thumbBytes != null) {
          final thumbPath =
              '$uid/thumbnails/${DateTime.now().microsecondsSinceEpoch}_thumb.jpg';
          await sb.storage.from('chat-media').uploadBinary(
                thumbPath,
                thumbBytes,
                fileOptions: const FileOptions(
                  contentType: 'image/jpeg',
                  upsert: false,
                ),
              );
          thumbnailUrl = sb.storage.from('chat-media').getPublicUrl(thumbPath);
        }
      } catch (e) {
        debugPrint('Thumbnail yaratishda xato: $e');
      }

      final publicUrl = await _uploadChatMedia(
        bytes,
        path,
        contentType: _contentTypeForFile(file.name),
        taskId: taskId,
      );
      _setUploadProgress(taskId, 0.95);
      await ref.read(messagesProvider(widget.conversationId).notifier).send('',
          mediaUrl: publicUrl,
          mediaType: isVideo ? 'video' : 'image',
          thumbnailUrl: thumbnailUrl);
      _finishUpload(taskId);
      if (!mounted) return;
      AppToast.success(context, isVideo ? 'Video yuborildi' : 'Rasm yuborildi');
    } catch (e) {
      if (taskId != null) _failUpload(taskId, e);
      if (!mounted) return;
      AppToast.error(
        context,
        "Kamera/Galereya uskunada qo'llab-quvvatlanmaydi yoki ruxsat yo'q",
        duration: const Duration(seconds: 4),
      );
    }
  }

  Future<_PreparedVideoMessage> _prepareVideoMessage(
      XFile file, int sizeBytes) async {
    String? thumbPath;
    String? thumbPreviewUrl;
    try {
      thumbPath = await VideoThumbnail.thumbnailFile(
        video: file.path,
        thumbnailPath: (await getTemporaryDirectory()).path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 640,
        quality: 74,
      );
      if (thumbPath != null) thumbPreviewUrl = Uri.file(thumbPath).toString();
    } catch (e) {
      debugPrint('Video thumbnail yaratishda xato: $e');
    }

    Duration duration = Duration.zero;
    int? width;
    int? height;
    VideoPlayerController? controller;
    try {
      controller = VideoPlayerController.file(File(file.path));
      await controller.initialize();
      duration = controller.value.duration;
      final size = controller.value.size;
      if (size.width > 0 && size.height > 0) {
        width = size.width.round();
        height = size.height.round();
      }
    } catch (e) {
      debugPrint('Video metadata o‘qishda xato: $e');
    } finally {
      disposeVideoControllerSafely(controller);
    }
    return _PreparedVideoMessage(
      localThumbPath: thumbPath,
      thumbnailPreviewUrl: thumbPreviewUrl,
      duration: duration,
      width: width,
      height: height,
      sizeBytes: sizeBytes,
    );
  }

  Future<void> _pickAndSendAlbum() async {
    Future<void> retry() => _pickAndSendAlbum();
    String? taskId;
    try {
      final picker = ImagePicker();
      final files =
          await picker.pickMultiImage(imageQuality: 85, maxWidth: 1920);
      if (files.isEmpty) return;
      if (!mounted) return;
      taskId = _beginUpload('Album yuklanmoqda', retry);
      final sb = Supabase.instance.client;
      final uid = sb.auth.currentUser?.id ?? 'anon';
      final urls = <String>[];
      final thumbUrls = <String>[];
      final mediaPaths = <String>[];
      final mediaBuckets = <String>[];
      final mimeTypes = <String>[];
      for (final file in files.take(10)) {
        final path =
            '$uid/albums/${DateTime.now().microsecondsSinceEpoch}_${file.name}';
        final bytes = await file.readAsBytes();

        // Thumbnail yaratish
        String? thumbUrl;
        try {
          final original = img.decodeImage(bytes);
          if (original != null) {
            final resized = img.copyResize(original, width: 320);
            final thumbBytes =
                Uint8List.fromList(img.encodeJpg(resized, quality: 70));
            final thumbPath =
                '$uid/thumbnails/${DateTime.now().microsecondsSinceEpoch}_thumb.jpg';
            await sb.storage.from('chat-media').uploadBinary(
                  thumbPath,
                  thumbBytes,
                  fileOptions: const FileOptions(
                    contentType: 'image/jpeg',
                    upsert: false,
                  ),
                );
            thumbUrl = sb.storage.from('chat-media').getPublicUrl(thumbPath);
          }
        } catch (e) {
          debugPrint('Album thumbnail yaratishda xato: $e');
        }

        _setUploadProgress(taskId, 0.1 + (urls.length / files.length) * 0.75);
        final uploaded = await _uploadChatMediaResult(
          bytes,
          path,
          contentType: _contentTypeForFile(file.name),
          taskId: taskId,
        );
        urls.add(uploaded.url);
        thumbUrls.add(thumbUrl ?? uploaded.url);
        mediaPaths.add(uploaded.path);
        mediaBuckets.add(uploaded.bucket);
        mimeTypes.add(uploaded.contentType);
      }
      if (urls.isEmpty) return;
      await ref.read(messagesProvider(widget.conversationId).notifier).send(
        '',
        mediaUrl: urls.first,
        mediaType: 'album',
        thumbnailUrl: thumbUrls.first,
        metadata: {
          'album_id': 'album-${DateTime.now().microsecondsSinceEpoch}',
          'media_urls': urls,
          'thumbnail_urls': thumbUrls,
          'media_paths': mediaPaths,
          'media_buckets': mediaBuckets,
          'mime_types': mimeTypes,
          if (mediaPaths.isNotEmpty) 'media_path': mediaPaths.first,
          if (mediaBuckets.isNotEmpty) 'media_bucket': mediaBuckets.first,
          if (mimeTypes.isNotEmpty) 'mime_type': mimeTypes.first,
        },
      );
      _finishUpload(taskId);
    } catch (e) {
      if (taskId != null) _failUpload(taskId, e);
      if (!mounted) return;
      AppToast.error(context, friendlyError(e));
    }
  }

  Future<void> _pickAndSendFile() async {
    Future<void> retry() => _pickAndSendFile();
    String? taskId;
    try {
      final result = await FilePicker.pickFiles();
      if (result == null || result.files.isEmpty) return;
      if (!mounted) return;

      final file = result.files.first;
      final bytes = file.bytes ??
          (file.path != null ? await File(file.path!).readAsBytes() : null);
      if (bytes == null) return;

      taskId = _beginUpload('Fayl yuklanmoqda', retry);
      final sb = Supabase.instance.client;
      final uid = sb.auth.currentUser?.id ?? 'anon';
      final path = '$uid/${DateTime.now().millisecondsSinceEpoch}_${file.name}';

      final uploaded = await _uploadChatMediaResult(
        bytes,
        path,
        contentType: _contentTypeForFile(file.name),
        taskId: taskId,
      );
      _setUploadProgress(taskId, 0.95);

      await ref.read(messagesProvider(widget.conversationId).notifier).send(
        file.name,
        mediaUrl: uploaded.url,
        mediaType: 'file',
        metadata: {
          'file_name': file.name,
          'media_path': uploaded.path,
          'media_bucket': uploaded.bucket,
          'mime_type': uploaded.contentType,
          'size_bytes': bytes.length,
        },
      );
      _finishUpload(taskId);
      if (!mounted) return;
      AppToast.success(context, 'Fayl yuborildi');
    } catch (e) {
      if (taskId != null) _failUpload(taskId, e);
      if (!mounted) return;
      AppToast.error(context, friendlyError(e));
    }
  }

  Future<void> _sendLocation({
    bool live = false,
    String label = 'Current location',
    Duration? liveDuration,
  }) async {
    try {
      if (!mounted) return;
      AppToast.info(context, 'Joylashuv aniqlanmoqda...');

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showPermissionHelp('Joylashuv ruxsati berilmadi.');
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        _showPermissionHelp(
            'Joylashuv ruxsati doimiy bloklangan. Settingsdan yoqing.');
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.high));
      final expiresAt = live
          ? DateTime.now()
              .toUtc()
              .add(liveDuration ?? const Duration(minutes: 15))
          : null;

      await ref.read(messagesProvider(widget.conversationId).notifier).send(
        '$label\n${pos.latitude},${pos.longitude}',
        mediaType: live ? 'live_location' : 'location',
        metadata: {
          if (expiresAt != null)
            'live_location_expires_at': expiresAt.toIso8601String(),
          if (liveDuration != null)
            'live_location_duration_seconds': liveDuration.inSeconds,
        },
      );

      if (!mounted) return;
      AppToast.success(context, 'Joylashuv yuborildi');
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, friendlyError(e));
    }
  }

  void _showPermissionHelp(String message) {
    if (!mounted) return;
    AppToast.error(context, message,
        actionLabel: 'Settings', action: Geolocator.openAppSettings);
  }

  Future<Duration?> _pickLiveLocationDuration() =>
      showModalBottomSheet<Duration>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          final c = AlsamosColors.of(ctx);
          Widget item(String title, Duration value) => ListTile(
                leading: const Icon(LucideIcons.timer),
                title: Text(title),
                onTap: () => Navigator.pop(ctx, value),
              );
          return SafeArea(
            child: Container(
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.card.withValues(alpha: 0.98),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: c.border),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                item('15 daqiqa', const Duration(minutes: 15)),
                item('1 soat', const Duration(hours: 1)),
                item('8 soat', const Duration(hours: 8)),
              ]),
            ),
          );
        },
      );

  void _showLocationSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final c = AlsamosColors.of(ctx);
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.card.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: c.border.withValues(alpha: 0.7)),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                leading: const Icon(LucideIcons.crosshair),
                title: const Text('Current location'),
                subtitle: const Text('Hozirgi joylashuvni yuborish'),
                onTap: () {
                  Navigator.pop(ctx);
                  _sendLocation(label: 'Current location');
                },
              ),
              ListTile(
                leading: const Icon(LucideIcons.radioTower),
                title: const Text('Live location'),
                subtitle: const Text('15 daqiqa / 1 soat / 8 soat davomida'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final duration = await _pickLiveLocationDuration();
                  if (duration == null) return;
                  _sendLocation(
                    live: true,
                    label: 'Live location',
                    liveDuration: duration,
                  );
                },
              ),
              ListTile(
                leading: const Icon(LucideIcons.mapPinned),
                title: const Text('Joy tanlash'),
                subtitle: const Text('Yaqin joylar ro\'yxati bilan'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _sendLocationFromMapPicker();
                },
              ),
            ]),
          ),
        );
      },
    );
  }

  /// Opens the map+nearby-places picker and sends the selected location.
  Future<void> _sendLocationFromMapPicker() async {
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever ||
          perm == LocationPermission.denied) {
        _showPermissionHelp('Joylashuv ruxsati berilmadi.');
        return;
      }
      // ignore: deprecated_member_use
      final pos = await Geolocator.getCurrentPosition(
          // ignore: deprecated_member_use
          desiredAccuracy: LocationAccuracy.high);
      if (!mounted) return;
      final picked = await Navigator.push<SharedLocation>(
        context,
        MaterialPageRoute(
            builder: (_) => LocationPickerScreen(
                initial: LatLng(pos.latitude, pos.longitude))),
      );
      if (picked == null || !mounted) return;
      final label = picked.address ?? 'Tanlangan joy';
      await ref.read(messagesProvider(widget.conversationId).notifier).send(
        '$label\n${picked.latitude},${picked.longitude}',
        mediaType: 'location',
        metadata: {
          'location_label': label,
          'latitude': picked.latitude,
          'longitude': picked.longitude,
          if (picked.placeType != null) 'place_type': picked.placeType,
          if (picked.distanceM != null) 'distance_m': picked.distanceM,
          'picked_from_nearby_places': picked.placeType != null,
        },
      );
    } catch (e) {
      if (mounted) {
        AppToast.error(context, friendlyError(e));
      }
    }
  }

  // ignore: unused_element
  void _ensureDartIoImport() {
    File('').path;
  } // keeps dart:io alive for any future use

  void _showAttachmentMenu() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
        context: context,
        builder: (ctx) {
          final c = AlsamosColors.of(ctx);
          Widget tile(
            IconData ic,
            String label,
            Color color,
            VoidCallback onTap,
          ) =>
              Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(24),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  borderRadius: BorderRadius.circular(24),
                  hoverColor: color.withValues(alpha: 0.06),
                  highlightColor: color.withValues(alpha: 0.08),
                  splashColor: color.withValues(alpha: 0.10),
                  onTap: () {
                    Navigator.pop(ctx);
                    onTap();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 12),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.15),
                              shape: BoxShape.circle),
                          child: Icon(ic, color: color, size: 26)),
                      const SizedBox(height: 6),
                      Text(label,
                          style: TextStyle(fontSize: 12, color: c.foreground)),
                    ]),
                  ),
                ),
              );
          // v37: real dialoglar — ComposerExtras (Joylashuv/Kontakt/So'rovnoma)
          return SafeArea(
              child: Padding(
            padding: const EdgeInsets.all(20),
            child: GridView.count(
              shrinkWrap: true,
              crossAxisCount: 4,
              mainAxisSpacing: 16,
              children: [
                // v30: media tile'lar image_picker + Supabase Storage'ga ulandi
                tile(
                    LucideIcons.image,
                    'Galereya',
                    Colors.purple,
                    () =>
                        _pickAndSendMedia(ImageSource.gallery, isVideo: false)),
                tile(LucideIcons.images, 'Album', Colors.indigo,
                    _pickAndSendAlbum),
                tile(
                    LucideIcons.camera,
                    'Kamera',
                    Colors.red,
                    () =>
                        _pickAndSendMedia(ImageSource.camera, isVideo: false)),
                tile(
                    LucideIcons.video,
                    'Video',
                    Colors.pink,
                    () =>
                        _pickAndSendMedia(ImageSource.gallery, isVideo: true)),
                tile(LucideIcons.file, 'Fayl', Colors.blue, _pickAndSendFile),
                tile(LucideIcons.sticker, 'Sticker', Colors.deepOrange,
                    _showStickerSheet),
                tile(LucideIcons.mapPin, 'Joylashuv', Colors.green,
                    _showLocationSheet),
                tile(
                    LucideIcons.user,
                    'Kontakt',
                    Colors.orange,
                    () => ComposerExtras.showContactPicker(context,
                            onShare: (n, p) {
                          ref
                              .read(messagesProvider(widget.conversationId)
                                  .notifier)
                              .send('\ud83d\udcde $n\n$p',
                                  mediaType: 'contact');
                          AppToast.success(context, 'Kontakt yuborildi');
                        })),
                tile(
                    LucideIcons.barChart3,
                    "So'rovnoma",
                    Colors.teal,
                    () => ComposerExtras.showPollCreator(context,
                            onCreate: (q, opts) {
                          final pollText =
                              "$q\n${opts.map((o) => '- $o').join('\n')}";
                          ref
                              .read(messagesProvider(widget.conversationId)
                                  .notifier)
                              .send(pollText, mediaType: 'poll', metadata: {
                            'poll': {
                              'question': q,
                              'options': [
                                for (var i = 0; i < opts.length; i++)
                                  {
                                    'id': 'opt_$i',
                                    'text': opts[i],
                                    'votes': 0,
                                  }
                              ],
                              'multiple': false,
                            }
                          });
                          AppToast.success(context, 'So\'rovnoma yuborildi');
                        })),
                // v40: GIF tile
                tile(
                    LucideIcons.image,
                    'GIF',
                    Colors.pinkAccent,
                    () => GifPicker.show(context, onSelect: (url) {
                          ref
                              .read(messagesProvider(widget.conversationId)
                                  .notifier)
                              .send('', mediaUrl: url, mediaType: 'gif');
                          AppToast.success(context, 'GIF yuborildi');
                        })),
              ],
            ),
          ));
        });
  }

  Future<void> _showStickerPicker() async {
    final sticker = await TelegramStickerPicker.show(context);
    if (sticker != null && mounted) {
      _sendSticker(sticker);
    }
  }

  Future<void> _sendSticker(Sticker sticker) async {
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) return;

    // Send sticker as message with metadata
    final stickerUrl =
        sticker.lottieUrl ?? sticker.imageUrl ?? sticker.videoUrl;
    if (stickerUrl == null) return;

    await ref.read(messagesProvider(widget.conversationId).notifier).send(
      sticker.emoji, // Text fallback
      mediaType: 'sticker',
      mediaUrl: stickerUrl,
      metadata: {
        'sticker': sticker.toMap(),
      },
    );
  }

  Future<void> _showStickerSheet() async {
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) return;
    final repo = ref.read(messagesRepositoryProvider);
    final title = TextEditingController();
    final url = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          Future<List<Map<String, dynamic>>> packs() =>
              repo.fetchStickerPacks(userId);
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.7,
            minChildSize: 0.45,
            maxChildSize: 0.92,
            builder: (_, controller) {
              final c = AlsamosColors.of(ctx);
              return Container(
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(24)),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  Row(children: [
                    const Icon(LucideIcons.sticker),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('Sticker packlar',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w800)),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(LucideIcons.x),
                    ),
                  ]),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: title,
                        decoration:
                            const InputDecoration(hintText: 'Pack nomi'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: url,
                        decoration: const InputDecoration(
                            hintText: 'Sticker image URL'),
                      ),
                    ),
                    IconButton(
                      onPressed: () async {
                        if (url.text.trim().isEmpty) return;
                        await repo.installStickerPack(
                          userId: userId,
                          title: title.text,
                          stickerUrl: url.text.trim(),
                        );
                        title.clear();
                        url.clear();
                        setLocal(() {});
                      },
                      icon: const Icon(LucideIcons.plus),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Expanded(
                    child: FutureBuilder<List<Map<String, dynamic>>>(
                      future: packs(),
                      builder: (_, snap) {
                        final items = snap.data ?? const [];
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        if (items.isEmpty) {
                          return Center(
                            child: Text('Sticker pack yo‘q',
                                style: TextStyle(color: c.mutedForeground)),
                          );
                        }
                        return GridView.builder(
                          controller: controller,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                          ),
                          itemCount: items.length,
                          itemBuilder: (_, i) {
                            final pack = items[i];
                            final stickers = (pack['stickers'] as List? ?? [])
                                .whereType<Map>()
                                .toList();
                            final sticker = stickers.isEmpty
                                ? pack['cover_url']?.toString()
                                : stickers.first['image_url']?.toString();
                            if (sticker == null || sticker.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            return Stack(children: [
                              Positioned.fill(
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    ref
                                        .read(messagesProvider(
                                                widget.conversationId)
                                            .notifier)
                                        .send('',
                                            mediaUrl: sticker,
                                            mediaType: 'sticker');
                                  },
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(14),
                                    child: Image.network(sticker,
                                        fit: BoxFit.contain),
                                  ),
                                ),
                              ),
                              Positioned(
                                right: 0,
                                top: 0,
                                child: IconButton.filledTonal(
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(LucideIcons.x, size: 14),
                                  onPressed: () async {
                                    await repo.removeStickerPack(
                                      userId: userId,
                                      packId: pack['id'].toString(),
                                    );
                                    setLocal(() {});
                                  },
                                ),
                              ),
                            ]);
                          },
                        );
                      },
                    ),
                  ),
                ]),
              );
            },
          );
        },
      ),
    );
    title.dispose();
    url.dispose();
  }

  String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(d.year, d.month, d.day);
    final diff = today.difference(that).inDays;
    if (diff == 0) return 'Bugun';
    if (diff == 1) return 'Kecha';
    if (diff < 7) return DateFormat.EEEE().format(d);
    return DateFormat('d MMMM yyyy').format(d);
  }

  Future<void> _openDiscussionForMessage(
    Message message,
    Conversation conversation,
  ) async {
    final userId = ref.read(authProvider).user?.id;
    final linkedGroupId = conversation.linkedGroupId;
    if (userId == null || linkedGroupId == null) return;
    try {
      final anchorId = await ref
          .read(messagesRepositoryProvider)
          .ensureChannelDiscussionAnchor(
            channelMessage: message,
            linkedGroupId: linkedGroupId,
            userId: userId,
          );
      pendingMessageHighlights[linkedGroupId] = anchorId;
      if (mounted) context.push('/messages/$linkedGroupId');
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final theme = Theme.of(context);
    final userId = ref.watch(authProvider).user?.id;
    final state = ref.watch(messagesProvider(widget.conversationId));
    final conversations =
        ref.watch(conversationsProvider).valueOrNull ?? const <Conversation>[];
    final showDeleted =
        ref.watch(showDeletedMessagesProvider).valueOrNull ?? false;
    final convFromProvider = conversations
        .where((conversation) => conversation.id == widget.conversationId)
        .firstOrNull;
    final conv =
        widget.conversation ?? convFromProvider ?? _resolvedConversation;
    if (conv == null) _scheduleConversationResolve();
    final isGroup = conv?.type == 'group';
    final isChannel = conv?.type == 'channel';
    final nextUnreadChannel =
        isChannel ? _nextUnreadChannel(conversations) : null;
    final isSelf = conv?.isSelfChat ?? false;
    final otherId = conv?.otherParticipant?.id;
    final online = conv?.type == 'private' &&
        !isSelf &&
        otherId != null &&
        ref.watch(isUserOnlineProvider(otherId));
    final visiblePresence =
        otherId == null ? null : ref.watch(visiblePresenceProvider(otherId));

    String statusText() {
      if (isSelf) return "o'zingizga xabar saqlang";
      if (conv?.type == 'private') {
        if (online) return 'onlayn';
        return visiblePresence?.valueOrNull?.label ?? 'last seen recently';
      }
      if (isGroup) return 'guruh';
      if (isChannel) return 'kanal';
      return '';
    }

    String typingText() {
      final users = state.typingUsers.values.toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      if (users.isEmpty) return statusText();
      if (conv?.type == 'private') return 'yozmoqda...';
      if (users.length == 1) return '${users.first.name} yozmoqda...';
      if (users.length == 2) {
        return '${users[0].name}, ${users[1].name} yozmoqda...';
      }
      return '${users.length} kishi yozmoqda...';
    }

    // Group messages by day.
    final rawMsgs = state.messages
        .where((message) => showDeleted || !message.isDeleted)
        .toList();
    final pendingHighlight = pendingMessageHighlights[widget.conversationId];
    if (pendingHighlight != null &&
        rawMsgs.any((m) => m.id == pendingHighlight)) {
      pendingMessageHighlights.remove(widget.conversationId);
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => _scrollToMessage(pendingHighlight, rawMsgs));
    }
    final msgs = _savedTagFilter == null
        ? rawMsgs
        : rawMsgs
            .where((m) =>
                (m.metadata['saved_tags'] as List?)
                    ?.contains(_savedTagFilter) ==
                true)
            .toList();
    final replyMsg = state.replyToId != null
        ? msgs.where((m) => m.id == state.replyToId).firstOrNull
        : null;
    final editingMsg = state.editingId != null
        ? msgs.where((m) => m.id == state.editingId).firstOrNull
        : null;
    final topInset = MediaQuery.paddingOf(context).top;
    final headerHeight = 64.0 + topInset;

    return Scaffold(
      backgroundColor: c.background,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: _handleBackSwipeStart,
        onHorizontalDragUpdate: _handleBackSwipeUpdate,
        onHorizontalDragEnd: _handleBackSwipeEnd,
        onHorizontalDragCancel: () => _handleBackSwipeEnd(),
        child: Stack(children: [
          ChatWallpaper(conversationId: widget.conversationId),
          Column(children: [
            // === ChatHeader or Selection Toolbar ===
            _isSelectionMode
                ? _SelectionToolbar(
                    count: _selectedMessages.length,
                    topInset: topInset,
                    onClose: _exitSelectionMode,
                    onForward:
                        _selectedMessages.isEmpty ? null : _forwardSelected,
                    onDelete:
                        _selectedMessages.isEmpty ? null : _deleteSelected,
                  )
                : Container(
                    height: headerHeight,
                    padding: EdgeInsets.fromLTRB(8, topInset, 8, 0),
                    decoration: BoxDecoration(
                        color: c.card,
                        border: Border(bottom: BorderSide(color: c.border))),
                    child: Row(children: [
                      if (!widget.embedded)
                        IconButton(
                            icon: const Icon(LucideIcons.arrowLeft, size: 22),
                            onPressed: () => Navigator.of(context).maybePop())
                      else
                        const SizedBox(width: 12),
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            if (conv?.type == 'private' &&
                                conv?.otherParticipant != null) {
                              final usernameOrId =
                                  conv!.otherParticipant!.username ??
                                      conv.otherParticipant!.id;
                              context.push('/user/$usernameOrId');
                            } else if (conv != null &&
                                (conv.type == 'group' ||
                                    conv.type == 'channel')) {
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                backgroundColor: Colors.transparent,
                                builder: (ctx) =>
                                    _GroupProfileSheet(conv: conv),
                              );
                            }
                          },
                          child: Row(
                            children: [
                              _headerAvatar(conv, isGroup, isChannel, isSelf,
                                  online, c, theme),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                    Row(children: [
                                      Flexible(
                                          child: Text(
                                        isSelf
                                            ? 'Saqlangan xabarlar'
                                            : (conv?.title ?? 'Yuklanmoqda...'),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600),
                                      )),
                                      if (conv?.isVerified == true) ...[
                                        const SizedBox(width: 4),
                                        const VerifiedBadge(size: 14)
                                      ],
                                    ]),
                                    Text(
                                        state.isTyping
                                            ? typingText()
                                            : statusText(),
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: state.isTyping
                                                ? theme.colorScheme.primary
                                                : c.mutedForeground)),
                                  ])),
                            ],
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(LucideIcons.phone, size: 20),
                        tooltip: "Audio qo'ng'iroq",
                        onPressed: () => _startCall(type: 'audio'),
                      ),
                      IconButton(
                        icon: const Icon(LucideIcons.video, size: 20),
                        tooltip: 'Video qo\'ng\'iroq',
                        onPressed: () => _startCall(type: 'video'),
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(LucideIcons.moreVertical, size: 20),
                        color: c.card,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        elevation: 8,
                        onSelected: (val) => _handleChatMenuAction(val, c),
                        itemBuilder: (ctx) => [
                          PopupMenuItem(
                              value: 'search',
                              child: Row(children: [
                                Icon(LucideIcons.search,
                                    size: 18, color: c.foreground),
                                const SizedBox(width: 12),
                                const Text('Izlash')
                              ])),
                          PopupMenuItem(
                              value: 'pin',
                              child: Row(children: [
                                Icon(
                                    conv?.isPinned == true
                                        ? LucideIcons.pinOff
                                        : LucideIcons.pin,
                                    size: 18,
                                    color: c.foreground),
                                const SizedBox(width: 12),
                                Text(conv?.isPinned == true
                                    ? "Pin'ni olib tashlash"
                                    : "Pin qilish")
                              ])),
                          PopupMenuItem(
                              value: 'mute',
                              child: Row(children: [
                                Icon(
                                    conv?.isMuted == true
                                        ? LucideIcons.bell
                                        : LucideIcons.bellOff,
                                    size: 18,
                                    color: c.foreground),
                                const SizedBox(width: 12),
                                Text(conv?.isMuted == true
                                    ? "Ovozni yoqish"
                                    : "Ovozni o'chirish")
                              ])),
                          PopupMenuItem(
                              value: 'read',
                              child: Row(children: [
                                Icon(LucideIcons.checkCheck,
                                    size: 18, color: c.foreground),
                                const SizedBox(width: 12),
                                const Text("O'qilgan deb belgilash")
                              ])),
                          PopupMenuItem(
                              value: 'unread',
                              child: Row(children: [
                                Icon(LucideIcons.mailOpen,
                                    size: 18, color: c.foreground),
                                const SizedBox(width: 12),
                                const Text("O'qilmagan deb belgilash")
                              ])),
                          PopupMenuItem(
                              value: 'manage',
                              child: Row(children: [
                                Icon(LucideIcons.shieldCheck,
                                    size: 18, color: c.foreground),
                                const SizedBox(width: 12),
                                const Text('Boshqaruv')
                              ])),
                          PopupMenuItem(
                              value: 'export',
                              child: Row(children: [
                                Icon(LucideIcons.download,
                                    size: 18, color: c.foreground),
                                const SizedBox(width: 12),
                                const Text('Ma’lumotlarni eksport')
                              ])),
                          PopupMenuItem(
                              value: 'scheduled',
                              child: Row(children: [
                                Icon(LucideIcons.clock,
                                    size: 18, color: c.foreground),
                                const SizedBox(width: 12),
                                const Text('Rejalashtirilgan xabarlar')
                              ])),
                          PopupMenuItem(
                              value: 'archive',
                              child: Row(children: [
                                Icon(LucideIcons.archive,
                                    size: 18, color: c.foreground),
                                const SizedBox(width: 12),
                                const Text('Arxivga')
                              ])),
                          PopupMenuItem(
                              value: 'locations',
                              child: Row(children: [
                                Icon(LucideIcons.mapPin,
                                    size: 18, color: c.foreground),
                                const SizedBox(width: 12),
                                const Text('Joylashuvlar tarixi')
                              ])),
                          PopupMenuItem(
                              value: 'wallpaper',
                              child: Row(children: [
                                Icon(LucideIcons.image,
                                    size: 18, color: c.foreground),
                                const SizedBox(width: 12),
                                const Text('Fon rasmini o‘zgartirish')
                              ])),
                          const PopupMenuDivider(),
                          PopupMenuItem(
                              value: 'delete',
                              child: Row(children: [
                                const Icon(LucideIcons.trash2,
                                    size: 18, color: Colors.red),
                                const SizedBox(width: 12),
                                const Text("Suhbatni o'chirish",
                                    style: TextStyle(color: Colors.red))
                              ])),
                        ],
                      ),
                    ]),
                  ),
            if (_showMessageSearch)
              MessageSearchInConversation(
                key: ValueKey(_messageSearchInitialQuery),
                initialQuery: _messageSearchInitialQuery,
                messages: msgs
                    .where(
                        (m) => !m.isDeleted && (m.content?.isNotEmpty ?? false))
                    .map((m) => InConversationMessage(
                          id: m.id,
                          content: m.content ?? '',
                          createdAt: m.createdAt,
                        ))
                    .toList(),
                onHighlight: (id) => _scrollToMessage(id, msgs),
                onClose: () => setState(() {
                  _showMessageSearch = false;
                  _messageSearchInitialQuery = '';
                }),
              ),
            if (isSelf)
              _SavedTagFilterBar(
                selected: _savedTagFilter,
                onChanged: (tag) => setState(() => _savedTagFilter = tag),
              ),
            // === Pinned messages bar (web: PinnedMessagesBar between ChatHeader and list) ===
            // v37: real provider — `pinned_messages` Supabase table via pinnedMessagesProvider.
            Consumer(
              builder: (ctx, ref2, _) {
                final asyncPinned =
                    ref2.watch(pinnedMessagesProvider(widget.conversationId));
                return asyncPinned.when(
                  data: (items) => PinnedMessagesBar(
                    pinnedMessages: items,
                    onUnpin: (pinnedRowId) async {
                      await ref2
                          .read(messagesRepositoryProvider)
                          .unpinMessage(pinnedRowId);
                      // Refresh after unpin
                      // ignore: unused_result
                      ref2.refresh(
                          pinnedMessagesProvider(widget.conversationId));
                    },
                    onUnpinAll: () async {
                      await ref2
                          .read(messagesRepositoryProvider)
                          .unpinAllMessages(widget.conversationId);
                      // ignore: unused_result
                      ref2.refresh(
                          pinnedMessagesProvider(widget.conversationId));
                    },
                    onScrollTo: (messageId) {
                      _scrollToMessage(messageId, msgs);
                    },
                  ),
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                );
              },
            ),
            if (_uploads.isNotEmpty)
              _UploadQueueBar(
                tasks: _uploads.values.toList(),
                onCancel: _cancelUpload,
                onRetry: (id) {
                  final task = _uploads[id];
                  if (task == null) return;
                  setState(() => _uploads.remove(id));
                  task.retry();
                },
              ),
            // === Messages list with scroll-to-bottom button ===
            Expanded(
              child: Stack(
                children: [
                  // Messages list
                  state.isLoading
                      ? Center(
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                          CircularProgressIndicator(
                              color: theme.colorScheme.primary),
                          const SizedBox(height: 16),
                          Text('Xabarlar yuklanmoqda...',
                              style: TextStyle(
                                  color: c.mutedForeground, fontSize: 14)),
                        ]))
                      : msgs.isEmpty
                          ? _EmptyState(c: c)
                          : Builder(builder: (_) {
                              final msgsById = {for (final m in msgs) m.id: m};
                              return NotificationListener<
                                  OverscrollNotification>(
                                onNotification: (notification) {
                                  final target = nextUnreadChannel;
                                  if (target == null ||
                                      _nextUnreadNavigationQueued ||
                                      !_scrollController.hasClients) {
                                    return false;
                                  }
                                  final atBottom =
                                      _scrollController.position.pixels <= 12;
                                  if (atBottom &&
                                      notification.overscroll < -14) {
                                    _openNextUnreadChannel(target);
                                    return true;
                                  }
                                  return false;
                                },
                                child: ListView.builder(
                                  controller: _scrollController,
                                  reverse: true,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  itemCount: msgs.length,
                                  itemBuilder: (_, i) {
                                    final idx = msgs.length - 1 - i;
                                    final m = msgs[idx];
                                    final isMine = m.senderId == userId;
                                    // ignore: unused_local_variable
                                    final next = idx + 1 < msgs.length
                                        ? msgs[idx + 1]
                                        : null;
                                    final prev =
                                        idx - 1 >= 0 ? msgs[idx - 1] : null;
                                    final replyMessage = m.replyToId == null
                                        ? null
                                        : msgsById[m.replyToId];
                                    Offset tapPosition = Offset.zero;
                                    // Date divider when day changes.
                                    final showDayDivider = prev == null ||
                                        _isDifferentDay(
                                            prev.createdAt, m.createdAt);
                                    return Column(
                                        crossAxisAlignment: isMine
                                            ? CrossAxisAlignment.end
                                            : CrossAxisAlignment.start,
                                        children: [
                                          if (showDayDivider)
                                            _DayDivider(
                                                label: _dayLabel(m.createdAt),
                                                c: c),
                                          GestureDetector(
                                            onTapDown: (d) =>
                                                tapPosition = d.globalPosition,
                                            onTap: _isSelectionMode
                                                ? () => _toggleMessageSelection(
                                                    m.id)
                                                : () => _onLongPress(
                                                    m, isMine, tapPosition),
                                            onSecondaryTapDown: (d) =>
                                                _isSelectionMode
                                                    ? null
                                                    : _onLongPress(m, isMine,
                                                        d.globalPosition),
                                            child: Stack(
                                              children: [
                                                GestureDetector(
                                                  behavior: HitTestBehavior
                                                      .translucent,
                                                  child: AnimatedContainer(
                                                    duration: const Duration(
                                                        milliseconds: 220),
                                                    curve: Curves.easeOutCubic,
                                                    decoration: BoxDecoration(
                                                      color:
                                                          _highlightedMessageId ==
                                                                  m.id
                                                              ? theme
                                                                  .colorScheme
                                                                  .primary
                                                                  .withValues(
                                                                      alpha:
                                                                          0.12)
                                                              : Colors
                                                                  .transparent,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              14),
                                                    ),
                                                    child: MessageBubble(
                                                      message: m,
                                                      isMine: isMine,
                                                      replyMessage:
                                                          replyMessage,
                                                      onCommentTap: (conv
                                                                      ?.type ==
                                                                  'channel' &&
                                                              conv?.linkedGroupId !=
                                                                  null)
                                                          ? () =>
                                                              _openDiscussionForMessage(
                                                                  m, conv!)
                                                          : null,
                                                      onHashtagTap:
                                                          _openHashtagSearch,
                                                      onMediaPlaybackRequested:
                                                          null,
                                                      onReplyPreviewTap: m
                                                                  .replyToId ==
                                                              null
                                                          ? null
                                                          : () =>
                                                              _scrollToMessage(
                                                                m.replyToId!,
                                                                msgs,
                                                              ),
                                                      reactions:
                                                          state.reactions[
                                                                  m.id] ??
                                                              const [],
                                                      onToggleReaction:
                                                          (emoji) => _onReact(
                                                              m, emoji),
                                                      onReactionSummaryTap:
                                                          _showReactionUsers,
                                                      onPollVote: (optionId) => ref
                                                          .read(messagesProvider(
                                                                  widget
                                                                      .conversationId)
                                                              .notifier)
                                                          .votePoll(
                                                              m.id, optionId),
                                                      onTranslate: () => ref
                                                          .read(messagesProvider(
                                                                  widget
                                                                      .conversationId)
                                                              .notifier)
                                                          .translate(m.id),
                                                      onTranscribe: () => ref
                                                          .read(messagesProvider(
                                                                  widget
                                                                      .conversationId)
                                                              .notifier)
                                                          .transcribe(m.id),
                                                      onStopLiveLocation: m
                                                                      .mediaType ==
                                                                  'live_location' &&
                                                              isMine
                                                          ? () => ref
                                                              .read(messagesProvider(
                                                                      widget
                                                                          .conversationId)
                                                                  .notifier)
                                                              .stopLiveLocation(
                                                                  m.id)
                                                          : null,
                                                      onCallTap: (type) =>
                                                          _startCall(
                                                        type: type ==
                                                                CallType.video
                                                            ? 'video'
                                                            : 'audio',
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                // Selection checkbox (web isSelected indicator)
                                                if (_isSelectionMode)
                                                  Positioned(
                                                    left: isMine ? null : 8,
                                                    right: isMine ? 8 : null,
                                                    top: 8,
                                                    child: Container(
                                                      width: 24,
                                                      height: 24,
                                                      decoration: BoxDecoration(
                                                        color: _selectedMessages
                                                                .contains(m.id)
                                                            ? theme.colorScheme
                                                                .primary
                                                            : c.card,
                                                        shape: BoxShape.circle,
                                                        border: Border.all(
                                                          color: _selectedMessages
                                                                  .contains(
                                                                      m.id)
                                                              ? theme
                                                                  .colorScheme
                                                                  .primary
                                                              : c.border,
                                                          width: 2,
                                                        ),
                                                      ),
                                                      child: _selectedMessages
                                                              .contains(m.id)
                                                          ? Icon(
                                                              LucideIcons.check,
                                                              size: 16,
                                                              color: theme
                                                                  .colorScheme
                                                                  .onPrimary,
                                                            )
                                                          : null,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ]);
                                  },
                                ),
                              );
                            }),
                  if (nextUnreadChannel != null &&
                      !_showScrollToBottom &&
                      !state.isLoading)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 18,
                      child: Center(
                        child: _NextUnreadChannelPill(
                          conversation: nextUnreadChannel,
                          onTap: () => _openNextUnreadChannel(
                            nextUnreadChannel,
                          ),
                        ),
                      ),
                    ),
                  // === Scroll-to-bottom FAB ===
                  // Web: `absolute bottom-4 right-4 z-20 h-11 w-11 rounded-full bg-card border border-border shadow-lg ... transition-all active:scale-95`
                  if (_showScrollToBottom)
                    Positioned(
                      right: 16,
                      bottom: 16,
                      child: _ScrollToBottomFab(
                        unreadCount: conv?.unreadCount ?? 0,
                        onTap: () {
                          _scrollController.animateTo(
                            0,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOut,
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
            // === Reply / Editing preview ===
            if (replyMsg != null)
              _ReplyPreview(
                  message: replyMsg,
                  onCancel: () => ref
                      .read(messagesProvider(widget.conversationId).notifier)
                      .setReplyTo(null),
                  c: c,
                  theme: theme),
            if (editingMsg != null)
              _EditingPreview(
                  message: editingMsg,
                  onCancel: _cancelEditingComposer,
                  c: c,
                  theme: theme),
            // === Voice/Video recording UI ===
            if (_recordingMedia) _mediaRecorderBar(c, theme),
            // === Composer ===
            if (!_recordingMedia) _composer(c, theme),
          ]),
          if (_edgeSwipeActive)
            _BackSwipeCue(progress: _edgeSwipeProgress / 72),
        ]),
      ),
    );
  }

  bool _isDifferentDay(DateTime a, DateTime b) =>
      a.year != b.year || a.month != b.month || a.day != b.day;

  void _scrollToMessage(String messageId, List<Message> messages) {
    if (!_scrollController.hasClients || messages.isEmpty) return;
    final idx = messages.indexWhere((m) => m.id == messageId);
    if (idx < 0) {
      AppToast.info(context, 'Xabar hali cacheda topilmadi');
      return;
    }
    final reverseIdx = messages.length - 1 - idx;
    _scrollController.animateTo(
      (reverseIdx * 76.0)
          .clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
    _highlightTimer?.cancel();
    setState(() => _highlightedMessageId = messageId);
    _highlightTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted && _highlightedMessageId == messageId) {
        setState(() => _highlightedMessageId = null);
      }
    });
  }

  Widget _headerAvatar(Conversation? conv, bool isGroup, bool isChannel,
      bool isSelf, bool online, AlsamosColors c, ThemeData theme) {
    Widget avatar;
    if (isSelf || isGroup || isChannel) {
      avatar = Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
            color: theme.colorScheme.primary, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Icon(
            isSelf
                ? LucideIcons.bookmark
                : isGroup
                    ? LucideIcons.users
                    : LucideIcons.megaphone,
            size: 20,
            color: theme.colorScheme.onPrimary),
      );
    } else {
      avatar = StoryAvatarRing(
          userId: conv?.otherParticipant?.id,
          avatarUrl: conv?.displayAvatar,
          fallback: conv?.initial ?? '?',
          size: 40);
    }
    return SizedBox(
        width: 40,
        height: 40,
        child: Stack(children: [
          avatar,
          if (online)
            Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                      color: const Color(0xFF22C55E),
                      shape: BoxShape.circle,
                      border: Border.all(color: c.card, width: 2)),
                )),
        ]));
  }

  void _handleChatMenuAction(String action, AlsamosColors c) async {
    final convId = widget.conversationId;
    final notif = ref.read(conversationsProvider.notifier);

    switch (action) {
      case 'locations':
        final allMsgs = ref.read(messagesProvider(convId)).messages;
        SharedLocationHistorySheet.show(
          context: context,
          messages: allMsgs,
          onJumpToMessage: (id) => _scrollToMessage(id, allMsgs),
        );
        break;
      case 'wallpaper':
        if (!mounted) return;
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ChatWallpaperSettingsPage(conversationId: convId),
        ));
        break;
      case 'search':
        setState(() => _showMessageSearch = true);
        break;
      case 'pin':
        await notif.togglePin(convId);
        break;
      case 'mute':
        if (!mounted) return;
        await _ConversationNotificationSheet.show(context, convId);
        if (!mounted) return;
        ref.invalidate(conversationNotificationSettingsProvider(convId));
        await ref.read(conversationsProvider.notifier).load();
        break;
      case 'read':
        await notif.markAsRead(convId);
        break;
      case 'unread':
        await notif.markAsUnread(convId);
        break;
      case 'scheduled':
        ScheduledMessagesSheet.show(context, convId);
        break;
      case 'manage':
        ConversationAdminPanel.show(
          context,
          conversationId: convId,
          title: widget.conversation?.title ?? 'Suhbat',
        );
        break;
      case 'export':
        appAnalytics.track('user_data_export_requested');
        final data = await ref
            .read(conversationAdminRepositoryProvider)
            .createUserExport();
        if (mounted) {
          AppToast.info(context, 'Eksport: ${data['status'] ?? 'ready'}');
        }
        break;
      case 'archive':
        final ok = await notif.archive(convId);
        if (ok && mounted && !widget.embedded) {
          Navigator.of(context).maybePop();
        }
        break;
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (dctx) => AlertDialog(
            title: const Text("Suhbatni o'chirish?"),
            content: const Text(
                "Bu suhbat sizning xabarlar ro'yxatidan olib tashlanadi."),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dctx, false),
                  child: const Text('Bekor')),
              TextButton(
                onPressed: () => Navigator.pop(dctx, true),
                child: const Text("O'chirish",
                    style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );
        if (ok == true) {
          await notif.delete(convId);
          if (mounted && !widget.embedded) {
            Navigator.of(context).maybePop();
          }
        }
        break;
    }
  }

  Future<void> _reportMessage(Message message) async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(
            leading: Icon(LucideIcons.flag),
            title: Text('Shikoyat sababi'),
          ),
          for (final item in const [
            ('spam', 'Spam'),
            ('violence', 'Zo‘ravonlik'),
            ('adult', 'Nojo‘ya kontent'),
            ('scam', 'Firibgarlik'),
            ('other', 'Boshqa'),
          ])
            ListTile(
              title: Text(item.$2),
              onTap: () => Navigator.pop(ctx, item.$1),
            ),
        ]),
      ),
    );
    if (reason == null) return;
    await ref.read(conversationAdminRepositoryProvider).reportMessage(
          conversationId: widget.conversationId,
          messageId: message.id,
          reason: reason,
        );
    appAnalytics.track('message_reported',
        properties: {'conversation_id': widget.conversationId});
    if (mounted) {
      AppToast.success(context, 'Shikoyat moderatsiyaga yuborildi');
    }
  }

  // Voice/Video recording bar (UI scaffold; full record requires record package).
  Widget _mediaRecorderBar(AlsamosColors c, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
          color: c.card, border: Border(top: BorderSide(color: c.border))),
      child: SafeArea(
          top: false,
          child: Row(children: [
            IconButton(
              icon: const Icon(LucideIcons.trash2, color: Colors.red),
              onPressed: _cancelRecording,
            ),
            const SizedBox(width: 8),
            AnimatedBuilder(
                animation: _recPulse!,
                builder: (_, __) => Container(
                      width: 12 + 4 * _recPulse!.value,
                      height: 12 + 4 * _recPulse!.value,
                      decoration: BoxDecoration(
                          color: Colors.red
                              .withValues(alpha: 0.7 + 0.3 * _recPulse!.value),
                          shape: BoxShape.circle),
                    )),
            const SizedBox(width: 12),
            Expanded(
              child: Row(
                children: [
                  Text(
                    '${_voiceDuration.inMinutes.toString().padLeft(2, '0')}:${(_voiceDuration.inSeconds % 60).toString().padLeft(2, '0')}',
                    style: TextStyle(
                        color: c.foreground,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _RecordingWaveform(
                      values: _liveWaveform,
                      color: theme.colorScheme.primary,
                      mutedColor: c.mutedForeground.withValues(alpha: 0.28),
                    ),
                  ),
                ],
              ),
            ),
            Text(_isMediaVideoMode ? 'Video...' : 'Ovoz...',
                style: TextStyle(color: c.mutedForeground)),
            const SizedBox(width: 12),
            Container(
              decoration: BoxDecoration(
                  color: theme.colorScheme.primary, shape: BoxShape.circle),
              child: IconButton(
                icon: const Icon(LucideIcons.send, color: Colors.white),
                onPressed: _stopAndSendRecording,
              ),
            ),
          ])),
    );
  }

  Widget _composer(AlsamosColors c, ThemeData theme) {
    final primary = theme.colorScheme.primary;
    final isDark = theme.brightness == Brightness.dark;
    final compact = MediaQuery.sizeOf(context).width < 560;
    final actionSize = compact ? 44.0 : 48.0;
    final inputMaxHeight = compact ? 282.0 : 324.0;
    final composerSurface = c.card.withValues(alpha: isDark ? 0.78 : 0.86);
    final inputSurface = c.muted.withValues(alpha: isDark ? 0.52 : 0.74);
    final subtleShadow = [
      BoxShadow(
        color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.08),
        blurRadius: 24,
        offset: const Offset(0, -8),
      ),
    ];

    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              decoration: BoxDecoration(
                color: composerSurface,
                border: Border(top: BorderSide(color: c.border)),
                boxShadow: subtleShadow,
              ),
              child: SafeArea(
                top: false,
                minimum: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _ComposerCircleButton(
                      icon: LucideIcons.plus,
                      foreground: c.mutedForeground,
                      background: c.muted.withValues(alpha: 0.48),
                      borderColor: c.border,
                      size: actionSize,
                      onPressed: _showAttachmentMenu,
                    ),
                    SizedBox(width: compact ? 6 : 8),
                    Expanded(
                      child: Container(
                        constraints: BoxConstraints(
                          minHeight: actionSize,
                          maxHeight: inputMaxHeight,
                        ),
                        decoration: BoxDecoration(
                          color: inputSurface,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black
                                  .withValues(alpha: isDark ? 0.10 : 0.04),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Stack(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 5, 72, 5),
                              child: Shortcuts(
                                shortcuts: {
                                  const SingleActivator(
                                          LogicalKeyboardKey.enter):
                                      const _SendMessageIntent(),
                                  const SingleActivator(
                                          LogicalKeyboardKey.numpadEnter):
                                      const _SendMessageIntent(),
                                },
                                child: Actions(
                                  actions: {
                                    _SendMessageIntent:
                                        CallbackAction<_SendMessageIntent>(
                                      onInvoke: (_) {
                                        if (_controller.text
                                            .trim()
                                            .isNotEmpty) {
                                          _send();
                                        }
                                        return null;
                                      },
                                    ),
                                  },
                                  child: CanonicalRichComposerField(
                                    controller: _controller,
                                    focusNode: _focusNode,
                                    minLines: 1,
                                    maxLines: compact ? 10 : 12,
                                    keyboardType: TextInputType.multiline,
                                    textCapitalization:
                                        TextCapitalization.sentences,
                                    style: TextStyle(
                                      color: c.foreground,
                                      fontSize: 16,
                                      height: 1.28,
                                    ),
                                    cursorColor: primary,
                                    decoration: InputDecoration(
                                      hintText: 'Xabar yozing...',
                                      hintStyle: TextStyle(
                                        color: c.mutedForeground
                                            .withValues(alpha: 0.82),
                                      ),
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      disabledBorder: InputBorder.none,
                                      errorBorder: InputBorder.none,
                                      focusedErrorBorder: InputBorder.none,
                                      isDense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              vertical: 8),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              right: 6,
                              bottom: 5,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _ComposerIconButton(
                                    icon: LucideIcons.sticker,
                                    color: c.mutedForeground,
                                    onPressed: _showStickerPicker,
                                  ),
                                  _ComposerIconButton(
                                    icon: LucideIcons.smile,
                                    color: c.mutedForeground,
                                    onPressed: _pickEmojiForComposer,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(width: compact ? 6 : 8),
                    // v33: send vs mic switcher (autocomplete overlay positioning anchor)
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 150),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      child: _hasText
                          ? GestureDetector(
                              key: const ValueKey('send'),
                              onLongPress:
                                  _editingComposer ? _send : _showSendOptions,
                              child: _ComposerCircleButton(
                                icon: LucideIcons.send,
                                foreground: Colors.white,
                                background: primary,
                                borderColor: Colors.transparent,
                                shadowColor: primary.withValues(alpha: 0.34),
                                size: actionSize,
                                onPressed: _send,
                              ),
                            )
                          : GestureDetector(
                              key:
                                  ValueKey(_isMediaVideoMode ? 'video' : 'mic'),
                              onTap: () {
                                HapticFeedback.lightImpact();
                                setState(() =>
                                    _isMediaVideoMode = !_isMediaVideoMode);
                              },
                              onLongPressStart: (_) {
                                HapticFeedback.mediumImpact();
                                if (!_isMediaVideoMode) {
                                  _startRecording();
                                } else {
                                  _pickAndSendMedia(ImageSource.camera,
                                      isVideo: true);
                                }
                              },
                              child: _ComposerCircleButton(
                                icon: _isMediaVideoMode
                                    ? LucideIcons.camera
                                    : LucideIcons.mic,
                                foreground: c.mutedForeground,
                                background: c.muted.withValues(alpha: 0.58),
                                borderColor: c.border,
                                size: actionSize,
                                onPressed: null,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // v33: autocomplete overlays — composer ustida ko'rinadi (web ekvivalent).
        // `HashtagAutocomplete`/`MentionAutocomplete` o'zlari `Positioned` qaytaradi,
        // shuning uchun ular bevosita Stack farzandlari.
        if (_hashtagQuery != null)
          HashtagAutocomplete(
            conversationId: widget.conversationId,
            query: _hashtagQuery!,
            left: 56,
            right: 56,
            top: -240,
            onSelect: (tag) => _applyAutocomplete(tag, '#'),
            onClose: _closeAutocomplete,
          ),
        if (_mentionQuery != null)
          MentionAutocomplete(
            conversationId: widget.conversationId,
            query: _mentionQuery!,
            left: 56,
            right: 56,
            top: -240,
            onSelect: (username) => _applyAutocomplete(username, '@'),
            onClose: _closeAutocomplete,
          ),
      ],
    );
  }

  Future<void> _pickEmojiForComposer() async {
    final emoji = await EmojiPickerSheet.show(context);
    if (emoji == null || !mounted) return;
    final sel = _controller.selection;
    final base = _controller.text;
    final pos = sel.isValid ? sel.start : base.length;
    final newText = base.substring(0, pos) + emoji + base.substring(pos);
    _controller.text = newText;
    _controller.selection = TextSelection.collapsed(offset: pos + emoji.length);
  }
}

class _ComposerIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  const _ComposerIconButton({
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 34,
      child: IconButton(
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 34),
        icon: Icon(icon, color: color, size: 19),
        onPressed: onPressed,
      ),
    );
  }
}

class _ComposerCircleButton extends StatelessWidget {
  final IconData icon;
  final Color foreground;
  final Color background;
  final Color borderColor;
  final Color? shadowColor;
  final double size;
  final VoidCallback? onPressed;

  const _ComposerCircleButton({
    required this.icon,
    required this.foreground,
    required this.background,
    required this.borderColor,
    this.shadowColor,
    this.size = 48,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final button = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background,
        shape: BoxShape.circle,
        border: Border.all(color: borderColor),
        boxShadow: shadowColor == null
            ? null
            : [
                BoxShadow(
                  color: shadowColor!,
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: Icon(icon, color: foreground, size: size <= 44 ? 20 : 21),
    );

    if (onPressed == null) return button;
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: button,
      ),
    );
  }
}

class _RecordingWaveform extends StatelessWidget {
  final List<int> values;
  final Color color;
  final Color mutedColor;

  const _RecordingWaveform({
    required this.values,
    required this.color,
    required this.mutedColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: CustomPaint(
        painter: _RecordingWaveformPainter(
          values: values.isEmpty ? List<int>.filled(24, 18) : values,
          color: color,
          mutedColor: mutedColor,
        ),
      ),
    );
  }
}

class _RecordingWaveformPainter extends CustomPainter {
  final List<int> values;
  final Color color;
  final Color mutedColor;

  const _RecordingWaveformPainter({
    required this.values,
    required this.color,
    required this.mutedColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty || size.width <= 0) return;
    const gap = 2.0;
    final count = values.length;
    final barWidth =
        ((size.width - gap * (count - 1)) / count).clamp(2.0, 5.0).toDouble();
    final startX = (size.width - (barWidth * count + gap * (count - 1)))
        .clamp(0.0, size.width)
        .toDouble();
    final activePaint = Paint()..color = color;
    final mutedPaint = Paint()..color = mutedColor;
    for (var i = 0; i < count; i++) {
      final normalized = values[i].clamp(12, 100) / 100;
      final height =
          (size.height * normalized).clamp(4.0, size.height).toDouble();
      final x = startX + i * (barWidth + gap);
      final rect = Rect.fromLTWH(
        x,
        (size.height - height) / 2,
        barWidth,
        height,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        i > count - 6 ? activePaint : mutedPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RecordingWaveformPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.color != color ||
      oldDelegate.mutedColor != mutedColor;
}

class _DayDivider extends StatelessWidget {
  final String label;
  final AlsamosColors c;
  const _DayDivider({required this.label, required this.c});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(children: [
        Expanded(child: Divider(color: c.border)),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
              color: c.muted, borderRadius: BorderRadius.circular(10)),
          child: Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: c.mutedForeground,
                  fontWeight: FontWeight.w500)),
        ),
        const SizedBox(width: 12),
        Expanded(child: Divider(color: c.border)),
      ]),
    );
  }
}

class _ReplyPreview extends StatelessWidget {
  final Message message;
  final VoidCallback onCancel;
  final AlsamosColors c;
  final ThemeData theme;
  const _ReplyPreview(
      {required this.message,
      required this.onCancel,
      required this.c,
      required this.theme});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
          color: c.card, border: Border(top: BorderSide(color: c.border))),
      child: Row(children: [
        Container(width: 3, height: 36, color: theme.colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(message.sender?.displayName ?? 'Javob berilmoqda',
              style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          Text(message.content ?? '[media]',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c.mutedForeground, fontSize: 13)),
        ])),
        IconButton(
            icon: Icon(LucideIcons.x, size: 18, color: c.mutedForeground),
            onPressed: onCancel),
      ]),
    );
  }
}

class _EditingPreview extends StatelessWidget {
  final Message message;
  final VoidCallback onCancel;
  final AlsamosColors c;
  final ThemeData theme;
  const _EditingPreview(
      {required this.message,
      required this.onCancel,
      required this.c,
      required this.theme});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
          color: c.card, border: Border(top: BorderSide(color: c.border))),
      child: Row(children: [
        Icon(LucideIcons.pencil, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Tahrirlash',
              style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          Text(message.content ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c.mutedForeground, fontSize: 13)),
        ])),
        IconButton(
            icon: Icon(LucideIcons.x, size: 18, color: c.mutedForeground),
            onPressed: onCancel),
      ]),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final AlsamosColors c;
  const _EmptyState({required this.c});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              theme.colorScheme.primary.withValues(alpha: 0.1),
              theme.colorScheme.primary.withValues(alpha: 0.05),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shape: BoxShape.circle,
        ),
        child: Icon(LucideIcons.messageCircle,
            size: 40, color: theme.colorScheme.primary),
      ),
      const SizedBox(height: 24),
      Text('Hali xabarlar yo\'q',
          style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.bold, color: c.foreground)),
      const SizedBox(height: 8),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48),
        child: Text(
          'Birinchi xabarni yuboring va suhbatni boshlang',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: c.mutedForeground, height: 1.4),
        ),
      ),
    ]));
  }
}

// =====================================================================
// _ScrollToBottomFab — mirrors web `<button class="absolute bottom-4 right-4 z-20 h-11 w-11 rounded-full bg-card border border-border shadow-lg ... transition-all active:scale-95">`
// =====================================================================
class _BackSwipeCue extends StatelessWidget {
  final double progress;
  const _BackSwipeCue({required this.progress});

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final value = progress.clamp(0.0, 1.0);
    return Positioned(
      left: 12 + (value * 12),
      top: MediaQuery.sizeOf(context).height * 0.5 - 26,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: value,
          duration: const Duration(milliseconds: 80),
          child: Transform.scale(
            scale: 0.88 + (value * 0.18),
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: c.card.withValues(alpha: 0.92),
                shape: BoxShape.circle,
                border: Border.all(color: c.border),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(
                LucideIcons.arrowLeft,
                size: 24,
                color: c.foreground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NextUnreadChannelPill extends StatefulWidget {
  final Conversation conversation;
  final VoidCallback onTap;

  const _NextUnreadChannelPill({
    required this.conversation,
    required this.onTap,
  });

  @override
  State<_NextUnreadChannelPill> createState() => _NextUnreadChannelPillState();
}

class _NextUnreadChannelPillState extends State<_NextUnreadChannelPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: widget.onTap,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 360),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: c.card.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: c.border),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1F000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _controller,
                builder: (context, child) => Transform.translate(
                  offset: Offset(0, -2 * _controller.value),
                  child: child,
                ),
                child: Icon(
                  LucideIcons.arrowUp,
                  size: 17,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  "Keyingi o'qilmagan kanal",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.foreground,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  widget.conversation.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.mutedForeground,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (widget.conversation.visibleUnreadCount > 0) ...[
                const SizedBox(width: 8),
                Container(
                  constraints: const BoxConstraints(minWidth: 20),
                  height: 20,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    widget.conversation.visibleUnreadCount > 99
                        ? '99+'
                        : '${widget.conversation.visibleUnreadCount}',
                    style: TextStyle(
                      color: theme.colorScheme.onPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ScrollToBottomFab extends StatefulWidget {
  final int unreadCount;
  final VoidCallback onTap;
  const _ScrollToBottomFab({required this.unreadCount, required this.onTap});

  @override
  State<_ScrollToBottomFab> createState() => _ScrollToBottomFabState();
}

class _ScrollToBottomFabState extends State<_ScrollToBottomFab> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final theme = Theme.of(context);
    return SizedBox(
      // web h-11 w-11 = 44x44 (button), but with badge we need overflow allowance
      width: 52,
      height: 52,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // FAB button — h-11 w-11 = 44x44
          Positioned(
            left: 4,
            top: 4,
            child: GestureDetector(
              onTapDown: (_) => setState(() => _pressed = true),
              onTapUp: (_) {
                setState(() => _pressed = false);
                widget.onTap();
              },
              onTapCancel: () => setState(() => _pressed = false),
              child: AnimatedScale(
                scale: _pressed ? 0.95 : 1.0, // web active:scale-95
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: c.card,
                    shape: BoxShape.circle,
                    border: Border.all(color: c.border),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x1A000000), // web shadow-lg
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    LucideIcons.arrowDown,
                    color: c.foreground,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
          // Unread badge — web: -top-1 -right-1 min-w-[20px] h-5 px-1.5 rounded-full bg-primary text-[11px] font-semibold
          if (widget.unreadCount > 0)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                constraints: const BoxConstraints(minWidth: 20),
                height: 20,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(999),
                ),
                alignment: Alignment.center,
                child: Text(
                  widget.unreadCount > 99 ? '99+' : '${widget.unreadCount}',
                  style: TextStyle(
                    color: theme.colorScheme.onPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    height: 1.0,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// =====================================================================
// _SelectionToolbar — mirrors web `<div class="bg-card/90 backdrop-blur-xl border-b border-border ... animate-in slide-in-from-top duration-200">`
// =====================================================================
class _SelectionToolbar extends StatefulWidget {
  final int count;
  final double topInset;
  final VoidCallback onClose;
  final VoidCallback? onForward;
  final VoidCallback? onDelete;
  const _SelectionToolbar({
    required this.count,
    this.topInset = 0,
    required this.onClose,
    this.onForward,
    this.onDelete,
  });

  @override
  State<_SelectionToolbar> createState() => _SelectionToolbarState();
}

class _SelectionToolbarState extends State<_SelectionToolbar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 200), // web duration-200
      vsync: this,
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -1), // web slide-in-from-top
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    return SlideTransition(
      position: _slide,
      child: ClipRect(
        child: BackdropFilter(
          // web backdrop-blur-xl ≈ blur(24px)
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            height: 64 + widget.topInset,
            padding: EdgeInsets.fromLTRB(8, widget.topInset, 8, 0),
            decoration: BoxDecoration(
              color: c.card.withValues(alpha: 0.9), // web bg-card/90
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(LucideIcons.x, size: 22),
                  onPressed: widget.onClose,
                  tooltip: 'Bekor qilish',
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.count > 0
                        ? '${widget.count} ta tanlandi'
                        : 'Xabarlarni tanlang',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  icon: const Icon(LucideIcons.share2, size: 20),
                  tooltip: 'Yo\'naltirish',
                  onPressed: widget.onForward,
                ),
                IconButton(
                  icon: const Icon(LucideIcons.trash2,
                      size: 20, color: Color(0xFFEF4444)),
                  tooltip: "O'chirish",
                  onPressed: widget.onDelete,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UploadCancelled implements Exception {
  const _UploadCancelled();
  @override
  String toString() => 'Upload bekor qilindi';
}

class _ChatUploadResult {
  const _ChatUploadResult({
    required this.url,
    required this.bucket,
    required this.path,
    required this.contentType,
  });

  final String url;
  final String bucket;
  final String path;
  final String contentType;
}

class _UploadTask {
  const _UploadTask({
    required this.id,
    required this.label,
    required this.retry,
    this.progress = 0.02,
    this.error,
    this.cancelled = false,
  });

  final String id;
  final String label;
  final Future<void> Function() retry;
  final double progress;
  final String? error;
  final bool cancelled;

  _UploadTask copyWith({
    double? progress,
    String? error,
    bool? cancelled,
  }) =>
      _UploadTask(
        id: id,
        label: label,
        retry: retry,
        progress: progress ?? this.progress,
        error: error,
        cancelled: cancelled ?? this.cancelled,
      );
}

class _PreparedVideoMessage {
  final String? localThumbPath;
  final String? thumbnailPreviewUrl;
  final Duration duration;
  final int? width;
  final int? height;
  final int sizeBytes;

  const _PreparedVideoMessage({
    required this.localThumbPath,
    required this.thumbnailPreviewUrl,
    required this.duration,
    required this.width,
    required this.height,
    required this.sizeBytes,
  });
}

class _UploadQueueBar extends StatelessWidget {
  const _UploadQueueBar({
    required this.tasks,
    required this.onCancel,
    required this.onRetry,
  });

  final List<_UploadTask> tasks;
  final ValueChanged<String> onCancel;
  final ValueChanged<String> onRetry;

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final task = tasks.last;
    final failed = task.error != null || task.cancelled;
    return Material(
      color: c.card.withValues(alpha: 0.98),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
        child: Row(children: [
          Icon(
            failed ? LucideIcons.circleAlert : LucideIcons.upload,
            size: 18,
            color: failed ? Colors.red : Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  failed ? (task.error ?? 'Bekor qilindi') : task.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: failed ? Colors.red : c.foreground,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    minHeight: 4,
                    value: failed ? 1 : task.progress.clamp(0.02, 0.98),
                    backgroundColor: c.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (failed)
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () => onRetry(task.id),
              icon: const Icon(LucideIcons.refreshCw, size: 18),
            )
          else
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () => onCancel(task.id),
              icon: const Icon(LucideIcons.x, size: 18),
            ),
        ]),
      ),
    );
  }
}

class _SavedTagFilterBar extends ConsumerWidget {
  const _SavedTagFilterBar({
    required this.selected,
    required this.onChanged,
  });

  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(authProvider).user?.id;
    if (userId == null) return const SizedBox.shrink();
    return FutureBuilder<List<String>>(
      future: ref.read(messagesRepositoryProvider).savedMessageTags(userId),
      builder: (context, snap) {
        final tags = snap.data ?? const [];
        if (tags.isEmpty) return const SizedBox.shrink();
        final c = AlsamosColors.of(context);
        return Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: c.card.withValues(alpha: 0.96),
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              ChoiceChip(
                label: const Text('Hammasi'),
                selected: selected == null,
                onSelected: (_) => onChanged(null),
              ),
              const SizedBox(width: 6),
              for (final tag in tags) ...[
                ChoiceChip(
                  label: Text('#$tag'),
                  selected: selected == tag,
                  onSelected: (_) => onChanged(tag),
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _MessageMenuAction {
  final String value;
  final IconData icon;
  final String label;
  final bool destructive;
  final bool separated;

  const _MessageMenuAction(
    this.value,
    this.icon,
    this.label, {
    this.destructive = false,
    this.separated = false,
  });
}

class _MessageReactionMenuBar extends StatelessWidget {
  final ValueChanged<String> onReact;
  final VoidCallback onMore;
  const _MessageReactionMenuBar({
    required this.onReact,
    required this.onMore,
  });

  static const _emojis = [
    '\u{1F44D}',
    '\u{1F602}',
    '\u{2764}\u{FE0F}',
    '\u{1F604}',
    '\u{1F91D}',
    '\u{1F525}',
  ];

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    return _MenuEntrance(
      child: Material(
        color: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(29),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
            child: Container(
              height: 54,
              padding: const EdgeInsets.symmetric(horizontal: 7),
              decoration: BoxDecoration(
                color: c.card.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(29),
                border: Border.all(color: c.border.withValues(alpha: 0.46)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.16),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  for (final emoji in _emojis)
                    InkWell(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        onReact(emoji);
                      },
                      borderRadius: BorderRadius.circular(24),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        curve: Curves.easeOutCubic,
                        width: 48,
                        height: 46,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(shape: BoxShape.circle),
                        child: AnimatedEmoji(
                          emoji: emoji,
                          size: 34,
                          animate: true,
                          replayOnTap: false,
                        ),
                      ),
                    ),
                  InkWell(
                    onTap: onMore,
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      width: 48,
                      height: 46,
                      margin: const EdgeInsets.only(left: 2),
                      decoration: BoxDecoration(
                        color: c.muted.withValues(alpha: 0.62),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(LucideIcons.chevronDown,
                          size: 18, color: c.mutedForeground),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageActionPanel extends StatelessWidget {
  final String title;
  final List<_MessageMenuAction> actions;
  final double maxHeight;
  final ValueChanged<String?> onSelected;

  const _MessageActionPanel({
    required this.title,
    required this.actions,
    required this.maxHeight,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    return _MenuEntrance(
      child: Material(
        color: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
            child: Container(
              constraints: BoxConstraints(maxHeight: maxHeight),
              decoration: BoxDecoration(
                color: c.card.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: c.border.withValues(alpha: 0.48)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 28,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Row(children: [
                      Icon(LucideIcons.checkCheck,
                          size: 16, color: c.mutedForeground),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: c.mutedForeground,
                          ),
                        ),
                      ),
                    ]),
                  ),
                  Divider(height: 1, color: c.border.withValues(alpha: 0.5)),
                  for (final action in actions) ...[
                    if (action.separated)
                      Divider(
                          height: 7, color: c.border.withValues(alpha: 0.5)),
                    _TelegramMenuRow(
                      icon: action.icon,
                      label: action.label,
                      c: c,
                      destructive: action.destructive,
                      onTap: () => onSelected(action.value),
                    ),
                  ],
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuEntrance extends StatelessWidget {
  final Widget child;
  const _MenuEntrance({required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 170),
      curve: Curves.easeOutCubic,
      builder: (_, value, child) => Transform.scale(
        scale: 0.96 + value * 0.04,
        alignment: Alignment.topCenter,
        child: Opacity(opacity: value, child: child),
      ),
      child: child,
    );
  }
}

class _TelegramMenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final AlsamosColors? c;
  final bool destructive;
  final VoidCallback? onTap;
  const _TelegramMenuRow({
    required this.icon,
    required this.label,
    this.c,
    this.destructive = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = c ?? AlsamosColors.of(context);
    final color = destructive ? const Color(0xFFEF4444) : colors.foreground;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.15,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _GroupProfileSheet extends StatelessWidget {
  final Conversation conv;
  const _GroupProfileSheet({required this.conv});

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final theme = Theme.of(context);
    final isChannel = conv.type == 'channel';

    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 20),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
                color: c.border, borderRadius: BorderRadius.circular(2)),
          ),
          CircleAvatar(
            radius: 50,
            backgroundImage:
                (conv.avatarUrl != null && conv.avatarUrl!.isNotEmpty)
                    ? NetworkImage(conv.avatarUrl!)
                    : null,
            backgroundColor: theme.colorScheme.primary,
            child: (conv.avatarUrl == null || conv.avatarUrl!.isEmpty)
                ? Text(
                    conv.title.isNotEmpty ? conv.title[0].toUpperCase() : '?',
                    style: const TextStyle(
                        fontSize: 40,
                        color: Colors.white,
                        fontWeight: FontWeight.bold))
                : null,
          ),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Flexible(
                child: Text(conv.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold))),
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'QR code',
              onPressed: () => UsernameQrDialog.show(
                context,
                title: conv.title,
                subtitle: isChannel ? 'Kanal' : 'Guruh',
                data:
                    'https://alsamos.app/${isChannel ? 'channel' : 'group'}/${conv.id}',
                avatarUrl: conv.avatarUrl,
              ),
              icon:
                  Icon(LucideIcons.qrCode, size: 18, color: c.mutedForeground),
            ),
          ]),
          const SizedBox(height: 4),
          Text(isChannel ? 'Kanal' : 'Guruh',
              style: TextStyle(fontSize: 14, color: c.mutedForeground)),
          const SizedBox(height: 24),
          Divider(color: c.border, height: 1),
          if (conv.description != null && conv.description!.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tavsif',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.primary)),
                  const SizedBox(height: 8),
                  Text(conv.description!, style: const TextStyle(fontSize: 15)),
                ],
              ),
            ),
            Divider(color: c.border, height: 1),
          ],
          ListTile(
            leading: Icon(LucideIcons.bell, color: c.foreground),
            title: const Text('Bildirishnomalar'),
            trailing: Switch(value: true, onChanged: (_) {}),
          ),
          ListTile(
            leading: Icon(LucideIcons.image, color: c.foreground),
            title: const Text('Media, fayllar va havolalar'),
            trailing: const Icon(LucideIcons.chevronRight, size: 20),
          ),
          ListTile(
            leading: Icon(LucideIcons.users, color: c.foreground),
            title: const Text('A\'zolar'),
            trailing: const Icon(LucideIcons.chevronRight, size: 20),
          ),
          ListTile(
            leading: const Icon(LucideIcons.logOut, color: Colors.red),
            title: Text(isChannel ? 'Kanaldan chiqish' : 'Guruhdan chiqish',
                style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class _ConversationNotificationSheet extends ConsumerWidget {
  const _ConversationNotificationSheet({required this.conversationId});

  final String conversationId;

  static Future<void> show(BuildContext context, String conversationId) {
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: AlsamosColors.of(context).card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) =>
          _ConversationNotificationSheet(conversationId: conversationId),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AlsamosColors.of(context);
    final settingsAsync =
        ref.watch(conversationNotificationSettingsProvider(conversationId));
    final repo = ref.read(conversationNotificationSettingsRepositoryProvider);

    Future<void> apply(Future<void> Function() action) async {
      try {
        await action();
        ref.invalidate(
            conversationNotificationSettingsProvider(conversationId));
        await ref.read(conversationsProvider.notifier).load();
        if (context.mounted) Navigator.of(context).pop();
      } catch (e) {
        if (context.mounted) {
          AppToast.error(context, friendlyError(e));
        }
      }
    }

    Widget option({
      required IconData icon,
      required String title,
      String? subtitle,
      required VoidCallback onTap,
      bool selected = false,
    }) {
      return ListTile(
        leading: Icon(icon, color: selected ? c.primary : c.foreground),
        title: Text(title,
            style: TextStyle(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
        subtitle: subtitle == null
            ? null
            : Text(subtitle, style: TextStyle(color: c.mutedForeground)),
        trailing: selected ? Icon(LucideIcons.check, color: c.primary) : null,
        onTap: onTap,
      );
    }

    return settingsAsync.when(
      loading: () => const SizedBox(
        height: 220,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Sozlamalar yuklanmadi',
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: c.foreground)),
            const SizedBox(height: 8),
            Text('$error', style: TextStyle(color: c.mutedForeground)),
          ],
        ),
      ),
      data: (settings) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                title: const Text('Suhbat bildirishnomalari',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                subtitle: Text(settings.subtitle,
                    style: TextStyle(color: c.mutedForeground)),
              ),
              option(
                icon: LucideIcons.bell,
                title: 'Yoqilgan',
                subtitle: 'Barcha xabarlar uchun bildirishnoma',
                selected: !settings.isMuted && !settings.mentionsOnly,
                onTap: () => apply(() => repo.enableAll(conversationId)),
              ),
              option(
                icon: LucideIcons.atSign,
                title: 'Faqat mentionlar',
                subtitle: '@username yoki javoblar kelganda',
                selected: settings.mentionsOnly,
                onTap: () => apply(() => repo.setMentionsOnly(conversationId)),
              ),
              option(
                icon: LucideIcons.clock3,
                title: '1 soatga ovozsiz',
                onTap: () => apply(() => repo.setMuted(
                      conversationId,
                      duration: const Duration(hours: 1),
                    )),
              ),
              option(
                icon: LucideIcons.moon,
                title: '8 soatga ovozsiz',
                onTap: () => apply(() => repo.setMuted(
                      conversationId,
                      duration: const Duration(hours: 8),
                    )),
              ),
              option(
                icon: LucideIcons.calendarDays,
                title: '2 kunga ovozsiz',
                onTap: () => apply(() => repo.setMuted(
                      conversationId,
                      duration: const Duration(days: 2),
                    )),
              ),
              option(
                icon: LucideIcons.bellOff,
                title: 'Doimiy ovozsiz',
                selected: settings.muteForever,
                onTap: () =>
                    apply(() => repo.setMuted(conversationId, forever: true)),
              ),
              SwitchListTile.adaptive(
                value: settings.previewEnabled,
                activeThumbColor: c.primary,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                secondary:
                    Icon(LucideIcons.messageSquareText, color: c.foreground),
                title: const Text('Matn preview ko\'rsatish'),
                subtitle: Text('Push va lokal bildirishnomalarda xabar matni',
                    style: TextStyle(color: c.mutedForeground)),
                onChanged: (value) =>
                    apply(() => repo.setPreviewEnabled(conversationId, value)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
