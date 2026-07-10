import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/widgets/user_avatar.dart';
import 'message_attachment.dart';
import 'message_content_rich.dart';
import 'message_context_menu.dart';
import 'message_reactions.dart';
import 'voice_message_player.dart';
import 'video_message_player.dart';
import 'audio_file_player.dart';
import 'call_history_message.dart';
import 'location_message.dart';
import 'shared_post_preview.dart';
import 'story_reply_preview.dart';
import 'link_preview.dart';

// Telegram-style message bubble with all features — matches web messages/EnhancedMessageBubble.tsx
class EnhancedMessageBubble extends StatelessWidget {
  final String messageId;
  final String content;
  final bool isMine;
  final String? senderName;
  final String? senderAvatar;
  final bool showAvatar;
  final bool showSenderName;
  final DateTime sentAt;
  final DateTime? readAt;
  final bool isEdited;
  final bool isPinned;
  final String? mediaType; // 'image' | 'video' | 'audio' | 'voice' | 'video_message' | 'document' | 'gif' | 'location' | 'sticker'
  final List<String> mediaUrls;
  final String? mediaFileName;
  final double? locationLat;
  final double? locationLng;
  final String? locationAddress;
  final String? sharedPostId;
  final String? storyReplyId;
  final String? replyToContent;
  final String? replyToSender;
  final bool replyToIsMine;
  final List<ReactionGroup> reactions;
  final void Function(String emoji)? onToggleReaction;
  final ValueChanged<String>? onAddReaction;
  final VoidCallback? onReply;
  final VoidCallback? onForward;
  final VoidCallback? onCopy;
  final VoidCallback? onEdit;
  final VoidCallback? onPin;
  final VoidCallback? onDelete;
  final VoidCallback? onViewInfo;
  final VoidCallback? onSelect;

  const EnhancedMessageBubble({
    super.key,
    required this.messageId,
    required this.content,
    required this.isMine,
    this.senderName,
    this.senderAvatar,
    this.showAvatar = true,
    this.showSenderName = true,
    required this.sentAt,
    this.readAt,
    this.isEdited = false,
    this.isPinned = false,
    this.mediaType,
    this.mediaUrls = const [],
    this.mediaFileName,
    this.locationLat,
    this.locationLng,
    this.locationAddress,
    this.sharedPostId,
    this.storyReplyId,
    this.replyToContent,
    this.replyToSender,
    this.replyToIsMine = false,
    this.reactions = const [],
    this.onToggleReaction,
    this.onAddReaction,
    this.onReply,
    this.onForward,
    this.onCopy,
    this.onEdit,
    this.onPin,
    this.onDelete,
    this.onViewInfo,
    this.onSelect,
  });

  bool get _isCallHistory => content.startsWith('{') && content.contains('"type"') && (content.contains('"audio"') || content.contains('"video"'));

