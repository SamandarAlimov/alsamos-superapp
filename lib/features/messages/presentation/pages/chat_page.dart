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
import '../../../../shared/widgets/user_avatar.dart';
import '../../../../shared/widgets/username_qr_dialog.dart';
import '../../../../shared/widgets/verified_badge.dart';
import '../../data/models/conversation_model.dart';
import '../../data/models/message_model.dart';
import '../providers/conversations_provider.dart';
import '../providers/chat_background_provider.dart';
import '../providers/messages_provider.dart';
import '../widgets/call_history_message.dart';
import '../widgets/message_bubble.dart';
import '../widgets/composer_extras.dart';
import '../widgets/emoji_picker_sheet.dart';
import '../widgets/pinned_messages_bar.dart';
import '../providers/pinned_messages_provider.dart';
import '../providers/online_status_provider.dart';
import '../widgets/scheduled_messages_sheet.dart';
import '../widgets/message_search_in_conversation.dart';
import '../widgets/mini_audio_player.dart';
import '../../../../shared/widgets/gif_picker.dart';
import '../../../../shared/widgets/hashtag_autocomplete.dart';
import '../../../../shared/widgets/message_reactions_bar.dart';
import 'webrtc_call_page.dart';
import 'dart:io' show File;
import 'package:file_picker/file_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:record/record.dart';
import 'dart:async';
import 'package:path_provider/path_provider.dart';
import '../../../../shared/widgets/mention_autocomplete.dart';

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

