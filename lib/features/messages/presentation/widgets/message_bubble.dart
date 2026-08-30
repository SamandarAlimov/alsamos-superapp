import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/stories/story_avatar_ring.dart';
import '../../../../shared/widgets/message_reactions_bar.dart';
import '../../../../shared/widgets/voice_message_player.dart';
import '../../data/models/message_model.dart';
import '../../data/services/download_manager.dart';
import '../../data/services/media_settings_service.dart';
import '../providers/message_text_size_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'call_history_message.dart';
import 'location_message.dart';
import 'open_graph_preview.dart';
import 'media_gallery_viewer.dart';
import '../pages/document_viewer_page.dart';
import '../../../../shared/widgets/video_message_player.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/gestures.dart';
import '../../data/models/message_interaction_model.dart' as mi;
import '../../data/models/sticker_model.dart';
import 'animated_sticker.dart';
import 'standalone_emoji_message.dart';

final _timeFmt = DateFormat('HH:mm');

class MessageBubble extends ConsumerWidget {
  final Message message;
  final bool isMine;
  final bool isGroup;
  final bool showSender;
  final bool isPinned;
  final VoidCallback? onReply;
  final ValueChanged<CallType>? onCallTap;
  final Message? replyMessage;
  final VoidCallback? onReplyPreviewTap;
  final List<mi.MessageReactionGroup> reactions;
  final ValueChanged<String>? onToggleReaction;
  final ValueChanged<mi.MessageReactionGroup>? onReactionSummaryTap;

  final ValueChanged<String>? onPollVote;
  final VoidCallback? onTranslate;
  final VoidCallback? onTranscribe;
  final VoidCallback? onStopLiveLocation;
  final VoidCallback? onCommentTap;
  final ValueChanged<String>? onHashtagTap;
  final VoidCallback? onMediaPlaybackRequested;

  const MessageBubble(
      {super.key,
      required this.message,
      required this.isMine,
      this.isGroup = false,
      this.showSender = false,
      this.isPinned = false,
      this.onReply,
      this.onCallTap,
      this.replyMessage,
      this.onReplyPreviewTap,
      this.reactions = const [],
      this.onToggleReaction,
      this.onReactionSummaryTap,
      this.onPollVote,
      this.onTranslate,
      this.onTranscribe,
      this.onStopLiveLocation,
      this.onCommentTap,
      this.onHashtagTap,
      this.onMediaPlaybackRequested});

  bool get _isRead => message.status == 'read';
  bool get _isDelivered => message.status == 'delivered' || _isRead;