  @override
  Widget build(BuildContext context) {
    final colors = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;

    // Special: call history is always centered, system style
    if (_isCallHistory) {
      try {
        final data = CallHistoryData.fromJson(content);
        if (data != null) return CallHistoryMessage(data: data, isMine: isMine);
      } catch (_) {}
    }

    // Special: location bubble (no padding/background)
    if (mediaType == 'location' && locationLat != null && locationLng != null) {
      return Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: EdgeInsets.fromLTRB(isMine ? 60 : 12, 2, isMine ? 12 : 60, 2),
          child: LocationMessage(latitude: locationLat!, longitude: locationLng!, address: locationAddress, isMine: isMine, senderName: senderName),
        ),
      );
    }

    final bubbleColor = isMine ? primary : colors.muted;
    final fg = isMine ? Colors.white : colors.foreground;
    final maxBubbleWidth = MediaQuery.of(context).size.width * 0.75;

    Widget mediaWidget = const SizedBox.shrink();
    if (mediaUrls.isNotEmpty && mediaType != null) {
      switch (mediaType) {
        case 'voice':
          mediaWidget = VoiceMessagePlayer(url: mediaUrls.first, isMine: isMine);
          break;
        case 'video_message':
          mediaWidget = VideoMessagePlayer(url: mediaUrls.first, isMine: isMine);
          break;
        case 'audio':
          mediaWidget = AudioFilePlayer(url: mediaUrls.first, name: mediaFileName, isMine: isMine, senderName: senderName);
          break;
        case 'image':
        case 'gif':
        case 'video':
        case 'document':
          mediaWidget = ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: MessageAttachment(url: mediaUrls.first, type: MessageAttachment.fromString(mediaType!), name: mediaFileName, isMine: isMine, senderName: senderName),
          );
          break;
        case 'sticker':
          mediaWidget = Image.network(mediaUrls.first, width: 140, height: 140, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const SizedBox(width: 140, height: 140));
          break;
      }
    }

    Widget? sharedWidget;
    if (sharedPostId != null && sharedPostId!.isNotEmpty) sharedWidget = SharedPostPreview(postId: sharedPostId!, isMine: isMine);
    if (storyReplyId != null && storyReplyId!.isNotEmpty) sharedWidget = StoryReplyPreview(storyId: storyReplyId!, isMine: isMine);

    return Padding(
      padding: EdgeInsets.fromLTRB(isMine ? 60 : 8, 2, isMine ? 8 : 60, 2),
      child: Row(
        mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMine && showAvatar)
            Padding(padding: const EdgeInsets.only(right: 6), child: UserAvatar(avatarUrl: senderAvatar, fallback: (senderName?.isNotEmpty ?? false) ? senderName![0].toUpperCase() : '?', size: 30))
          else if (!isMine)
            const SizedBox(width: 36),
          Flexible(
            child: Column(
              crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onLongPress: () => _openContextMenu(context),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                    child: Container(
                      decoration: BoxDecoration(
                        color: bubbleColor,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(16),
                          topRight: const Radius.circular(16),
                          bottomLeft: Radius.circular(isMine ? 16 : 4),
                          bottomRight: Radius.circular(isMine ? 4 : 16),
                        ),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 1, offset: const Offset(0, 1))],
                      ),
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        if (showSenderName && !isMine && (senderName?.isNotEmpty ?? false))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(senderName!, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primary)),
                          ),
                        if (replyToContent != null && replyToContent!.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(
                              color: (isMine ? Colors.white : primary).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border(left: BorderSide(color: isMine ? Colors.white : primary, width: 3)),
                            ),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                              if (replyToSender != null && replyToSender!.isNotEmpty)
                                Text(replyToSender!, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isMine ? Colors.white : primary)),
                              Text(replyToContent!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: fg.withValues(alpha: 0.85))),
                            ]),
                          ),
                        if (mediaUrls.isNotEmpty) Padding(padding: EdgeInsets.only(bottom: content.isNotEmpty ? 6 : 0), child: mediaWidget),
                        if (sharedWidget != null) Padding(padding: EdgeInsets.only(bottom: content.isNotEmpty ? 6 : 0), child: sharedWidget),
                        if (content.isNotEmpty)
                          MessageContentRich(content: content, isMine: isMine, baseStyle: TextStyle(fontSize: 14, height: 1.35, color: fg)),
                        const SizedBox(height: 4),
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          if (isPinned) Padding(padding: const EdgeInsets.only(right: 4), child: Icon(LucideIcons.pin, size: 10, color: fg.withValues(alpha: 0.7))),
                          if (isEdited) Padding(padding: const EdgeInsets.only(right: 4), child: Text('edited', style: TextStyle(fontSize: 10, color: fg.withValues(alpha: 0.7), fontStyle: FontStyle.italic))),
                          Text(DateFormat.Hm().format(sentAt), style: TextStyle(fontSize: 10, color: fg.withValues(alpha: 0.7), fontFeatures: const [FontFeature.tabularFigures()])),
                          if (isMine) Padding(padding: const EdgeInsets.only(left: 3), child: Icon(readAt != null ? Icons.done_all : Icons.done, size: 13, color: readAt != null ? const Color(0xFF93C5FD) : Colors.white.withValues(alpha: 0.7))),
                        ]),
                      ]),
                    ),
                  ),
                ),
                if (reactions.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: MessageReactions(reactions: reactions, isMine: isMine, onToggle: onToggleReaction ?? (s) {}, onAdd: onAddReaction ?? (s) {}),
                  ),
                if (mediaUrls.isEmpty && content.contains(RegExp(r'https?://')))
                  Padding(padding: const EdgeInsets.only(top: 4), child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxBubbleWidth), child: LinkPreview(url: RegExp(r'https?:\/\/[^\s]+').firstMatch(content)?.group(0) ?? ''))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openContextMenu(BuildContext context) {
    HapticFeedback.lightImpact();
    MessageContextMenu.show(
      context,
      isMine: isMine,
      sentAt: sentAt,
      readAt: readAt,
      isPinned: isPinned,
      hasMedia: mediaUrls.isNotEmpty,
      onViewInfo: onViewInfo,
      onReply: onReply,
      onForward: onForward,
      onCopy: onCopy ?? () { Clipboard.setData(ClipboardData(text: content)); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied'))); },
      onEdit: isMine ? onEdit : null,
      onPin: onPin,
      onDelete: onDelete,
      onSelect: onSelect,
    );
  }
}