class _ChatPageState extends ConsumerState<ChatPage> with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  bool _hasText = false;
  bool _recordingMedia = false;
  bool _isMediaVideoMode = false;
  bool _showScrollToBottom = false;
  
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
  Message? _activeMediaMessage;

  @override
  void initState() {
    super.initState();
    if (chatDrafts.containsKey(widget.conversationId)) {
      _controller.text = chatDrafts[widget.conversationId]!;
      _hasText = _controller.text.trim().isNotEmpty;
    }
    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
      _updateAutocomplete();
    });
    // Scroll listener for scroll-to-bottom button
    _scrollController.addListener(_onScroll);
    // Initialize recording pulse animation
    _recPulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
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

  bool _isPlayableMedia(Message message) {
    final type = message.mediaType;
    return message.mediaUrl != null &&
        (type == 'audio' ||
            type == 'voice' ||
            type == 'video' ||
            type == 'video_note');
  }

  List<Message> _playableMessages(List<Message> messages) =>
      messages.where(_isPlayableMedia).toList();

  void _openMiniPlayer(Message message) {
    if (!_isPlayableMedia(message)) return;
    setState(() => _activeMediaMessage = message);
  }

  void _playAdjacent(List<Message> messages, int direction) {
    final playable = _playableMessages(messages);
    if (playable.isEmpty) return;
    final current = _activeMediaMessage;
    final index =
        current == null ? -1 : playable.indexWhere((m) => m.id == current.id);
    final nextIndex = index < 0
        ? (direction > 0 ? 0 : playable.length - 1)
        : (index + direction).clamp(0, playable.length - 1);
    setState(() => _activeMediaMessage = playable[nextIndex]);
  }

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
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      chatDrafts[widget.conversationId] = text;
    } else {
      chatDrafts.remove(widget.conversationId);
    }
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _recPulse?.dispose();
    _recordTimer?.cancel();
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
        final path = '${dir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _audioRecorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
        setState(() {
          _recordingMedia = true;
          _isMediaVideoMode = false;
          _voiceDuration = Duration.zero;
        });
        _recordTimer?.cancel();
        _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          setState(() {
            _voiceDuration = Duration(seconds: timer.tick);
          });
        });
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Mikrofon ruxsati yo'q")));
      }
    } catch (e) {
      debugPrint('Start recording error: $e');
    }
  }

  Future<String> _uploadChatMedia(
    Uint8List bytes,
    String path, {
    String? contentType,
  }) async {
    final sb = Supabase.instance.client;
    Object? firstError;
    for (final bucket in const ['chat-media', 'message-attachments']) {
      try {
        await sb.storage.from(bucket).uploadBinary(
              path,
              bytes,
              fileOptions: FileOptions(contentType: contentType, upsert: false),
            );
        return sb.storage.from(bucket).getPublicUrl(path);
      } catch (e) {
        firstError ??= e;
        final message = e.toString().toLowerCase();
        if (!message.contains('bucket not found') &&
            !message.contains('404')) {
          rethrow;
        }
      }
    }
    throw firstError ?? StateError('Media upload failed');
  }

  Future<void> _stopAndSendRecording() async {
    _recordTimer?.cancel();
    final path = await _audioRecorder.stop();
    final secs = _voiceDuration.inSeconds;
    setState(() {
      _recordingMedia = false;
      _voiceDuration = Duration.zero;
    });

    if (path != null && secs > 0) {
      try {
        final file = File(path);
        final bytes = await file.readAsBytes();
        
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Audio yuklanmoqda...'), duration: Duration(seconds: 2)));
        
        final sb = Supabase.instance.client;
        final uid = sb.auth.currentUser?.id ?? 'anon';
        final uploadPath = '$uid/${DateTime.now().millisecondsSinceEpoch}.m4a';
        
        final publicUrl = await _uploadChatMedia(
          bytes,
          uploadPath,
          contentType: 'audio/m4a',
        );
        
        await ref.read(messagesProvider(widget.conversationId).notifier)
            .send('\ud83c\udfa4 Ovoz xabar (${secs}s)', mediaType: 'voice', mediaUrl: publicUrl);
            
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Audio xatolik: $e'), backgroundColor: Colors.red.shade600));
      }
    }
  }

  Future<void> _cancelRecording() async {
    _recordTimer?.cancel();
    await _audioRecorder.stop();
    setState(() {
      _recordingMedia = false;
      _voiceDuration = Duration.zero;
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
    final selectedMsgs = state.messages.where((m) => _selectedMessages.contains(m.id)).toList();
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Faqat o\'z xabarlaringizni o\'chirishingiz mumkin')),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${mySelectedMessages.length} ta xabarni o\'chirish?'),
        content: const Text('Bu amalni qaytarib bo\'lmaydi.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Bekor')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("O'chirish", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (ok == true) {
      for (final msg in mySelectedMessages) {
        await ref.read(messagesProvider(widget.conversationId).notifier).delete(msg.id);
      }
      _exitSelectionMode();
    }
  }

  void _showForwardDialog(List<Message> messages) {
    final convos = ref.read(conversationsProvider).valueOrNull ?? [];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final c = AlsamosColors.of(ctx);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
                child: Row(children: [
                  const Icon(LucideIcons.share2, size: 18),
                  const SizedBox(width: 8),
                  Text("${messages.length} ta xabarni yo'naltirish", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  IconButton(icon: const Icon(LucideIcons.x), onPressed: () => Navigator.pop(ctx)),
                ]),
              ),
              Divider(color: c.border, height: 1),
              Expanded(
                child: convos.isEmpty
                    ? Center(child: Text('Suhbatlar yo\'q', style: TextStyle(color: c.mutedForeground)))
                    : ListView.builder(
                        itemCount: convos.length,
                        itemBuilder: (_, i) {
                          final conv = convos[i];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: c.muted,
                              backgroundImage: conv.otherParticipant?.avatarUrl != null
                                  ? NetworkImage(conv.otherParticipant!.avatarUrl!) : null,
                              child: conv.otherParticipant?.avatarUrl == null
                                  ? Text(conv.title.isNotEmpty ? conv.title[0].toUpperCase() : '?')
                                  : null,
                            ),
                            title: Text(conv.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(conv.type, style: TextStyle(fontSize: 12, color: c.mutedForeground)),
                            onTap: () async {
                              for (final msg in messages) {
                                await ref.read(messagesProvider(conv.id).notifier).send(msg.content ?? '');
                              }
                              if (ctx.mounted) Navigator.pop(ctx);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text("\"${conv.title}\" ga yo'naltirildi")));
                              }
                            },
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

  void _closeAutocomplete() {
    setState(() {
      _hashtagQuery = null;
      _mentionQuery = null;
      _tokenStart = -1;
    });
  }

  void _send() {
    HapticFeedback.lightImpact();
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    ref.read(messagesProvider(widget.conversationId).notifier).send(text);
    _controller.clear();
    setState(() => _hasText = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  void _onReply(Message m) {
    ref.read(messagesProvider(widget.conversationId).notifier).setReplyTo(m.id);
    _focusNode.requestFocus();
  }

  void _onEdit(Message m) {
    ref.read(messagesProvider(widget.conversationId).notifier).setEditing(m.id);
    _controller.text = m.content ?? '';
    _focusNode.requestFocus();
  }

  void _onDelete(Message m) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text("Xabarni o'chirish?"),
      content: const Text('Bu amalni qaytarib bo\'lmaydi.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Bekor')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("O'chirish", style: TextStyle(color: Colors.red))),
      ],
    ));
    if (ok == true) ref.read(messagesProvider(widget.conversationId).notifier).delete(m.id);
  }

  void _onReact(Message m, String emoji) {
    ref.read(messagesProvider(widget.conversationId).notifier).react(m.id, emoji);
  }

  // ignore: unused_element
  void _onLongPress(Message m, bool isMine, Offset position) async {
    HapticFeedback.mediumImpact();
    final c = AlsamosColors.of(context);
    final text = m.content ?? '';
    final hasLink = RegExp(r'https?://\S+').hasMatch(text);
    final isMedia = m.mediaUrl != null;
    final isImage = m.mediaType == 'image' || m.mediaType == 'gif';
    final isVideo = m.mediaType == 'video' || m.mediaType == 'video_note';
    final isAudio = m.mediaType == 'audio' || m.mediaType == 'voice';

    MessageReactionsOverlay.show(
      context,
      anchor: Offset(position.dx, position.dy - 54),
      onSelect: (emoji) => _onReact(m, emoji),
      onAddMore: () {},
    );

    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    final rect = overlay == null
        ? RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy)
        : RelativeRect.fromRect(
            Rect.fromLTWH(position.dx, position.dy, 1, 1),
            Offset.zero & overlay.size,
          );
    final result = await showMenu<String>(
      context: context,
      position: rect,
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.94),
      elevation: 14,
      constraints: const BoxConstraints(minWidth: 260, maxWidth: 340),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      items: [
        PopupMenuItem(
          enabled: false,
          child: Row(children: [
            Icon(LucideIcons.checkCheck, size: 22, color: c.foreground),
            const SizedBox(width: 16),
            Expanded(child: Text(isMine ? "Ko'rilganlar" : 'Xabar amallari', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
          ]),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'reply', child: _TelegramMenuRow(icon: LucideIcons.cornerUpLeft, label: 'Javob yozish', c: c)),
        if (text.isNotEmpty)
          PopupMenuItem(value: 'copy', child: _TelegramMenuRow(icon: LucideIcons.copy, label: 'Nusxalash', c: c)),
        if (isAudio)
          PopupMenuItem(value: 'save_notifications', child: _TelegramMenuRow(icon: LucideIcons.music, label: 'Bildirishnomalar uchun saqlash', c: c)),
        if (isImage)
          PopupMenuItem(value: 'save_media', child: _TelegramMenuRow(icon: LucideIcons.download, label: 'Rasmni saqlash', c: c)),
        if (isVideo)
          PopupMenuItem(value: 'save_media', child: _TelegramMenuRow(icon: LucideIcons.download, label: 'Videoni saqlash', c: c)),
        if (!isMedia && text.isNotEmpty)
          PopupMenuItem(value: 'speak', child: _TelegramMenuRow(icon: LucideIcons.messageSquare, label: 'Gapirish', c: c)),
        if (isMine && !isMedia)
          PopupMenuItem(value: 'edit', child: _TelegramMenuRow(icon: LucideIcons.squarePen, label: 'Tahrirlash', c: c)),
        PopupMenuItem(value: 'pin', child: _TelegramMenuRow(icon: LucideIcons.pin, label: 'Qadash', c: c)),
        if (hasLink)
          PopupMenuItem(value: 'copy_link', child: _TelegramMenuRow(icon: LucideIcons.link, label: 'Havolani nusxalash', c: c)),
        PopupMenuItem(value: 'forward', child: _TelegramMenuRow(icon: LucideIcons.forward, label: 'Uzatish', c: c)),
        if (!isMine)
          PopupMenuItem(value: 'report', child: _TelegramMenuRow(icon: LucideIcons.circleAlert, label: 'Shikoyat qilish', c: c)),
        if (isMine) const PopupMenuDivider(),
        if (isMine) const PopupMenuItem(value: 'delete', child: _TelegramMenuRow(icon: LucideIcons.trash2, label: "O'chirish", destructive: true)),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'select', child: _TelegramMenuRow(icon: LucideIcons.circleCheck, label: 'Tanlash', c: c)),
      ],
    );

    if (result == null) return;
    switch (result) {
      case 'reply': _onReply(m); break;
      case 'edit': _onEdit(m); break;
      case 'copy':
        Clipboard.setData(ClipboardData(text: text));
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nusxalandi')));
        break;
      case 'copy_link':
        final link = RegExp(r'https?://\S+').firstMatch(text)?.group(0);
        if (link != null) Clipboard.setData(ClipboardData(text: link));
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Havola nusxalandi')));
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
      case 'save_media':
        if (m.mediaUrl != null) {
          await launchUrl(Uri.parse(m.mediaUrl!), mode: LaunchMode.externalApplication);
        }
        break;
      case 'save_notifications':
        if (m.mediaUrl != null) {
          await Clipboard.setData(ClipboardData(text: m.mediaUrl!));
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Media havolasi nusxalandi')));
        }
        break;
      case 'report':
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tayyorlanmoqda')));
        break;
      case 'forward': _showForwardSheet(m); break;
      case 'select': _enterSelectionMode(m.id); break;
      case 'delete': _onDelete(m); break;
    }
  }
  /// Forward sheet — mirrors web `TelegramForwardDialog.tsx` (shows chat list to forward into).
  void _showForwardSheet(Message m) {
    final convos = ref.read(conversationsProvider).valueOrNull ?? [];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final c = AlsamosColors.of(ctx);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
                child: Row(children: [
                  const Icon(LucideIcons.share2, size: 18),
                  const SizedBox(width: 8),
                  const Text("Yo'naltirish", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  IconButton(icon: const Icon(LucideIcons.x), onPressed: () => Navigator.pop(ctx)),
                ]),
              ),
              Divider(color: c.border, height: 1),
              Expanded(
                child: convos.isEmpty
                    ? Center(child: Text('Suhbatlar yo\'q', style: TextStyle(color: c.mutedForeground)))
                    : ListView.builder(
                        itemCount: convos.length,
                        itemBuilder: (_, i) {
                          final conv = convos[i];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: c.muted,
                              backgroundImage: conv.otherParticipant?.avatarUrl != null
                                  ? NetworkImage(conv.otherParticipant!.avatarUrl!) : null,
                              child: conv.otherParticipant?.avatarUrl == null
                                  ? Text(conv.title.isNotEmpty ? conv.title[0].toUpperCase() : '?')
                                  : null,
                            ),
                            title: Text(conv.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(conv.type, style: TextStyle(fontSize: 12, color: c.mutedForeground)),
                            onTap: () {
                              ref.read(messagesProvider(conv.id).notifier).send(m.content ?? '');
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text("\"${conv.title}\" ga yo'naltirildi")));
                            },
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

      // Create video_calls record
      final callData = await sb.from('video_calls').insert({
        'conversation_id': widget.conversationId,
        'host_id': uid,
        'call_type': type,
        'status': 'active',
        'started_at': null,
      }).select().single().timeout(const Duration(seconds: 12));

      final callId = callData['id'] as String;
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

      await sb.from('call_participants').upsert([
        {
          'call_id': callId,
          'user_id': uid,
          'joined_at': DateTime.now().toUtc().toIso8601String(),
          'is_muted': false,
          'is_video_on': isVideo,
          'is_screen_sharing': false,
          'is_hand_raised': false,
        },
        for (final recipientId in recipientIds)
          {
            'call_id': callId,
            'user_id': recipientId,
            'is_muted': false,
            'is_video_on': isVideo,
            'is_screen_sharing': false,
            'is_hand_raised': false,
          },
      ], onConflict: 'call_id,user_id').timeout(const Duration(seconds: 12));

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

      for (final recipientId in recipientIds) {
        final channel = sb.channel('call-invite:$recipientId');
        channel.subscribe((status, [error]) async {
          if (status != RealtimeSubscribeStatus.subscribed) return;
          await channel.sendBroadcastMessage(event: 'incoming_call', payload: {
            'call_id': callId,
            'conversation_id': widget.conversationId,
            'caller_id': uid,
            'caller_name': callerName,
            'caller_avatar': callerAvatar,
            'call_type': type,
            'created_at': DateTime.now().toUtc().toIso8601String(),
          });
          await sb.removeChannel(channel);
        });
      }

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // dismiss loading
      loadingDismissed = true;

      // Push call page with real UUID as room ID
      final elapsed = await Navigator.of(context, rootNavigator: true).push<Duration>(
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

      // End call record
      await sb.from('video_calls').update({
        'status': 'ended',
        'ended_at': DateTime.now().toIso8601String(),
      }).eq('id', callId).timeout(const Duration(seconds: 12));

      if (elapsed == null) return;
      final mins = elapsed.inMinutes;
      final secs = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
      final durStr = '$mins:$secs';
      ref.read(messagesProvider(widget.conversationId).notifier).send(
        '📞 ${isVideo ? "Video" : "Audio"} qo\'ng\'iroq tugadi\nDavomiyligi: $durStr',
        mediaType: 'call_history',
      );
    } catch (e) {
      if (mounted) {
        if (!loadingDismissed) {
          Navigator.of(context, rootNavigator: true).pop(); // dismiss loading if not pushed
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Call error: $e')));
      }
    }
  }

  /// v30: image_picker bilan rasm/video tanlaydi, Supabase Storage `chat-media`
  /// bucket'ga yuklaydi, so'ng `messages` jadvalga `media_url`/`media_type` bilan yuboradi.
  Future<void> _pickAndSendMedia(ImageSource source, {required bool isVideo}) async {
    try {
      final picker = ImagePicker();
      final XFile? file = isVideo
          ? await picker.pickVideo(source: source, maxDuration: const Duration(minutes: 3))
          : await picker.pickImage(source: source, imageQuality: 85, maxWidth: 1920);
      if (file == null) return;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Yuklanmoqda...'), duration: Duration(seconds: 2)));
      final sb = Supabase.instance.client;
      final uid = sb.auth.currentUser?.id ?? 'anon';
      final ext = file.name.contains('.') ? file.name.split('.').last : (isVideo ? 'mp4' : 'jpg');
      final path = '$uid/${DateTime.now().millisecondsSinceEpoch}.$ext';
      final bytes = await file.readAsBytes();
      final publicUrl = await _uploadChatMedia(
        bytes,
        path,
        contentType: isVideo ? 'video/$ext' : 'image/$ext',
      );
      await ref.read(messagesProvider(widget.conversationId).notifier).send('', mediaUrl: publicUrl, mediaType: isVideo ? 'video' : 'image');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(isVideo ? 'Video yuborildi' : 'Rasm yuborildi'),
        backgroundColor: Colors.green.shade600,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text("Kamera/Galereya uskunada qo'llab-quvvatlanmaydi yoki ruxsat yo'q (Desktop Linux/Web bo'lishi mumkin)"),
        backgroundColor: Colors.red.shade600,
        duration: const Duration(seconds: 4),
      ));
    }
  }

  Future<void> _pickAndSendFile() async {
    try {
      final result = await FilePicker.pickFiles();
      if (result == null || result.files.isEmpty) return;
      if (!mounted) return;
      
      final file = result.files.first;
      final bytes = file.bytes ?? (file.path != null ? await File(file.path!).readAsBytes() : null);
      if (bytes == null) return;
      
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fayl yuklanmoqda...'), duration: Duration(seconds: 2)));
      final sb = Supabase.instance.client;
      final uid = sb.auth.currentUser?.id ?? 'anon';
      final path = '$uid/${DateTime.now().millisecondsSinceEpoch}_${file.name}';
      
      final publicUrl = await _uploadChatMedia(bytes, path);
      
      await ref.read(messagesProvider(widget.conversationId).notifier).send(file.name, mediaUrl: publicUrl, mediaType: 'file');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Fayl yuborildi'),
        backgroundColor: Colors.green.shade600,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Xatolik: $e'), backgroundColor: Colors.red.shade600));
    }
  }

  Future<void> _sendLocation({bool live = false, String label = 'Current location'}) async {
    try {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Joylashuv aniqlanmoqda...'), duration: Duration(seconds: 2)));
      
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;
      
      final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      
      await ref.read(messagesProvider(widget.conversationId).notifier).send(
        '📍 $label\n${pos.latitude},${pos.longitude}',
        mediaType: live ? 'live_location' : 'location',
      );
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Joylashuv yuborildi'),
        backgroundColor: Colors.green.shade600,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Xatolik: $e'), backgroundColor: Colors.red.shade600));
    }
  }

  Future<void> _sendPickedLocation() async {
    final latCtrl = TextEditingController();
    final lngCtrl = TextEditingController();
    final labelCtrl = TextEditingController(text: 'Tanlangan joy');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Location tanlash'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: labelCtrl, decoration: const InputDecoration(labelText: 'Nomi')),
          const SizedBox(height: 8),
          TextField(controller: latCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: 'Latitude')),
          const SizedBox(height: 8),
          TextField(controller: lngCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: 'Longitude')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Bekor')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yuborish')),
        ],
      ),
    );
    if (ok != true) return;
    final lat = double.tryParse(latCtrl.text.trim().replaceAll(',', '.'));
    final lng = double.tryParse(lngCtrl.text.trim().replaceAll(',', '.'));
    if (lat == null || lng == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Koordinata noto\'g\'ri')),
      );
      return;
    }
    await ref.read(messagesProvider(widget.conversationId).notifier).send(
      '📍 ${labelCtrl.text.trim().isEmpty ? 'Tanlangan joy' : labelCtrl.text.trim()}\n$lat,$lng',
      mediaType: 'location',
    );
  }

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
                subtitle: const Text('Realtime joylashuv xabari sifatida yuborish'),
                onTap: () {
                  Navigator.pop(ctx);
                  _sendLocation(live: true, label: 'Live location');
                },
              ),
              ListTile(
                leading: const Icon(LucideIcons.mapPinned),
                title: const Text('Tanlangan location'),
                subtitle: const Text('Koordinata kiritib yuborish'),
                onTap: () {
                  Navigator.pop(ctx);
                  _sendPickedLocation();
                },
              ),
            ]),
          ),
        );
      },
    );
  }

  // ignore: unused_element
  void _ensureDartIoImport() { File('').path; } // keeps dart:io alive for any future use

  void _showAttachmentMenu() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(context: context, builder: (ctx) {
      final c = AlsamosColors.of(ctx);
      Widget tile(IconData ic, String label, Color color, VoidCallback onTap) => InkWell(
        onTap: () { Navigator.pop(ctx); onTap(); },
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 56, height: 56, decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle), child: Icon(ic, color: color, size: 26)),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(fontSize: 12, color: c.foreground)),
        ]),
      );
      // v37: real dialoglar — ComposerExtras (Joylashuv/Kontakt/So'rovnoma)
      return SafeArea(child: Padding(
        padding: const EdgeInsets.all(20),
        child: GridView.count(
          shrinkWrap: true,
          crossAxisCount: 4,
          mainAxisSpacing: 16,
          children: [
            // v30: media tile'lar image_picker + Supabase Storage'ga ulandi
            tile(LucideIcons.image, 'Galereya', Colors.purple, () => _pickAndSendMedia(ImageSource.gallery, isVideo: false)),
            tile(LucideIcons.camera, 'Kamera', Colors.red, () => _pickAndSendMedia(ImageSource.camera, isVideo: false)),
            tile(LucideIcons.video, 'Video', Colors.pink, () => _pickAndSendMedia(ImageSource.gallery, isVideo: true)),
            tile(LucideIcons.file, 'Fayl', Colors.blue, _pickAndSendFile),
            tile(LucideIcons.mapPin, 'Joylashuv', Colors.green, _showLocationSheet),
            tile(LucideIcons.user, 'Kontakt', Colors.orange, () => ComposerExtras.showContactPicker(context, onShare: (n, p) {
              ref.read(messagesProvider(widget.conversationId).notifier).send('\ud83d\udcde $n\n$p', mediaType: 'contact');
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kontakt yuborildi'), backgroundColor: Colors.green));
            })),
            tile(LucideIcons.barChart3, "So'rovnoma", Colors.teal, () => ComposerExtras.showPollCreator(context, onCreate: (q, opts) {
              final pollText = '\ud83d\udcca $q\n${opts.map((o) => '○ $o').join('\n')}';
              ref.read(messagesProvider(widget.conversationId).notifier).send(pollText, mediaType: 'poll');
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('So\'rovnoma yuborildi'), backgroundColor: Colors.green));
            })),
            // v40: GIF tile
            tile(LucideIcons.image, 'GIF', Colors.pinkAccent, () => GifPicker.show(context, onSelect: (url) {
              ref.read(messagesProvider(widget.conversationId).notifier).send('', mediaUrl: url, mediaType: 'gif');
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('GIF yuborildi'), backgroundColor: Colors.green));
            })),
          ],
        ),
      ));
    });
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

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final theme = Theme.of(context);
    final userId = ref.watch(authProvider).user?.id;
    final chatBackgroundPath = ref.watch(chatBackgroundProvider);
    final state = ref.watch(messagesProvider(widget.conversationId));
    final conv = widget.conversation;
    final isGroup = conv?.type == 'group';
    final isChannel = conv?.type == 'channel';
    final isSelf = conv?.isSelfChat ?? false;
    final otherId = conv?.otherParticipant?.id;
    final online = conv?.type == 'private' && !isSelf && otherId != null && ref.watch(isUserOnlineProvider(otherId));

    String statusText() {
      if (isSelf) return "o'zingizga xabar saqlang";
      if (conv?.type == 'private') return online ? 'onlayn' : 'oflayn';
      if (isGroup) return 'guruh';
      if (isChannel) return 'kanal';
      return '';
    }

    // Group messages by day.
    final msgs = state.messages;
    final replyMsg = state.replyToId != null ? msgs.where((m) => m.id == state.replyToId).firstOrNull : null;
    final editingMsg = state.editingId != null ? msgs.where((m) => m.id == state.editingId).firstOrNull : null;
    final playable = _playableMessages(msgs);
    final activeMedia = _activeMediaMessage == null
        ? null
        : playable.where((m) => m.id == _activeMediaMessage!.id).firstOrNull;

    return Scaffold(
      backgroundColor: c.background,
      body: Stack(children: [
        if (chatBackgroundPath != null)
          Positioned.fill(
            child: Image.file(
              File(chatBackgroundPath),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        if (chatBackgroundPath != null)
          Positioned.fill(
            child: ColoredBox(
              color: c.background.withValues(alpha: 0.78),
            ),
          ),
        Column(children: [
        // === ChatHeader or Selection Toolbar ===
        _isSelectionMode
            ? _SelectionToolbar(
                count: _selectedMessages.length,
                onClose: _exitSelectionMode,
                onForward: _selectedMessages.isEmpty ? null : _forwardSelected,
                onDelete: _selectedMessages.isEmpty ? null : _deleteSelected,
              )
            : Container(
                height: 64,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(color: c.card, border: Border(bottom: BorderSide(color: c.border))),
                child: SafeArea(bottom: false, child: Row(children: [
                  if (!widget.embedded)
                    IconButton(icon: const Icon(LucideIcons.arrowLeft, size: 22), onPressed: () => Navigator.of(context).maybePop())
                  else
                    const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        if (conv?.type == 'private' && conv?.otherParticipant != null) {
                          final usernameOrId = conv!.otherParticipant!.username ?? conv.otherParticipant!.id;
                          context.push('/user/$usernameOrId');
                        } else if (conv != null && (conv.type == 'group' || conv.type == 'channel')) {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (ctx) => _GroupProfileSheet(conv: conv),
                          );
                        }
                      },
                      child: Row(
                        children: [
                          _headerAvatar(conv, isGroup, isChannel, isSelf, online, c, theme),
                          const SizedBox(width: 10),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                            Row(children: [
                              Flexible(child: Text(
                                isSelf ? 'Saqlangan xabarlar' : (conv?.title ?? 'Suhbat'),
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                              )),
                              if (conv?.isVerified == true) ...[const SizedBox(width: 4), const VerifiedBadge(size: 14)],
                            ]),
                            Text(state.isTyping ? 'yozmoqda...' : statusText(), style: TextStyle(fontSize: 12, color: state.isTyping ? theme.colorScheme.primary : c.mutedForeground)),
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 8,
                    onSelected: (val) => _handleChatMenuAction(val, c),
                    itemBuilder: (ctx) => [
                      PopupMenuItem(value: 'search', child: Row(children: [Icon(LucideIcons.search, size: 18, color: c.foreground), const SizedBox(width: 12), const Text('Izlash')])),
                      PopupMenuItem(value: 'pin', child: Row(children: [Icon(conv?.isPinned == true ? LucideIcons.pinOff : LucideIcons.pin, size: 18, color: c.foreground), const SizedBox(width: 12), Text(conv?.isPinned == true ? "Pin'ni olib tashlash" : "Pin qilish")])),
                      PopupMenuItem(value: 'mute', child: Row(children: [Icon(conv?.isMuted == true ? LucideIcons.bell : LucideIcons.bellOff, size: 18, color: c.foreground), const SizedBox(width: 12), Text(conv?.isMuted == true ? "Ovozni yoqish" : "Ovozni o'chirish")])),
                      PopupMenuItem(value: 'read', child: Row(children: [Icon(LucideIcons.checkCheck, size: 18, color: c.foreground), const SizedBox(width: 12), const Text("O'qilgan deb belgilash")])),
                      PopupMenuItem(value: 'unread', child: Row(children: [Icon(LucideIcons.mailOpen, size: 18, color: c.foreground), const SizedBox(width: 12), const Text("O'qilmagan deb belgilash")])),
                      PopupMenuItem(value: 'scheduled', child: Row(children: [Icon(LucideIcons.clock, size: 18, color: c.foreground), const SizedBox(width: 12), const Text('Rejalashtirilgan xabarlar')])),
                      PopupMenuItem(value: 'archive', child: Row(children: [Icon(LucideIcons.archive, size: 18, color: c.foreground), const SizedBox(width: 12), const Text('Arxivga')])),
                      const PopupMenuDivider(),
                      PopupMenuItem(value: 'delete', child: Row(children: [const Icon(LucideIcons.trash2, size: 18, color: Colors.red), const SizedBox(width: 12), const Text("Suhbatni o'chirish", style: TextStyle(color: Colors.red))])),
                    ],
                  ),
                ])),
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
                onScrollTo: (messageId) {
                  _scrollToMessage(messageId, msgs);
                },
              ),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            );
          },
        ),
        if (activeMedia != null)
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: MiniAudioPlayerBar(
              key: ValueKey(activeMedia.id),
              trackUrl: activeMedia.mediaUrl!,
              trackTitle: _mediaTitle(activeMedia),
              artist: activeMedia.sender?.title,
              isVideo: activeMedia.mediaType == 'video' ||
                  activeMedia.mediaType == 'video_note',
              onClose: () => setState(() => _activeMediaMessage = null),
              onPrevious: playable.length > 1 ? () => _playAdjacent(msgs, -1) : null,
              onNext: playable.length > 1 ? () => _playAdjacent(msgs, 1) : null,
            ),
          ),
        // === Messages list with scroll-to-bottom button ===
        Expanded(
          child: Stack(
            children: [
              // Messages list
              state.isLoading
                  ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      CircularProgressIndicator(color: theme.colorScheme.primary),
                      const SizedBox(height: 16),
                      Text('Xabarlar yuklanmoqda...', style: TextStyle(color: c.mutedForeground, fontSize: 14)),
                    ]))
                  : msgs.isEmpty
                      ? _EmptyState(c: c)
                      : ListView.builder(
                          controller: _scrollController,
                          reverse: true,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          itemCount: msgs.length,
                          itemBuilder: (_, i) {
                            final idx = msgs.length - 1 - i;
                            final m = msgs[idx];
                            final isMine = m.senderId == userId;
                            // ignore: unused_local_variable
                            final next = idx + 1 < msgs.length ? msgs[idx + 1] : null;
                            final prev = idx - 1 >= 0 ? msgs[idx - 1] : null;
                            // Date divider when day changes.
                            final showDayDivider = prev == null || _isDifferentDay(prev.createdAt, m.createdAt);
                            return Column(crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
                              if (showDayDivider) _DayDivider(label: _dayLabel(m.createdAt), c: c),
                                GestureDetector(
                                  onTap: _isSelectionMode ? () => _toggleMessageSelection(m.id) : null,
                                  onSecondaryTapDown: (d) => _isSelectionMode ? null : _onLongPress(m, isMine, d.globalPosition),
                                  onLongPressStart: (d) => _isSelectionMode ? null : _onLongPress(m, isMine, d.globalPosition),
                                child: Stack(
                                  children: [
                                    GestureDetector(
                                      behavior: HitTestBehavior.translucent,
                                      onTap: _isSelectionMode
                                          ? null
                                          : () => _openMiniPlayer(m),
                                      child: MessageBubble(
                                        message: m,
                                        isMine: isMine,
                                        onCallTap: (type) => _startCall(
                                          type: type == CallType.video ? 'video' : 'audio',
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
                                            color: _selectedMessages.contains(m.id)
                                                ? theme.colorScheme.primary
                                                : c.card,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: _selectedMessages.contains(m.id)
                                                  ? theme.colorScheme.primary
                                                  : c.border,
                                              width: 2,
                                            ),
                                          ),
                                          child: _selectedMessages.contains(m.id)
                                              ? Icon(
                                                  LucideIcons.check,
                                                  size: 16,
                                                  color: theme.colorScheme.onPrimary,
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
              // === Scroll-to-bottom FAB (web: h-11 w-11 bg-card border + unread badge) ===
              // Web: `absolute bottom-4 right-4 z-20 h-11 w-11 rounded-full bg-card border border-border shadow-lg ... transition-all active:scale-95`
              if (_showScrollToBottom)
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: _ScrollToBottomFab(
                    unreadCount: widget.conversation?.unreadCount ?? 0,
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
        if (replyMsg != null) _ReplyPreview(message: replyMsg, onCancel: () => ref.read(messagesProvider(widget.conversationId).notifier).setReplyTo(null), c: c, theme: theme),
        if (editingMsg != null) _EditingPreview(message: editingMsg, onCancel: () { ref.read(messagesProvider(widget.conversationId).notifier).setEditing(null); _controller.clear(); }, c: c, theme: theme),
        // === Voice/Video recording UI ===
        if (_recordingMedia) _mediaRecorderBar(c, theme),
        // === Composer ===
        if (!_recordingMedia) _composer(c, theme),
      ]),
      ]),
    );
  }

  bool _isDifferentDay(DateTime a, DateTime b) => a.year != b.year || a.month != b.month || a.day != b.day;

  void _scrollToMessage(String messageId, List<Message> messages) {
    if (!_scrollController.hasClients || messages.isEmpty) return;
    final idx = messages.indexWhere((m) => m.id == messageId);
    if (idx < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Xabar hali cacheda topilmadi')),
      );
      return;
    }
    final reverseIdx = messages.length - 1 - idx;
    _scrollController.animateTo(
      (reverseIdx * 76.0).clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _headerAvatar(Conversation? conv, bool isGroup, bool isChannel, bool isSelf, bool online, AlsamosColors c, ThemeData theme) {
    Widget avatar;
    if (isSelf || isGroup || isChannel) {
      avatar = Container(
        width: 40, height: 40,
        decoration: BoxDecoration(color: theme.colorScheme.primary, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Icon(isSelf ? LucideIcons.bookmark : isGroup ? LucideIcons.users : LucideIcons.megaphone, size: 20, color: theme.colorScheme.onPrimary),
      );
    } else {
      avatar = UserAvatar(avatarUrl: conv?.displayAvatar, fallback: conv?.initial ?? 'C', size: 40);
    }
    return SizedBox(width: 40, height: 40, child: Stack(children: [
      avatar,
      if (online)
        Positioned(right: 0, bottom: 0, child: Container(
          width: 12, height: 12,
          decoration: BoxDecoration(color: const Color(0xFF22C55E), shape: BoxShape.circle, border: Border.all(color: c.card, width: 2)),
        )),
    ]));
  }

  void _handleChatMenuAction(String action, AlsamosColors c) async {
    final convId = widget.conversationId;
    final notif = ref.read(conversationsProvider.notifier);
    
    switch (action) {
      case 'search':
        final st = ref.read(messagesProvider(convId));
        final items = st.messages
            .where((m) => !m.isDeleted && (m.content?.isNotEmpty ?? false))
            .map((m) => InConversationMessage(
                  id: m.id,
                  content: m.content ?? '',
                  createdAt: m.createdAt,
                ))
            .toList();
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          builder: (sctx) => MessageSearchInConversation(
            messages: items,
            onHighlight: (id) {
              Navigator.of(sctx).pop();
              final idx = st.messages.indexWhere((m) => m.id == id);
              if (idx >= 0 && _scrollController.hasClients) {
                final reverseIdx = st.messages.length - 1 - idx;
                _scrollController.animateTo(
                  (reverseIdx * 72.0).clamp(0.0, _scrollController.position.maxScrollExtent),
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                );
              }
            },
            onClose: () => Navigator.of(sctx).maybePop(),
          ),
        );
        break;
      case 'pin': await notif.togglePin(convId); break;
      case 'mute': await notif.toggleMute(convId); break;
      case 'read': await notif.markAsRead(convId); break;
      case 'unread': await notif.markAsUnread(convId); break;
      case 'scheduled': ScheduledMessagesSheet.show(context, convId); break;
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
            content: const Text("Bu suhbat sizning xabarlar ro'yxatidan olib tashlanadi."),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Bekor')),
              TextButton(
                onPressed: () => Navigator.pop(dctx, true),
                child: const Text("O'chirish", style: TextStyle(color: Colors.red)),
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

  // Voice/Video recording bar (UI scaffold; full record requires record package).
  Widget _mediaRecorderBar(AlsamosColors c, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: c.card, border: Border(top: BorderSide(color: c.border))),
      child: SafeArea(top: false, child: Row(children: [
        IconButton(
          icon: const Icon(LucideIcons.trash2, color: Colors.red),
          onPressed: _cancelRecording,
        ),
        const SizedBox(width: 8),
        AnimatedBuilder(animation: _recPulse!, builder: (_, __) => Container(
          width: 12 + 4 * _recPulse!.value,
          height: 12 + 4 * _recPulse!.value,
          decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.7 + 0.3 * _recPulse!.value), shape: BoxShape.circle),
        )),
        const SizedBox(width: 12),
        Expanded(child: Text(
          '${_voiceDuration.inMinutes.toString().padLeft(2, '0')}:${(_voiceDuration.inSeconds % 60).toString().padLeft(2, '0')}',
          style: TextStyle(color: c.foreground, fontSize: 15, fontWeight: FontWeight.w500, fontFeatures: const [FontFeature.tabularFigures()]),
        )),
        Text(_isMediaVideoMode ? 'Video...' : 'Ovoz...', style: TextStyle(color: c.mutedForeground)),
        const SizedBox(width: 12),
        Container(
          decoration: BoxDecoration(color: theme.colorScheme.primary, shape: BoxShape.circle),
          child: IconButton(
            icon: const Icon(LucideIcons.send, color: Colors.white),
            onPressed: _stopAndSendRecording,
          ),
        ),
      ])),
    );
  }

  Widget _composer(AlsamosColors c, ThemeData theme) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(color: c.card, border: Border(top: BorderSide(color: c.border))),
      child: SafeArea(top: false, child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        IconButton(icon: Icon(LucideIcons.plus, color: c.mutedForeground), onPressed: _showAttachmentMenu),
        Expanded(child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 120),
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Xabar yozing...',
              filled: true,
              fillColor: c.muted,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
              suffixIcon: IconButton(
                icon: Icon(LucideIcons.smile, color: c.mutedForeground, size: 20),
                onPressed: () async {
                  final emoji = await EmojiPickerSheet.show(context);
                  if (emoji != null && mounted) {
                    final sel = _controller.selection;
                    final base = _controller.text;
                    final pos = sel.isValid ? sel.start : base.length;
                    final newText = base.substring(0, pos) + emoji + base.substring(pos);
                    _controller.text = newText;
                    _controller.selection = TextSelection.collapsed(offset: pos + emoji.length);
                  }
                },
              ),
            ),
          ),
        )),
        const SizedBox(width: 6),
        // v33: send vs mic switcher (autocomplete overlay positioning anchor)
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          child: _hasText
              ? Container(
                  key: const ValueKey('send'),
                  decoration: BoxDecoration(color: theme.colorScheme.primary, shape: BoxShape.circle),
                  child: IconButton(icon: const Icon(LucideIcons.send, color: Colors.white, size: 20), onPressed: _send),
                )
              : GestureDetector(
                  key: ValueKey(_isMediaVideoMode ? 'video' : 'mic'),
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() => _isMediaVideoMode = !_isMediaVideoMode);
                  },
                  onLongPressStart: (_) {
                    HapticFeedback.mediumImpact();
                    if (!_isMediaVideoMode) {
                      _startRecording();
                    } else {
                      _pickAndSendMedia(ImageSource.camera, isVideo: true);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: c.muted, shape: BoxShape.circle),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                      child: Icon(_isMediaVideoMode ? LucideIcons.camera : LucideIcons.mic, key: ValueKey(_isMediaVideoMode), color: c.mutedForeground, size: 20),
                    ),
                  ),
                ),
        ),
      ])),
        ),
        // v33: autocomplete overlays — composer ustida ko'rinadi (web ekvivalent).
        // `HashtagAutocomplete`/`MentionAutocomplete` o'zlari `Positioned` qaytaradi,
        // shuning uchun ular bevosita Stack farzandlari.
        if (_hashtagQuery != null)
          HashtagAutocomplete(
            query: _hashtagQuery!,
            left: 56,
            right: 56,
            top: -240,
            onSelect: (tag) => _applyAutocomplete(tag, '#'),
            onClose: _closeAutocomplete,
          ),
        if (_mentionQuery != null)
          MentionAutocomplete(
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
          decoration: BoxDecoration(color: c.muted, borderRadius: BorderRadius.circular(10)),
          child: Text(label, style: TextStyle(fontSize: 11, color: c.mutedForeground, fontWeight: FontWeight.w500)),
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
  const _ReplyPreview({required this.message, required this.onCancel, required this.c, required this.theme});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: c.card, border: Border(top: BorderSide(color: c.border))),
      child: Row(children: [
        Container(width: 3, height: 36, color: theme.colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(message.sender?.displayName ?? 'Javob berilmoqda', style: TextStyle(color: theme.colorScheme.primary, fontSize: 12, fontWeight: FontWeight.w600)),
          Text(message.content ?? '[media]', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.mutedForeground, fontSize: 13)),
        ])),
        IconButton(icon: Icon(LucideIcons.x, size: 18, color: c.mutedForeground), onPressed: onCancel),
      ]),
    );
  }
}