  ({double lat, double lng, String? label})? _locationData(String text) {
    final data = message.location;
    if (data == null) return null;

    final latRaw = data['latitude'];
    final lngRaw = data['longitude'];
    final lat = latRaw is num ? latRaw.toDouble() : double.tryParse('$latRaw');
    final lng = lngRaw is num ? lngRaw.toDouble() : double.tryParse('$lngRaw');
    if (lat == null || lng == null) return null;

    final address = data['address']?.toString().trim();
    final label = data['label']?.toString().trim();
    final resolvedLabel = address?.isNotEmpty == true
        ? address
        : (label?.isNotEmpty == true ? label : null);
    return (lat: lat, lng: lng, label: resolvedLabel);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final c = AlsamosColors.of(context);
    final messageTextSize = ref.watch(messageTextSizeProvider);
    final text = message.content ?? '';
    if (message.isDeleted) {
      return _DeletedBubble(
        isMine: isMine,
        c: c,
        content: text,
        mediaType: message.mediaType,
      );
    }

    final mediaUrls0 = message.mediaUrls;
    if (text.isNotEmpty &&
        mediaUrls0.isEmpty &&
        message.mediaType == null &&
        message.replyToId == null &&
        message.poll == null &&
        isEmojiOnly(text)) {
      return StandaloneEmojiMessage(
        message: message,
        isMine: isMine,
        reactions: reactions,
        onToggleReaction: onToggleReaction,
        onReactionSummaryTap: onReactionSummaryTap,
      );
    }

    final bg = isMine ? theme.colorScheme.primary : c.card;
    final fg = isMine ? theme.colorScheme.onPrimary : c.foreground;
    final mediaUrls = message.mediaUrls;
    final hasMedia = mediaUrls.isNotEmpty;
    final poll = message.poll;
    final locationData = _locationData(text);
    final linkUrl = locationData == null
        ? RegExp(r'https?:\/\/[^\s]+').firstMatch(text)?.group(0)
        : null;
    final bubbleMaxWidth =
        (MediaQuery.sizeOf(context).width * 0.72).clamp(0.0, 560.0).toDouble();

    // Check for call history
    final isCallHistory =
        message.mediaType == 'call_history' || text.startsWith('📞');
    CallHistoryData? callData;
    if (isCallHistory) {
      callData = CallHistoryData.fromJson(text);
      if (callData == null) {
        final isVideo = text.toLowerCase().contains('video');
        final durMatch = RegExp(r'(\d+):(\d+)(?::(\d+))?').firstMatch(text);
        int? dur;
        if (durMatch != null) {
          if (durMatch.group(3) != null) {
            dur = int.parse(durMatch.group(1)!) * 3600 +
                int.parse(durMatch.group(2)!) * 60 +
                int.parse(durMatch.group(3)!);
          } else {
            dur = int.parse(durMatch.group(1)!) * 60 +
                int.parse(durMatch.group(2)!);
          }
        }
        callData = CallHistoryData(
          type: isVideo ? CallType.video : CallType.audio,
          status: CallStatus.ended,
          durationSeconds: dur,
          timestamp: message.createdAt.toLocal(),
        );
      }
    }

    if (callData != null) {
      return CallHistoryMessage(
        data: callData,
        isMine: isMine,
        onTap: onCallTap == null ? null : () => onCallTap!(callData!.type),
      );
    }
    return GestureDetector(
      // v34: uzun bosish — oldin context menu, endi suzuvchi 6-emoji reaksiya bar
      // (Telegram/Instagram uslubi, web `MessageReactions.tsx` UX 1:1)
      onLongPressStart: (details) {
        HapticFeedback.mediumImpact();
        MessageReactionsOverlay.show(
          context,
          anchor: details.globalPosition,
          onSelect: (emoji) {
            onToggleReaction?.call(emoji);
          },
          onAddMore: () => _contextMenu(context, c, text),
        );
      },
      onLongPress: () {/* handled in onLongPressStart */},
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
        child: Row(
          mainAxisAlignment:
              isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isMine && isGroup) ...[
              StoryAvatarRing(
                  userId: message.senderId,
                  avatarUrl: message.sender?.avatarUrl,
                  fallback: message.sender?.initial ?? 'U',
                  size: 28),
              const SizedBox(width: 6),
            ],
            Flexible(
              fit: FlexFit.loose,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: bubbleMaxWidth),
                child: Column(
                  crossAxisAlignment: isMine
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          // Web: rounded-2xl px-4 py-2.5 (16px radius, 16h/10v padding)
                          padding: hasMedia
                              ? const EdgeInsets.all(4)
                              : const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                          constraints: const BoxConstraints(maxWidth: 460),
                          decoration: BoxDecoration(
                            color: message.status == 'failed'
                                ? const Color(
                                    0x33EF4444) // web bg-destructive/20
                                : bg,
                            // Web: rounded-2xl (16px) with rounded-br-md (6px) for mine, rounded-bl-md for theirs
                            // Telegram-style sharp tails
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(16),
                              topRight: const Radius.circular(16),
                              bottomLeft: Radius.circular(isMine ? 16 : 0),
                              bottomRight: Radius.circular(isMine ? 0 : 16),
                            ),
                            border: message.status == 'failed'
                                ? Border.all(color: const Color(0xFFEF4444))
                                : (isMine ? null : Border.all(color: c.border)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Forwarded indicator
                              if (message.content?.startsWith('[forwarded]') ??
                                  false) ...[
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(LucideIcons.forward,
                                          size: 14,
                                          color: fg.withValues(alpha: 0.8)),
                                      const SizedBox(width: 6),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Forwarded message',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: fg.withValues(alpha: 0.8),
                                            ),
                                          ),
                                          if (message.sender?.title != null)
                                            Text(
                                              message.sender!.title,
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: isMine
                                                    ? fg
                                                    : theme.colorScheme.primary,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 2),
                              ],
                              if (showSender && !isMine && isGroup)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(message.sender?.title ?? 'User',
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: theme.colorScheme.primary)),
                                ),
                              // Reply-to preview — Telegram style
                              if (message.replyToId != null) ...[
                                _ReplyPreview(
                                  message: replyMessage,
                                  isMine: isMine,
                                  foreground: fg,
                                  onTap: onReplyPreviewTap,
                                ),
                              ],
                              if (locationData != null)
                                LocationMessage(
                                  latitude: locationData.lat,
                                  longitude: locationData.lng,
                                  address: message.mediaType == 'live_location'
                                      ? 'Live location'
                                      : locationData.label,
                                  isMine: isMine,
                                  senderName: message.sender?.title,
                                ),
                              if (message.mediaType == 'live_location')
                                _LiveLocationStatus(
                                  message: message,
                                  isMine: isMine,
                                  foreground: fg,
                                  muted: isMine
                                      ? fg.withValues(alpha: 0.74)
                                      : c.mutedForeground,
                                  onStop: onStopLiveLocation,
                                ),
                              if (poll != null)
                                _PollBubble(
                                  poll: poll,
                                  foreground: fg,
                                  muted: isMine
                                      ? fg.withValues(alpha: 0.74)
                                      : c.mutedForeground,
                                  onVote: onPollVote,
                                ),
                              if (hasMedia && mediaUrls.length > 1)
                                _AlbumGrid(
                                  urls: mediaUrls,
                                  thumbnails:
                                      (message.metadata['thumbnail_urls']
                                                  as List?)
                                              ?.whereType<String>()
                                              .toList() ??
                                          const [],
                                  mediaType: message.mediaType ?? 'image',
                                ),
                              if (hasMedia && mediaUrls.length == 1)
                                message.mediaType == 'sticker'
                                    ? _StickerBubble(
                                        url: mediaUrls.first,
                                        message: message,
                                      )
                                    : (message.mediaType == 'audio' ||
                                            message.mediaType == 'voice')
                                        ? VoiceMessagePlayer(
                                            url: mediaUrls.first,
                                            duration: message.durationMs == null
                                                ? null
                                                : Duration(
                                                    milliseconds:
                                                        message.durationMs!),
                                            waveform: message.waveform,
                                            isMine: isMine,
                                            senderName: message.sender?.title,
                                            onPlaybackRequested:
                                                onMediaPlaybackRequested,
                                          )
                                        : (message.mediaType == 'video' ||
                                                message.mediaType ==
                                                    'video_note')
                                            ? VideoMessagePlayer(
                                                url: mediaUrls.first,
                                                thumbnailUrl:
                                                    message.thumbnailUrl,
                                                isMine: isMine,
                                                isCircular: message.mediaType ==
                                                    'video_note',
                                              )
                                            : (message.mediaType == 'file' ||
                                                    message.mediaType ==
                                                        'document')
                                                ? _buildFileAttachment(
                                                    context,
                                                    isMine,
                                                    mediaUrls.first,
                                                    fg,
                                                    c)
                                                : ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            12),
                                                    child: InkWell(
                                                      onTap: () =>
                                                          MediaGalleryViewer
                                                              .open(
                                                        context,
                                                        items: [
                                                          MediaGalleryItem(
                                                            url:
                                                                mediaUrls.first,
                                                            type: message
                                                                    .mediaType ??
                                                                'image',
                                                            thumbnailUrl: message
                                                                .thumbnailUrl,
                                                          )
                                                        ],
                                                      ),
                                                      child: _AutoDownloadImage(
                                                        url: message
                                                                .thumbnailUrl ??
                                                            mediaUrls.first,
                                                        mediaType:
                                                            message.mediaType ??
                                                                'image',
                                                        width: 200,
                                                        height: 200,
                                                        fit: BoxFit.cover,
                                                      ),
                                                    ),
                                                  ),
                              if (message.uploadProgress != null &&
                                  message.status == 'sending')
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(99),
                                    child: LinearProgressIndicator(
                                      minHeight: 3,
                                      value: message.uploadProgress!
                                          .clamp(0.04, 0.98),
                                      backgroundColor:
                                          fg.withValues(alpha: 0.16),
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        isMine ? fg : theme.colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                ),
                              if (text.isNotEmpty &&
                                  locationData == null &&
                                  poll == null)
                                Padding(
                                  padding: hasMedia
                                      ? const EdgeInsets.only(top: 6)
                                      : EdgeInsets.zero,
                                  child: Stack(
                                    children: [
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 2),
                                        child: Text.rich(
                                          TextSpan(
                                            children: [
                                              ..._buildTextSpans(text, fg),
                                              WidgetSpan(
                                                  child: SizedBox(
                                                      width: message.isEdited
                                                          ? 70
                                                          : 50)),
                                            ],
                                          ),
                                          style: TextStyle(
                                              fontSize: messageTextSize),
                                          softWrap: true,
                                          overflow: TextOverflow.visible,
                                        ),
                                      ),
                                      Positioned(
                                        right: 0,
                                        bottom: 0,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (message.isEdited) ...[
                                              Text('(edited)',
                                                  style: TextStyle(
                                                      fontSize: 10,
                                                      color: isMine
                                                          ? fg.withValues(
                                                              alpha: 0.7)
                                                          : c.mutedForeground)),
                                              const SizedBox(width: 4),
                                            ],
                                            Text(
                                              _timeFmt.format(
                                                  message.createdAt.toLocal()),
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  color: isMine
                                                      ? fg.withValues(
                                                          alpha: 0.7)
                                                      : c.mutedForeground),
                                            ),
                                            if (isMine) ...[
                                              const SizedBox(width: 4),
                                              _StatusIcon(
                                                  status: message.status,
                                                  isRead: _isRead,
                                                  isDelivered: _isDelivered,
                                                  fg: fg),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else if (!hasMedia)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Text(
                                      _timeFmt
                                          .format(message.createdAt.toLocal()),
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: isMine
                                              ? fg.withValues(alpha: 0.7)
                                              : c.mutedForeground),
                                    ),
                                    if (isMine) ...[
                                      const SizedBox(width: 4),
                                      _StatusIcon(
                                          status: message.status,
                                          isRead: _isRead,
                                          isDelivered: _isDelivered,
                                          fg: fg),
                                    ],
                                  ],
                                ),
                              if (linkUrl != null && linkUrl.isNotEmpty)
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                      maxWidth: (bubbleMaxWidth - 32)
                                          .clamp(220, 320)),
                                  child: OpenGraphPreview(url: linkUrl),
                                ),
                              if (message.translatedText != null)
                                _InlineInsight(
                                  icon: LucideIcons.languages,
                                  label: 'Tarjima',
                                  text: message.translatedText!,
                                  foreground: fg,
                                  muted: isMine
                                      ? fg.withValues(alpha: 0.72)
                                      : c.mutedForeground,
                                ),
                              if (message.transcriptText != null)
                                _InlineInsight(
                                  icon: LucideIcons.fileAudio,
                                  label: 'Transkripsiya',
                                  text: message.transcriptText!,
                                  foreground: fg,
                                  muted: isMine
                                      ? fg.withValues(alpha: 0.72)
                                      : c.mutedForeground,
                                ),
                            ],
                          ),
                        ),
                        // Pinned indicator — web: absolute -top-1 (right if mine, left+8 if not), Pin icon
                        if (isPinned)
                          Positioned(
                            top: -4,
                            right: isMine ? 0 : null,
                            left: isMine ? null : 8,
                            child: Container(
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary,
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: c.background, width: 2),
                              ),
                              child: Icon(LucideIcons.pin,
                                  size: 10, color: theme.colorScheme.onPrimary),
                            ),
                          ),
                      ],
                    ),
                    // Reactions chips below bubble — web parity
                    MessageReactionChips(
                      reactions: [
                        for (final reaction in reactions)
                          ReactionGroup(
                            emoji: reaction.emoji,
                            count: reaction.count,
                            hasReacted: reaction.hasReacted,
                          ),
                      ],
                      isMine: isMine,
                      onToggle: (emoji) => onToggleReaction?.call(emoji),
                      onInspect: onReactionSummaryTap == null
                          ? null
                          : (emoji) {
                              final group = reactions
                                  .where((reaction) => reaction.emoji == emoji)
                                  .firstOrNull;
                              if (group != null) onReactionSummaryTap!(group);
                            },
                    ),
                    if (message.commentCount > 0 || onCommentTap != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Align(
                          alignment: isMine
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: InkWell(
                            onTap: onCommentTap,
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: c.card,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: c.border),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(LucideIcons.messageCircle,
                                      size: 14,
                                      color: theme.colorScheme.primary),
                                  const SizedBox(width: 6),
                                  Text(
                                    message.commentCount > 0
                                        ? '${message.commentCount} izoh'
                                        : 'Izoh qoldirish',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileAttachment(
      BuildContext ctx, bool isMine, String url, Color fg, AlsamosColors c) {
    String fileName = url.split('/').last;
    try {
      fileName = Uri.decodeComponent(fileName);
    } catch (_) {}
    final isZip = fileName.endsWith('.zip') || fileName.endsWith('.rar');
    final isPdf = fileName.endsWith('.pdf');
    final icon = isZip
        ? LucideIcons.archive
        : (isPdf ? LucideIcons.fileText : LucideIcons.file);

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        Navigator.push(
          ctx,
          MaterialPageRoute(
            builder: (_) => DocumentViewerPage(
              url: url,
              fileName: fileName,
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isMine ? Colors.white.withValues(alpha: 0.2) : c.muted,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color:
                    isMine ? Colors.white.withValues(alpha: 0.2) : c.background,
                shape: BoxShape.circle),
            child: Icon(icon, color: fg, size: 24),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 160,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  fileName,
                  style: TextStyle(
                      color: fg, fontWeight: FontWeight.w600, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Hujjat',
                  style:
                      TextStyle(color: fg.withValues(alpha: 0.7), fontSize: 12),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  List<TextSpan> _buildTextSpans(String text, Color fg) {
    final tokenRegex = RegExp(r'(https?:\/\/[^\s]+)|(^|[\s])#([a-zA-Z0-9_]+)');
    final matches = tokenRegex.allMatches(text);
    if (matches.isEmpty) {
      return [
        TextSpan(
            text: text, style: TextStyle(color: fg, fontSize: 14, height: 1.45))
      ];
    }

    final spans = <TextSpan>[];
    int start = 0;
    for (final m in matches) {
      if (m.start > start) {
        spans.add(TextSpan(
            text: text.substring(start, m.start),
            style: TextStyle(color: fg, fontSize: 14, height: 1.45)));
      }
      final url = m.group(1);
      final tag = m.group(3);
      if (url != null) {
        spans.add(TextSpan(
          text: url,
          style: TextStyle(
              color: isMine ? Colors.white : Colors.blue,
              fontSize: 14,
              height: 1.45,
              decoration: TextDecoration.underline),
          recognizer: TapGestureRecognizer()
            ..onTap = () async {
              final uri = Uri.parse(url);
              if (await canLaunchUrl(uri)) await launchUrl(uri);
            },
        ));
      } else if (tag != null) {
        final raw = m.group(0)!;
        final prefix = raw.startsWith('#') ? '' : raw.substring(0, 1);
        if (prefix.isNotEmpty) {
          spans.add(TextSpan(
              text: prefix,
              style: TextStyle(color: fg, fontSize: 14, height: 1.45)));
        }
        spans.add(TextSpan(
          text: '#$tag',
          style: TextStyle(
              color: isMine ? Colors.white : Colors.blue,
              fontSize: 14,
              height: 1.45,
              fontWeight: FontWeight.w600),
          recognizer: TapGestureRecognizer()
            ..onTap = () => onHashtagTap?.call(tag),
        ));
      }
      start = m.end;
    }
    if (start < text.length) {
      spans.add(TextSpan(
          text: text.substring(start),
          style: TextStyle(color: fg, fontSize: 14, height: 1.45)));
    }
    return spans;
  }

  void _contextMenu(BuildContext ctx, AlsamosColors c, String text) {
    showModalBottomSheet<void>(
      context: ctx,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
            color: c.card, borderRadius: BorderRadius.circular(20)),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: c.border, borderRadius: BorderRadius.circular(2))),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    '\u2764\ufe0f',
                    '\ud83d\ude02',
                    '\ud83d\ude2e',
                    '\ud83d\udc4d',
                    '\ud83d\udc4e',
                    '\ud83d\ude4f'
                  ]
                      .map((e) => GestureDetector(
                          onTap: () => Navigator.pop(ctx),
                          child: Container(
                              width: 42,
                              height: 42,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                  color: c.muted, shape: BoxShape.circle),
                              child: Text(e,
                                  style: const TextStyle(fontSize: 22)))))
                      .toList(),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                  leading:
                      Icon(LucideIcons.cornerDownLeft, color: c.foreground),
                  title: Text('Javob berish',
                      style: TextStyle(color: c.foreground)),
                  onTap: () {
                    Navigator.pop(ctx);
                    onReply?.call();
                  }),
              ListTile(
                  leading: Icon(LucideIcons.copy, color: c.foreground),
                  title:
                      Text('Nusxalash', style: TextStyle(color: c.foreground)),
                  onTap: () {
                    Navigator.pop(ctx);
                    Clipboard.setData(ClipboardData(text: text));
                  }),
              if (isMine)
                ListTile(
                    leading: const Icon(LucideIcons.trash2,
                        color: Color(0xFFEF4444)),
                    title: const Text("O'chirish",
                        style: TextStyle(color: Color(0xFFEF4444))),
                    onTap: () => Navigator.pop(ctx)),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReplyPreview extends StatelessWidget {
  final Message? message;
  final bool isMine;
  final Color foreground;
  final VoidCallback? onTap;

  const _ReplyPreview({
    required this.message,
    required this.isMine,
    required this.foreground,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = AlsamosColors.of(context);
    final author = message?.sender?.title ?? 'Xabar';
    final snippet = _snippet(message);
    final accent = isMine ? Colors.white : theme.colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: (isMine ? Colors.white : c.muted).withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(8),
          border: Border(left: BorderSide(color: accent, width: 3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message?.mediaUrl != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 34,
                  height: 34,
                  child: message!.mediaType == 'image' ||
                          message!.mediaType == 'gif'
                      ? CachedNetworkImage(
                          imageUrl: message!.mediaUrl!,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Icon(
                            LucideIcons.image,
                            size: 16,
                            color: foreground.withValues(alpha: 0.75),
                          ),
                        )
                      : Icon(
                          _mediaIcon(message!.mediaType),
                          size: 18,
                          color: foreground.withValues(alpha: 0.75),
                        ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.1,
                      fontWeight: FontWeight.w700,
                      color: accent,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    snippet,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.15,
                      color: foreground.withValues(alpha: 0.82),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _snippet(Message? message) {
    if (message == null) return 'Asl xabar topilmadi';
    if (message.isDeleted) return 'Bu xabar o\'chirilgan';
    final content = message.content?.trim();
    if (content != null && content.isNotEmpty) return content;
    switch (message.mediaType) {
      case 'image':
      case 'gif':
        return 'Rasm';
      case 'voice':
      case 'audio':
        return 'Audio xabar';
      case 'video':
      case 'video_note':
        return 'Video xabar';
      case 'location':
      case 'live_location':
        return 'Location';
      case 'file':
      case 'document':
        return 'Fayl';
    }
    return 'Xabar';
  }

  static IconData _mediaIcon(String? mediaType) {
    switch (mediaType) {
      case 'voice':
      case 'audio':
        return LucideIcons.mic;
      case 'video':
      case 'video_note':
        return LucideIcons.video;
      case 'location':
      case 'live_location':
        return LucideIcons.mapPin;
      case 'file':
      case 'document':
        return LucideIcons.file;
      default:
        return LucideIcons.paperclip;
    }
  }
}

class _AlbumGrid extends StatelessWidget {
  final List<String> urls;
  final List<String> thumbnails;
  final String mediaType;
  const _AlbumGrid({
    required this.urls,
    required this.thumbnails,
    required this.mediaType,
  });

  @override
  Widget build(BuildContext context) {
    final visible = urls.take(4).toList();
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 260,
        height: urls.length == 2 ? 130 : 220,
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: visible.length == 1 ? 1 : 2,
            mainAxisSpacing: 2,
            crossAxisSpacing: 2,
          ),
          itemCount: visible.length,
          itemBuilder: (_, index) {
            final url =
                index < thumbnails.length && thumbnails[index].isNotEmpty
                    ? thumbnails[index]
                    : visible[index];
            return InkWell(
              onTap: () => MediaGalleryViewer.open(
                context,
                items: [
                  for (var i = 0; i < urls.length; i++)
                    MediaGalleryItem(
                      url: urls[i],
                      type: mediaType == 'album' ? 'image' : mediaType,
                      thumbnailUrl:
                          i < thumbnails.length ? thumbnails[i] : null,
                    )
                ],
                initialIndex: index,
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _AutoDownloadImage(
                    url: url,
                    mediaType: mediaType == 'album' ? 'image' : mediaType,
                    fit: BoxFit.cover,
                  ),
                  if (index == 3 && urls.length > 4)
                    Container(
                      color: Colors.black.withValues(alpha: 0.42),
                      alignment: Alignment.center,
                      child: Text(
                        '+${urls.length - 3}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
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

class _AutoDownloadImage extends ConsumerStatefulWidget {
  const _AutoDownloadImage({
    required this.url,
    required this.mediaType,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  final String url;
  final String mediaType;
  final double? width;
  final double? height;
  final BoxFit fit;

  @override
  ConsumerState<_AutoDownloadImage> createState() => _AutoDownloadImageState();
}

class _AutoDownloadImageState extends ConsumerState<_AutoDownloadImage> {
  bool? _allowed;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final allowed = await ref
          .read(mediaSettingsServiceProvider)
          .shouldAutoDownload(widget.mediaType);
      if (!mounted) return;
      setState(() => _allowed = allowed);
      if (allowed) {
        await ref.read(downloadManagerProvider.notifier).download(
              widget.url,
              fileName: widget.url.split('/').last,
              openAfterDownload: false,
            );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_allowed == false) {
      final c = AlsamosColors.of(context);
      return Container(
        width: widget.width,
        height: widget.height,
        color: c.muted,
        alignment: Alignment.center,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(LucideIcons.download, color: c.mutedForeground),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () {
              setState(() => _allowed = true);
              ref.read(downloadManagerProvider.notifier).download(
                    widget.url,
                    fileName: widget.url.split('/').last,
                    openAfterDownload: false,
                  );
            },
            child: const Text('Yuklash'),
          ),
        ]),
      );
    }
    return CachedNetworkImage(
      imageUrl: widget.url,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
    );
  }
}

class _StickerBubble extends StatelessWidget {
  final String url;
  final Message? message;

  const _StickerBubble({required this.url, this.message});

  @override
  Widget build(BuildContext context) {
    // Try to get sticker data from message metadata
    final metadata = message?.metadata;
    Sticker? sticker;

    if (metadata != null && metadata['sticker'] != null) {
      try {
        final stickerData = metadata['sticker'] as Map<String, dynamic>;
        sticker = Sticker.fromMap(stickerData);
      } catch (e) {
        debugPrint('[_StickerBubble] Failed to parse sticker data: $e');
      }
    }

    // If we have full sticker data, use animated sticker widget
    if (sticker != null) {
      return RepaintBoundary(
        child: MessageSticker(
          sticker: sticker,
          size: 150,
        ),
      );
    }

    // Fallback: detect if it's a lottie/animated sticker from URL
    final isLottie = url.endsWith('.json') || url.contains('lottie');
    if (isLottie) {
      final fallbackSticker = Sticker(
        id: 'temp',
        packId: '',
        emoji: '🙂',
        lottieUrl: url,
        type: StickerType.animated,
      );
      return RepaintBoundary(
        child: MessageSticker(
          sticker: fallbackSticker,
          size: 150,
        ),
      );
    }

    // Static image sticker fallback
    return RepaintBoundary(
      child: CachedNetworkImage(
        imageUrl: url,
        width: 150,
        height: 150,
        fit: BoxFit.contain,
        errorWidget: (_, __, ___) => const Icon(LucideIcons.sticker, size: 72),
      ),
    );
  }
}

class _LiveLocationStatus extends StatelessWidget {
  const _LiveLocationStatus({
    required this.message,
    required this.isMine,
    required this.foreground,
    required this.muted,
    this.onStop,
  });

  final Message message;
  final bool isMine;
  final Color foreground;
  final Color muted;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    final stopped = message.metadata['live_location_stopped_at'] != null;
    final expiresRaw = message.metadata['live_location_expires_at']?.toString();
    final expiresAt = expiresRaw == null ? null : DateTime.tryParse(expiresRaw);
    final expired =
        expiresAt != null && expiresAt.toLocal().isBefore(DateTime.now());
    final active = !stopped && !expired;
    final subtitle = stopped
        ? "Live location to'xtatildi"
        : expired
            ? 'Live location muddati tugadi'
            : expiresAt == null
                ? 'Live location faol'
                : '${DateFormat('HH:mm').format(expiresAt.toLocal())} gacha faol';
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(children: [
        Icon(active ? LucideIcons.radioTower : LucideIcons.circleStop,
            size: 14, color: muted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(subtitle, style: TextStyle(color: muted, fontSize: 12)),
        ),
        if (active && isMine && onStop != null)
          TextButton(
            onPressed: onStop,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: Text("To'xtatish", style: TextStyle(color: foreground)),
          ),
      ]),
    );
  }
}

class _PollBubble extends StatelessWidget {
  final Map<String, dynamic> poll;
  final Color foreground;
  final Color muted;
  final ValueChanged<String>? onVote;
  const _PollBubble({
    required this.poll,
    required this.foreground,
    required this.muted,
    this.onVote,
  });

  @override
  Widget build(BuildContext context) {
    final question = poll['question']?.toString() ?? "So'rovnoma";
    final options = (poll['options'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final total = options.fold<int>(
      0,
      (sum, item) => sum + ((item['votes'] as num?)?.toInt() ?? 0),
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 320),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(LucideIcons.barChart3, size: 16, color: foreground),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                question,
                style: TextStyle(
                  color: foreground,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          for (final option in options)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: InkWell(
                onTap: onVote == null
                    ? null
                    : () => onVote!(option['id'].toString()),
                borderRadius: BorderRadius.circular(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text(
                          option['text']?.toString() ?? '',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: foreground, fontSize: 13),
                        ),
                      ),
                      Text(
                        '${total == 0 ? 0 : (((option['votes'] as num?)?.toInt() ?? 0) * 100 / total).round()}%',
                        style: TextStyle(color: muted, fontSize: 12),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        minHeight: 5,
                        value: total == 0
                            ? 0
                            : (((option['votes'] as num?)?.toDouble() ?? 0) /
                                total),
                        backgroundColor: muted.withValues(alpha: 0.18),
                        valueColor: AlwaysStoppedAnimation<Color>(foreground),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Text('$total ovoz', style: TextStyle(color: muted, fontSize: 11)),
        ],
      ),
    );
  }
}

class _InlineInsight extends StatelessWidget {
  final IconData icon;
  final String label;
  final String text;
  final Color foreground;
  final Color muted;
  const _InlineInsight({
    required this.icon,
    required this.label,
    required this.text,
    required this.foreground,
    required this.muted,
  });

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: foreground.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 14, color: muted),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          color: muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(text, style: TextStyle(color: foreground, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      );
}

/// Web parity status icon: sending (Clock animate-pulse), failed (AlertCircle red),
/// read (CheckCheck #0095F6 Instagram blue), delivered (CheckCheck), sent (Check).
class _StatusIcon extends StatelessWidget {
  final String status;
  final bool isRead;
  final bool isDelivered;
  final Color fg;
  const _StatusIcon({
    required this.status,
    required this.isRead,
    required this.isDelivered,
    required this.fg,
  });

  @override
  Widget build(BuildContext context) {
    if (status == 'sending') {
      return _PulsingClock(color: fg.withValues(alpha: 0.7));
    }
    if (status == 'failed') {
      return const Icon(LucideIcons.alertCircle,
          size: 12, color: Color(0xFFEF4444));
    }
    if (isRead) {
      // Web: CheckCheck h-3.5 w-3.5 text-[#0095F6] (Instagram blue)
      return const Icon(LucideIcons.checkCheck,
          size: 14, color: Color(0xFF0095F6));
    }
    if (isDelivered) {
      // Web: CheckCheck h-3.5 w-3.5 (default fg)
      return Icon(LucideIcons.checkCheck,
          size: 14, color: fg.withValues(alpha: 0.7));
    }
    // Sent: single check
    return Icon(LucideIcons.check, size: 12, color: fg.withValues(alpha: 0.7));
  }
}

/// Web `animate-pulse` clock icon for sending state.
class _PulsingClock extends StatefulWidget {
  final Color color;
  const _PulsingClock({required this.color});

  @override
  State<_PulsingClock> createState() => _PulsingClockState();
}

class _PulsingClockState extends State<_PulsingClock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Opacity(
        // Tailwind animate-pulse: opacity 1 -> 0.5 -> 1 (2s ease-in-out)
        opacity: 0.5 + (_ctrl.value * 0.5),
        child: Icon(LucideIcons.clock, size: 12, color: widget.color),
      ),
    );
  }
}

/// Reactions loader — fetches message_reactions for this messageId, groups by emoji,
/// renders [MessageReactionChips] below the bubble (web `EnhancedMessageBubble` fetchReactions).
class _ReactionsLoader extends ConsumerStatefulWidget {
  final String messageId;
  final bool isMine;
  const _ReactionsLoader({required this.messageId, required this.isMine});

  @override
  ConsumerState<_ReactionsLoader> createState() => _ReactionsLoaderState();
}

class _ReactionsLoaderState extends ConsumerState<_ReactionsLoader> {
  final _client = Supabase.instance.client;
  List<ReactionGroup> _groups = const [];
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _fetch();
    _channel = _client
        .channel('reactions-${widget.messageId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'message_reactions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'message_id',
            value: widget.messageId,
          ),
          callback: (_) => _fetch(),
        )
        .subscribe();
  }

  @override
  void dispose() {
    if (_channel != null) _client.removeChannel(_channel!);
    super.dispose();
  }

  Future<void> _fetch() async {
    try {
      final rows = await _client
          .from('message_reactions')
          .select('emoji, user_id')
          .eq('message_id', widget.messageId);
      final me = ref.read(authProvider).user?.id;
      final Map<String, _Acc> agg = {};
      for (final r in rows as List) {
        final emoji = r['emoji'] as String? ?? '';
        final uid = r['user_id'] as String? ?? '';
        if (emoji.isEmpty) continue;
        final a = agg.putIfAbsent(emoji, () => _Acc());
        a.count++;
        if (uid == me) a.mine = true;
      }
      if (!mounted) return;
      setState(() {
        _groups = agg.entries
            .map((e) => ReactionGroup(
                emoji: e.key, count: e.value.count, hasReacted: e.value.mine))
            .toList();
      });
    } catch (_) {
      // silent — row not yet present or table missing
    }
  }

  Future<void> _toggle(String emoji) async {
    final me = ref.read(authProvider).user?.id;
    if (me == null) return;
    try {
      // Remove if exists
      final existing = await _client
          .from('message_reactions')
          .select('id')
          .eq('message_id', widget.messageId)
          .eq('user_id', me)
          .eq('emoji', emoji)
          .maybeSingle();
      if (existing != null) {
        await _client
            .from('message_reactions')
            .delete()
            .eq('id', existing['id'] as String);
      } else {
        await _client.from('message_reactions').insert({
          'message_id': widget.messageId,
          'user_id': me,
          'emoji': emoji,
        });
      }
    } catch (_) {/* ignore */}
  }

  @override
  Widget build(BuildContext context) {
    if (_groups.isEmpty) return const SizedBox.shrink();
    return MessageReactionChips(
      reactions: _groups,
      isMine: widget.isMine,
      onToggle: _toggle,
    );
  }
}

class _Acc {
  int count = 0;
  bool mine = false;
}

class _DeletedBubble extends StatelessWidget {
  final bool isMine;
  final AlsamosColors c;
  final String content;
  final String? mediaType;
  const _DeletedBubble({
    required this.isMine,
    required this.c,
    required this.content,
    required this.mediaType,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
        child: Row(
          mainAxisAlignment:
              isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            Container(
              constraints: BoxConstraints(
                maxWidth: (MediaQuery.sizeOf(context).width * 0.68)
                    .clamp(160.0, 440.0)
                    .toDouble(),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                  color: c.muted,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.border)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(LucideIcons.ban, size: 13, color: c.mutedForeground),
                    const SizedBox(width: 5),
                    Text("o'chirilgan xabar",
                        style: TextStyle(
                            color: c.mutedForeground,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                  ]),
                  if (content.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(content.trim(),
                        softWrap: true,
                        style: TextStyle(
                            color: c.mutedForeground,
                            fontSize: 12,
                            height: 1.25,
                            fontStyle: FontStyle.italic)),
                  ] else if (mediaType != null) ...[
                    const SizedBox(height: 4),
                    Text('Media: $mediaType',
                        style: TextStyle(
                            color: c.mutedForeground,
                            fontSize: 12,
                            fontStyle: FontStyle.italic)),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
}
