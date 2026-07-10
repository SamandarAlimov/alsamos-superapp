import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../../../shared/widgets/message_reactions_bar.dart';
import '../../../../shared/widgets/voice_message_player.dart';
import '../../data/models/message_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'call_history_message.dart';
import 'location_message.dart';
import '../../../../shared/widgets/video_message_player.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/gestures.dart';

final _timeFmt = DateFormat('HH:mm');

class MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMine;
  final bool isGroup;
  final bool showSender;
  final bool isPinned;
  final VoidCallback? onReply;
  final ValueChanged<CallType>? onCallTap;
  const MessageBubble({super.key, required this.message, required this.isMine,
      this.isGroup = false, this.showSender = false, this.isPinned = false, this.onReply, this.onCallTap});

  bool get _isRead => message.status == 'read';
  bool get _isDelivered => message.status == 'delivered' || _isRead;

  ({double lat, double lng, String? label})? _locationData(String text) {
    if (message.mediaType != 'location' && message.mediaType != 'live_location') {
      return null;
    }
    final match = RegExp(r'(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)').firstMatch(text);
    if (match == null) return null;
    final lat = double.tryParse(match.group(1)!);
    final lng = double.tryParse(match.group(2)!);
    if (lat == null || lng == null) return null;
    final label = text
        .replaceAll(RegExp(r'https?://\S+'), '')
        .replaceAll('📍', '')
        .trim();
    return (lat: lat, lng: lng, label: label.isEmpty ? null : label);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = AlsamosColors.of(context);
    if (message.isDeleted) return _DeletedBubble(isMine: isMine, c: c);
    final bg = isMine ? theme.colorScheme.primary : c.card;
    final fg = isMine ? theme.colorScheme.onPrimary : c.foreground;
    final text = message.content ?? '';
    final hasMedia = message.mediaUrl != null;
    final locationData = _locationData(text);
    
    // Check for call history
    final isCallHistory = message.mediaType == 'call_history' || text.startsWith('📞');
    CallHistoryData? callData;
    if (isCallHistory) {
      callData = CallHistoryData.fromJson(text);
      if (callData == null) {
        final isVideo = text.toLowerCase().contains('video');
        final durMatch = RegExp(r'(\d+):(\d+)(?::(\d+))?').firstMatch(text);
        int? dur;
        if (durMatch != null) {
          if (durMatch.group(3) != null) {
            dur = int.parse(durMatch.group(1)!) * 3600 + int.parse(durMatch.group(2)!) * 60 + int.parse(durMatch.group(3)!);
          } else {
            dur = int.parse(durMatch.group(1)!) * 60 + int.parse(durMatch.group(2)!);
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
            // ignore: todo
            // TODO(v35+): reaction repo'ga `messages_reactions` insert (hozir UI only)
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Reaksiya: $emoji'),
                duration: const Duration(milliseconds: 800),
              ),
            );
          },
          onAddMore: () => _contextMenu(context, c, text),
        );
      },
      onLongPress: () { /* handled in onLongPressStart */ },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
        child: Row(
          mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isMine && isGroup) ...[
              UserAvatar(avatarUrl: message.sender?.avatarUrl, fallback: message.sender?.initial ?? 'U', size: 28),
              const SizedBox(width: 6),
            ],
            // KEY: ConstrainedBox so bubbles don't stretch full width
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72,
              ),
              child: Column(
                  crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                    // Web: rounded-2xl px-4 py-2.5 (16px radius, 16h/10v padding)
                    padding: hasMedia
                        ? const EdgeInsets.all(4)
                        : const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    constraints: const BoxConstraints(maxWidth: 460),
                    decoration: BoxDecoration(
                      color: message.status == 'failed'
                          ? const Color(0x33EF4444) // web bg-destructive/20
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
                        if (message.content?.startsWith('[forwarded]') ?? false) ...[
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                          color: isMine ? fg : theme.colorScheme.primary,
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
                          Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.only(left: 8),
                            decoration: BoxDecoration(
                              border: Border(
                                left: BorderSide(
                                  color: isMine
                                      ? Colors.white
                                      : theme.colorScheme.primary,
                                  width: 3,
                                ),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Replying to user',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: isMine
                                        ? Colors.white
                                        : theme.colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Message content preview...',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: fg.withValues(alpha: 0.8),
                                  ),
                                ),
                              ],
                            ),
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
                    if (hasMedia)
                      (message.mediaType == 'audio' || message.mediaType == 'voice')
                          ? VoiceMessagePlayer(
                              url: message.mediaUrl!,
                              isMine: isMine,
                              senderName: message.sender?.title,
                            )
                          : (message.mediaType == 'video' || message.mediaType == 'video_note')
                                ? VideoMessagePlayer(
                                    url: message.mediaUrl!,
                                    isMine: isMine,
                                    isCircular: message.mediaType == 'video_note',
                                  )
                                : (message.mediaType == 'file' || message.mediaType == 'document')
                                    ? _buildFileAttachment(context, isMine, message.mediaUrl!, fg, c)
                                    : ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: CachedNetworkImage(
                                          imageUrl: message.mediaUrl!,
                                          width: 200,
                                          height: 200,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                        if (text.isNotEmpty && locationData == null)
                          Padding(
                            padding: hasMedia
                                ? const EdgeInsets.only(top: 6)
                                : EdgeInsets.zero,
                            child: Stack(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: Text.rich(
                                    TextSpan(
                                      children: [
                                        ..._buildTextSpans(text, fg),
                                        WidgetSpan(child: SizedBox(width: message.isEdited ? 70 : 50)),
                                      ],
                                    ),
                                  ),
                                ),
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (message.isEdited) ...[
                                        Text('(edited)', style: TextStyle(fontSize: 10, color: isMine ? fg.withValues(alpha: 0.7) : c.mutedForeground)),
                                        const SizedBox(width: 4),
                                      ],
                                      Text(
                                        _timeFmt.format(message.createdAt.toLocal()),
                                        style: TextStyle(fontSize: 10, color: isMine ? fg.withValues(alpha: 0.7) : c.mutedForeground),
                                      ),
                                      if (isMine) ...[
                                        const SizedBox(width: 4),
                                        _StatusIcon(status: message.status, isRead: _isRead, isDelivered: _isDelivered, fg: fg),
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
                                _timeFmt.format(message.createdAt.toLocal()),
                                style: TextStyle(fontSize: 10, color: isMine ? fg.withValues(alpha: 0.7) : c.mutedForeground),
                              ),
                              if (isMine) ...[
                                const SizedBox(width: 4),
                                _StatusIcon(status: message.status, isRead: _isRead, isDelivered: _isDelivered, fg: fg),
                              ],
                            ],
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
                          border: Border.all(color: c.background, width: 2),
                        ),
                        child: Icon(LucideIcons.pin,
                            size: 10, color: theme.colorScheme.onPrimary),
                      ),
                    ),
                ],
              ),
              // Reactions chips below bubble — web parity
              _ReactionsLoader(messageId: message.id, isMine: isMine),
            ],
          ),
        ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileAttachment(BuildContext ctx, bool isMine, String url, Color fg, AlsamosColors c) {
    String fileName = url.split('/').last;
    try {
      fileName = Uri.decodeComponent(fileName);
    } catch (_) {}
    final isZip = fileName.endsWith('.zip') || fileName.endsWith('.rar');
    final isPdf = fileName.endsWith('.pdf');
    final icon = isZip ? LucideIcons.archive : (isPdf ? LucideIcons.fileText : LucideIcons.file);
    
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isMine ? Colors.white.withValues(alpha: 0.2) : c.muted,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: isMine ? Colors.white.withValues(alpha: 0.2) : c.background, shape: BoxShape.circle),
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
                  style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Hujjat',
                  style: TextStyle(color: fg.withValues(alpha: 0.7), fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<TextSpan> _buildTextSpans(String text, Color fg) {
    final urlRegex = RegExp(r'(https?:\/\/[^\s]+)');
    final matches = urlRegex.allMatches(text);
    if (matches.isEmpty) {
      return [TextSpan(text: text, style: TextStyle(color: fg, fontSize: 14, height: 1.45))];
    }

    final spans = <TextSpan>[];
    int start = 0;
    for (final m in matches) {
      if (m.start > start) {
        spans.add(TextSpan(text: text.substring(start, m.start), style: TextStyle(color: fg, fontSize: 14, height: 1.45)));
      }
      final url = m.group(0)!;
      spans.add(TextSpan(
        text: url,
        style: TextStyle(color: isMine ? Colors.white : Colors.blue, fontSize: 14, height: 1.45, decoration: TextDecoration.underline),
        recognizer: TapGestureRecognizer()..onTap = () async {
          final uri = Uri.parse(url);
          if (await canLaunchUrl(uri)) await launchUrl(uri);
        },
      ));
      start = m.end;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start), style: TextStyle(color: fg, fontSize: 14, height: 1.45)));
    }
    return spans;
  }

  void _contextMenu(BuildContext ctx, AlsamosColors c, String text) {
    showModalBottomSheet<void>(
      context: ctx, backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(20)),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(2))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: ['\u2764\ufe0f','\ud83d\ude02','\ud83d\ude2e','\ud83d\udc4d','\ud83d\udc4e','\ud83d\ude4f']
                      .map((e) => GestureDetector(onTap: () => Navigator.pop(ctx),
                          child: Container(width: 42, height: 42, alignment: Alignment.center,
                              decoration: BoxDecoration(color: c.muted, shape: BoxShape.circle),
                              child: Text(e, style: const TextStyle(fontSize: 22))))).toList(),
                ),
              ),
              const Divider(height: 1),
              ListTile(leading: Icon(LucideIcons.cornerDownLeft, color: c.foreground),
                  title: Text('Javob berish', style: TextStyle(color: c.foreground)),
                  onTap: () { Navigator.pop(ctx); onReply?.call(); }),
              ListTile(leading: Icon(LucideIcons.copy, color: c.foreground),
                  title: Text('Nusxalash', style: TextStyle(color: c.foreground)),
                  onTap: () { Navigator.pop(ctx); Clipboard.setData(ClipboardData(text: text)); }),
              if (isMine)
                ListTile(leading: const Icon(LucideIcons.trash2, color: Color(0xFFEF4444)),
                    title: const Text("O'chirish", style: TextStyle(color: Color(0xFFEF4444))),
                    onTap: () => Navigator.pop(ctx)),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
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
    return Icon(LucideIcons.check,
        size: 12, color: fg.withValues(alpha: 0.7));
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
  final bool isMine; final AlsamosColors c;
  const _DeletedBubble({required this.isMine, required this.c});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
    child: Row(
      mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: c.muted, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.border)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(LucideIcons.ban, size: 14, color: c.mutedForeground),
            const SizedBox(width: 6),
            Text("Xabar o'chirildi", style: TextStyle(color: c.mutedForeground, fontSize: 13, fontStyle: FontStyle.italic)),
          ]),
        ),
      ],
    ),
  );
}