class _EditingPreview extends StatelessWidget {
  final Message message;
  final VoidCallback onCancel;
  final AlsamosColors c;
  final ThemeData theme;
  const _EditingPreview({required this.message, required this.onCancel, required this.c, required this.theme});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: c.card, border: Border(top: BorderSide(color: c.border))),
      child: Row(children: [
        Icon(LucideIcons.pencil, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Tahrirlash', style: TextStyle(color: theme.colorScheme.primary, fontSize: 12, fontWeight: FontWeight.w600)),
          Text(message.content ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.mutedForeground, fontSize: 13)),
        ])),
        IconButton(icon: Icon(LucideIcons.x, size: 18, color: c.mutedForeground), onPressed: onCancel),
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
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(
        width: 96, height: 96,
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
        child: Icon(LucideIcons.messageCircle, size: 40, color: theme.colorScheme.primary),
      ),
      const SizedBox(height: 24),
      Text('Hali xabarlar yo\'q', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: c.foreground)),
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
  final VoidCallback onClose;
  final VoidCallback? onForward;
  final VoidCallback? onDelete;
  const _SelectionToolbar({
    required this.count,
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
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: c.card.withValues(alpha: 0.9), // web bg-card/90
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            child: SafeArea(
              bottom: false,
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
      ),
    );
  }
}

