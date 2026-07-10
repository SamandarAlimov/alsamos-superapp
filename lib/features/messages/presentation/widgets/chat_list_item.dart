import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/widgets/premium_motion.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../../../shared/widgets/verified_badge.dart';

// Telegram-style conversation row — matches web messages/ChatListItem.tsx (compact + full).
class ChatListItemData {
  final String id;
  final String type; // 'private' | 'group' | 'channel'
  final String? name;
  final String? avatarUrl;
  final bool isVerified;
  final bool isSelfChat;
  final bool isOnline;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final int unreadCount;
  final bool sentByMe;
  final bool isReadByOther;
  const ChatListItemData({
    required this.id,
    required this.type,
    this.name,
    this.avatarUrl,
    this.isVerified = false,
    this.isSelfChat = false,
    this.isOnline = false,
    this.lastMessage,
    this.lastMessageAt,
    this.unreadCount = 0,
    this.sentByMe = false,
    this.isReadByOther = false,
  });
}

class ChatListItem extends StatelessWidget {
  final ChatListItemData conversation;
  final bool isSelected;
  final bool isPinned;
  final bool isMuted;
  final bool isArchived;
  final bool compact;
  final VoidCallback onTap;
  final VoidCallback? onArchive;
  final VoidCallback? onUnarchive;
  final VoidCallback? onPin;
  final VoidCallback? onMute;
  final VoidCallback? onDelete;
  final VoidCallback? onMarkRead;
  final VoidCallback? onMarkUnread;

  const ChatListItem({
    super.key,
    required this.conversation,
    required this.isSelected,
    this.isPinned = false,
    this.isMuted = false,
    this.isArchived = false,
    this.compact = false,
    required this.onTap,
    this.onArchive,
    this.onUnarchive,
    this.onPin,
    this.onMute,
    this.onDelete,
    this.onMarkRead,
    this.onMarkUnread,
  });

  String _getName() {
    if (conversation.isSelfChat) return conversation.name ?? 'You';
    return conversation.name ??
        (conversation.type == 'private' ? 'Unknown' : 'Unnamed');
  }

  String _formatTime(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dDay = DateTime(d.year, d.month, d.day);
    final diff = today.difference(dDay).inDays;
    if (diff == 0) return DateFormat.Hm().format(d);
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return DateFormat.E().format(d);
    return DateFormat('dd.MM.yyyy').format(d);
  }

