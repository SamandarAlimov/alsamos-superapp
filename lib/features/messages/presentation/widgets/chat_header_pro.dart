import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../../../shared/widgets/verified_badge.dart';

// Telegram-style chat header — matches web messages/ChatHeader.tsx pixel-for-pixel.
class ChatHeaderPro extends StatefulWidget {
  final String name;
  final String? avatarUrl;
  final String chatType; // 'private' | 'group' | 'channel'
  final bool isVerified;
  final bool isSelfChat;
  final bool isOnline;
  final String? lastSeenText;
  final List<String> typingUsers;
  final bool isMuted;
  final bool isAdmin;
  final int scheduledCount;

  final VoidCallback? onBack;
  final VoidCallback? onAudioCall;
  final VoidCallback? onVideoCall;
  final VoidCallback? onSearch;
  final VoidCallback? onViewInfo;
  final VoidCallback? onMute;
  final VoidCallback? onLeave;
  final VoidCallback? onDelete;
  final VoidCallback? onManageMembers;
  final VoidCallback? onViewScheduled;

  const ChatHeaderPro({
    super.key,
    required this.name,
    this.avatarUrl,
    this.chatType = 'private',
    this.isVerified = false,
    this.isSelfChat = false,
    this.isOnline = false,
    this.lastSeenText,
    this.typingUsers = const [],
    this.isMuted = false,
    this.isAdmin = false,
    this.scheduledCount = 0,
    this.onBack,
    this.onAudioCall,
    this.onVideoCall,
    this.onSearch,
    this.onViewInfo,
    this.onMute,
    this.onLeave,
    this.onDelete,
    this.onManageMembers,
    this.onViewScheduled,
  });

  @override
  State<ChatHeaderPro> createState() => _ChatHeaderProState();
}