class _TelegramMenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final AlsamosColors? c;
  final bool destructive;
  const _TelegramMenuRow({
    required this.icon,
    required this.label,
    this.c,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = c ?? AlsamosColors.of(context);
    final color = destructive ? const Color(0xFFEF4444) : colors.foreground;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(children: [
        Icon(icon, size: 25, color: color),
        const SizedBox(width: 22),
        Expanded(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 20,
              height: 1.15,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ]),
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
            decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(2)),
          ),
          CircleAvatar(
            radius: 50,
            backgroundImage: (conv.avatarUrl != null && conv.avatarUrl!.isNotEmpty)
                ? NetworkImage(conv.avatarUrl!)
                : null,
            backgroundColor: theme.colorScheme.primary,
            child: (conv.avatarUrl == null || conv.avatarUrl!.isEmpty)
                ? Text(conv.title.isNotEmpty ? conv.title[0].toUpperCase() : '?', 
                    style: const TextStyle(fontSize: 40, color: Colors.white, fontWeight: FontWeight.bold))
                : null,
          ),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Flexible(child: Text(conv.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'QR code',
              onPressed: () => UsernameQrDialog.show(
                context,
                title: conv.title,
                subtitle: isChannel ? 'Kanal' : 'Guruh',
                data: 'https://alsamos.app/${isChannel ? 'channel' : 'group'}/${conv.id}',
                avatarUrl: conv.avatarUrl,
              ),
              icon: Icon(LucideIcons.qrCode, size: 18, color: c.mutedForeground),
            ),
          ]),
          const SizedBox(height: 4),
          Text(isChannel ? 'Kanal' : 'Guruh', style: TextStyle(fontSize: 14, color: c.mutedForeground)),
          const SizedBox(height: 24),
          Divider(color: c.border, height: 1),
          if (conv.description != null && conv.description!.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tavsif', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: theme.colorScheme.primary)),
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
            title: Text(isChannel ? 'Kanaldan chiqish' : 'Guruhdan chiqish', style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