  ({String text, Widget? icon}) _formatLastMessage(
      BuildContext context, String? message) {
    if (message == null || message.isEmpty) {
      return (text: 'No messages yet', icon: null);
    }
    if (message.startsWith('{') && message.contains('"type"')) {
      try {
        final call = jsonDecode(message) as Map<String, dynamic>;
        final t = call['type']?.toString();
        if (t == 'video' || t == 'audio') {
          final isVideo = t == 'video';
          final status = call['status']?.toString();
          switch (status) {
            case 'missed':
              return (
                text: isVideo
                    ? "O'tkazib yuborilgan video qo'ng'iroq"
                    : "O'tkazib yuborilgan qo'ng'iroq",
                icon: const Icon(LucideIcons.phoneMissed,
                    size: 13, color: Color(0xFFEF4444))
              );
            case 'declined':
              return (
                text: isVideo
                    ? "Rad etilgan video qo'ng'iroq"
                    : "Rad etilgan qo'ng'iroq",
                icon: const Icon(LucideIcons.phoneOff,
                    size: 13, color: Color(0xFFF97316))
              );
            case 'ended':
              final duration =
                  call['duration'] is int ? call['duration'] as int : null;
              var text = isVideo ? "Video qo'ng'iroq" : "Qo'ng'iroq";
              if (duration != null) {
                text +=
                    ' (${duration ~/ 60}:${(duration % 60).toString().padLeft(2, '0')})';
              }
              return (
                text: text,
                icon: Icon(isVideo ? LucideIcons.video : LucideIcons.phone,
                    size: 13, color: const Color(0xFF22C55E))
              );
            default:
              return (
                text: isVideo ? "Video qo'ng'iroq" : "Qo'ng'iroq",
                icon: Icon(isVideo ? LucideIcons.video : LucideIcons.phone,
                    size: 13, color: Theme.of(context).colorScheme.primary)
              );
          }
        }
      } catch (_) {}
    }
    return (text: message, icon: null);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final selectedForeground = Theme.of(context).colorScheme.onPrimary;
    final titleColor = isSelected ? selectedForeground : colors.foreground;
    final metaColor = isSelected
        ? selectedForeground.withValues(alpha: 0.78)
        : colors.mutedForeground;
    final emphasisColor = isSelected ? selectedForeground : primary;
    final isUnread = conversation.unreadCount > 0;
    final iconFallback = conversation.isSelfChat
        ? LucideIcons.bookmark
        : (conversation.type == 'group'
            ? LucideIcons.users
            : (conversation.type == 'channel' ? LucideIcons.megaphone : null));

    if (compact) {
      return PremiumMotion(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(12),
        hoverScale: 1.02,
        pressScale: 0.97,
        hoverLift: 0,
        builder: (context, hovered, pressed) => AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected
                ? primary
                : (hovered ? colors.accent.withValues(alpha: 0.9) : null),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Stack(clipBehavior: Clip.none, children: [
            AnimatedScale(
              duration: const Duration(milliseconds: 170),
              curve: Curves.easeOutBack,
              scale: hovered && !isSelected ? 1.06 : 1,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: isSelected
                            ? selectedForeground
                            : Colors.transparent,
                        width: 2)),
                child: iconFallback != null
                    ? Container(
                        decoration: BoxDecoration(
                            shape: BoxShape.circle, color: _avatarBg(context)),
                        child:
                            Icon(iconFallback, color: Colors.white, size: 18))
                    : UserAvatar(
                        avatarUrl: conversation.avatarUrl,
                        fallback: _getName().isNotEmpty
                            ? _getName()[0].toUpperCase()
                            : '?',
                        size: 44,
                        backgroundColor: primary),
              ),
            ),
            if (conversation.isOnline &&
                conversation.type == 'private' &&
                !conversation.isSelfChat)
              Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                          color: const Color(0xFF22C55E),
                          shape: BoxShape.circle,
                          border: Border.all(color: colors.card, width: 2)))),
            if (isUnread)
              Positioned(
                  top: -4,
                  right: -4,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    constraints: const BoxConstraints(minWidth: 20),
                    decoration: BoxDecoration(
                        color: isSelected ? selectedForeground : primary,
                        borderRadius: BorderRadius.circular(10)),
                    child: Text(
                        conversation.unreadCount > 99
                            ? '99+'
                            : '${conversation.unreadCount}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 9,
                            color: isSelected ? primary : Colors.white,
                            fontWeight: FontWeight.w600)),
                  )),
          ]),
        ),
      );
    }

    final lm = _formatLastMessage(context, conversation.lastMessage);

    return PremiumMotion(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      onLongPress: () => _showContextMenu(context),
      borderRadius: BorderRadius.circular(14),
      hoverScale: 1.006,
      pressScale: 0.985,
      hoverLift: 1,
      builder: (context, hovered, pressed) => AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? primary
              : (hovered ? colors.accent.withValues(alpha: 0.9) : null),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Stack(clipBehavior: Clip.none, children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: iconFallback != null ? _avatarBg(context) : null),
              child: iconFallback != null
                  ? Icon(iconFallback, color: Colors.white, size: 22)
                  : UserAvatar(
                      avatarUrl: conversation.avatarUrl,
                      fallback: _getName().isNotEmpty
                          ? _getName()[0].toUpperCase()
                          : '?',
                      size: 52,
                      backgroundColor: primary),
            ),
            if (conversation.isOnline &&
                conversation.type == 'private' &&
                !conversation.isSelfChat)
              Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                          color: const Color(0xFF22C55E),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: isSelected ? primary : colors.card,
                              width: 2)))),
          ]),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(_getName(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 14.5,
                          fontWeight:
                              isUnread ? FontWeight.w700 : FontWeight.w600,
                          color: titleColor)),
                ),
                if (conversation.isVerified)
                  const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: VerifiedBadge(size: 12)),
                if (isPinned)
                  Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Icon(LucideIcons.pin, size: 12, color: metaColor)),
                if (isMuted)
                  Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Icon(LucideIcons.volumeX,
                          size: 12, color: metaColor)),
                const Spacer(),
                if (conversation.lastMessageAt != null)
                  Text(_formatTime(conversation.lastMessageAt!),
                      style: TextStyle(
                          fontSize: 10.5,
                          color: isUnread ? emphasisColor : metaColor,
                          fontWeight:
                              isUnread ? FontWeight.w600 : FontWeight.w400)),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                if (conversation.sentByMe && conversation.unreadCount == 0)
                  Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(
                          conversation.isReadByOther
                              ? Icons.done_all
                              : Icons.done,
                          size: 14,
                          color: conversation.isReadByOther
                              ? emphasisColor
                              : metaColor)),
                if (lm.icon != null)
                  Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: lm.icon!),
                Expanded(
                    child: Text(lm.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12.5,
                            color: isUnread ? titleColor : metaColor,
                            fontWeight:
                                isUnread ? FontWeight.w500 : FontWeight.w400))),
                if (isUnread)
                  Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    constraints: const BoxConstraints(minWidth: 20),
                    decoration: BoxDecoration(
                        color: isSelected
                            ? selectedForeground
                            : (isMuted ? colors.mutedForeground : primary),
                        borderRadius: BorderRadius.circular(10)),
                    child: Text(
                        conversation.unreadCount > 99
                            ? '99+'
                            : '${conversation.unreadCount}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 10,
                            color: isSelected ? primary : Colors.white,
                            fontWeight: FontWeight.w600)),
                  ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  Color _avatarBg(BuildContext context) {
    if (conversation.isSelfChat) return const Color(0xFFEAB308);
    if (conversation.type == 'group') return const Color(0xFF3B82F6);
    if (conversation.type == 'channel') return const Color(0xFF8B5CF6);
    return Theme.of(context).colorScheme.primary;
  }

  void _showContextMenu(BuildContext context) {
    HapticFeedback.lightImpact();
    final colors = AlsamosColors.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheetCtx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (onPin != null)
          _menuItem(LucideIcons.pin, isPinned ? 'Unpin' : 'Pin', () {
            Navigator.pop(sheetCtx);
            onPin!();
          }),
        if (onMute != null)
          _menuItem(isMuted ? LucideIcons.bell : LucideIcons.bellOff,
              isMuted ? 'Unmute' : 'Mute', () {
            Navigator.pop(sheetCtx);
            onMute!();
          }),
        if (conversation.unreadCount > 0 && onMarkRead != null)
          _menuItem(Icons.done_all, 'Mark as read', () {
            Navigator.pop(sheetCtx);
            onMarkRead!();
          }),
        if (conversation.unreadCount == 0 && onMarkUnread != null)
          _menuItem(LucideIcons.dot, 'Mark as unread', () {
            Navigator.pop(sheetCtx);
            onMarkUnread!();
          }),
        if (isArchived && onUnarchive != null)
          _menuItem(LucideIcons.archiveRestore, 'Unarchive', () {
            Navigator.pop(sheetCtx);
            onUnarchive!();
          }),
        if (!isArchived && onArchive != null)
          _menuItem(LucideIcons.archive, 'Archive', () {
            Navigator.pop(sheetCtx);
            onArchive!();
          }),
        if (onDelete != null)
          _menuItem(LucideIcons.trash2, 'Delete', () {
            Navigator.pop(sheetCtx);
            onDelete!();
          }, color: const Color(0xFFEF4444)),
      ])),
    );
  }

  Widget _menuItem(IconData icon, String label, VoidCallback onTap,
          {Color? color}) =>
      ListTile(
          leading: Icon(icon, size: 18, color: color),
          title: Text(label, style: TextStyle(color: color, fontSize: 14)),
          onTap: onTap);
}