class _ChatHeaderProState extends State<ChatHeaderPro>
    with SingleTickerProviderStateMixin {
  late final AnimationController _typingPulse;

  @override
  void initState() {
    super.initState();
    // Web: typing... has animate-pulse (opacity 1 -> 0.5 -> 1, ~2s)
    _typingPulse = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _typingPulse.dispose();
    super.dispose();
  }

  Widget _status(BuildContext context) {
    final colors = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    if (widget.typingUsers.isNotEmpty) {
      return AnimatedBuilder(
        animation: _typingPulse,
        builder: (_, __) => Opacity(
          opacity: 0.5 + (_typingPulse.value * 0.5),
          child: Text('typing...',
              style: TextStyle(
                  fontSize: 12,
                  color: primary,
                  fontWeight: FontWeight.w500)),
        ),
      );
    }
    if (widget.isSelfChat) {
      // Web: text-amber-500
      return const Text('save messages to yourself',
          style: TextStyle(fontSize: 12, color: Color(0xFFF59E0B)));
    }
    if (widget.chatType == 'private') {
      if (widget.isOnline) {
        // Web: text-green-500 font-medium
        return const Text('online',
            style: TextStyle(
                fontSize: 12,
                color: Color(0xFF22C55E),
                fontWeight: FontWeight.w500));
      }
      return Text(widget.lastSeenText ?? 'last seen recently',
          style: TextStyle(fontSize: 12, color: colors.mutedForeground));
    }
    if (widget.chatType == 'channel') {
      return Text('channel',
          style: TextStyle(fontSize: 12, color: colors.mutedForeground));
    }
    return Text('group',
        style: TextStyle(fontSize: 12, color: colors.mutedForeground));
  }

  Color _avatarBg(BuildContext context) {
    if (widget.isSelfChat) return const Color(0xFFF59E0B); // amber-500
    if (widget.chatType == 'group') return const Color(0xFF3B82F6); // blue-500
    if (widget.chatType == 'channel') return const Color(0xFF8B5CF6); // violet-500
    return Theme.of(context).colorScheme.primary;
  }

  Gradient? _avatarGradient() {
    // Web: self-chat uses bg-gradient-to-br from-amber-500 to-orange-500
    if (widget.isSelfChat) {
      return const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFF59E0B), Color(0xFFF97316)],
      );
    }
    return null;
  }

  IconData? _fallbackIcon() {
    if (widget.isSelfChat) return LucideIcons.bookmark;
    if (widget.chatType == 'group') return LucideIcons.users;
    if (widget.chatType == 'channel') return LucideIcons.megaphone;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AlsamosColors.of(context);
    final icon = _fallbackIcon();
    final gradient = _avatarGradient();

    // Web: h-16 px-4 flex items-center justify-between border-b border-border bg-card/95 backdrop-blur
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
              color: colors.card.withValues(alpha: 0.95),
              border: Border(bottom: BorderSide(color: colors.border))),
          child: Row(children: [
        if (widget.onBack != null)
          IconButton(
              icon: const Icon(LucideIcons.arrowLeft, size: 20),
              onPressed: () {
                HapticFeedback.selectionClick();
                widget.onBack!();
              }),
        Expanded(
          child: InkWell(
            onTap: widget.onViewInfo,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Avatar: web h-10 w-10 (40px)
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: gradient,
                        color: gradient == null && icon != null
                            ? _avatarBg(context)
                            : null,
                      ),
                      child: icon != null
                          ? Icon(icon, color: Colors.white, size: 20)
                          : UserAvatar(
                              avatarUrl: widget.avatarUrl,
                              fallback: widget.name.isNotEmpty
                                  ? widget.name[0].toUpperCase()
                                  : '?',
                              size: 40,
                              backgroundColor: _avatarBg(context)),
                    ),
                    // Online indicator: web h-3 w-3 bg-green-500 border-2 border-card
                    if (widget.isOnline && !widget.isSelfChat)
                      Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                  color: const Color(0xFF22C55E),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: colors.card, width: 2)))),
                    // Self-chat indicator: web -bottom-0.5 -right-0.5 h-4 w-4 bg-card border-2 border-amber-500 + Bookmark filled
                    if (widget.isSelfChat)
                      Positioned(
                          bottom: -2,
                          right: -2,
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: colors.card,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: const Color(0xFFF59E0B), width: 2),
                            ),
                            child: const Icon(LucideIcons.bookmark,
                                size: 8, color: Color(0xFFF59E0B)),
                          )),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(children: [
                          Flexible(
                              child: Text(widget.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  // Web: text-sm font-semibold (14px w600)
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600))),
                          if (widget.chatType == 'private' && widget.isVerified)
                            const Padding(
                                padding: EdgeInsets.only(left: 4),
                                child: VerifiedBadge(size: 14)),
                          if (widget.isMuted)
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Icon(LucideIcons.bellOff,
                                  size: 12, color: colors.mutedForeground),
                            ),
                        ]),
                        const SizedBox(height: 2),
                        _status(context),
                      ]),
                ),
              ]),
            ),
          ),
        ),
        if (!widget.isSelfChat) ...[
          IconButton(
              icon: Icon(LucideIcons.phone,
                  size: 20, color: colors.mutedForeground),
              onPressed: widget.onAudioCall,
              visualDensity: VisualDensity.compact),
          IconButton(
              icon: Icon(LucideIcons.video,
                  size: 20, color: colors.mutedForeground),
              onPressed: widget.onVideoCall,
              visualDensity: VisualDensity.compact),
        ],
        if (widget.onSearch != null)
          IconButton(
              icon: Icon(LucideIcons.search,
                  size: 20, color: colors.mutedForeground),
              onPressed: widget.onSearch,
              visualDensity: VisualDensity.compact),
        PopupMenuButton<String>(
          icon: Icon(LucideIcons.moreVertical,
              size: 20, color: colors.mutedForeground),
          itemBuilder: (_) => [
            if (widget.onViewInfo != null)
              const PopupMenuItem(
                  value: 'info',
                  child: Row(children: [
                    Icon(LucideIcons.info, size: 14),
                    SizedBox(width: 8),
                    Text('View info')
                  ])),
            if (widget.onMute != null)
              PopupMenuItem(
                  value: 'mute',
                  child: Row(children: [
                    Icon(widget.isMuted ? LucideIcons.bell : LucideIcons.bellOff,
                        size: 14),
                    const SizedBox(width: 8),
                    Text(widget.isMuted ? 'Unmute' : 'Mute')
                  ])),
            if (widget.onViewScheduled != null && widget.scheduledCount > 0)
              PopupMenuItem(
                  value: 'scheduled',
                  child: Row(children: [
                    const Icon(LucideIcons.clock, size: 14),
                    const SizedBox(width: 8),
                    Text('Scheduled (${widget.scheduledCount})')
                  ])),
            if (widget.isAdmin && widget.onManageMembers != null)
              const PopupMenuItem(
                  value: 'members',
                  child: Row(children: [
                    Icon(LucideIcons.users2, size: 14),
                    SizedBox(width: 8),
                    Text('Manage members')
                  ])),
            if (widget.chatType != 'private' && widget.onLeave != null)
              const PopupMenuItem(
                  value: 'leave',
                  child: Row(children: [
                    Icon(LucideIcons.logOut,
                        size: 14, color: Color(0xFFEF4444)),
                    SizedBox(width: 8),
                    Text('Leave',
                        style: TextStyle(color: Color(0xFFEF4444)))
                  ])),
            if (widget.onDelete != null)
              const PopupMenuItem(
                  value: 'delete',
                  child: Row(children: [
                    Icon(LucideIcons.trash2,
                        size: 14, color: Color(0xFFEF4444)),
                    SizedBox(width: 8),
                    Text('Delete',
                        style: TextStyle(color: Color(0xFFEF4444)))
                  ])),
          ],
          onSelected: (v) {
            switch (v) {
              case 'info':
                widget.onViewInfo?.call();
                break;
              case 'mute':
                widget.onMute?.call();
                break;
              case 'scheduled':
                widget.onViewScheduled?.call();
                break;
              case 'members':
                widget.onManageMembers?.call();
                break;
              case 'leave':
                widget.onLeave?.call();
                break;
              case 'delete':
                widget.onDelete?.call();
                break;
            }
          },
        ),
      ]),
        ),
      ),
    );
  }
}
