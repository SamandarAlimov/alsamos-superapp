import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/stories/story_avatar_ring.dart';
import '../providers/live_webrtc_service.dart';
import '../../../../shared/widgets/app_toast.dart';

/// Pixel-perfect Flutter port of web `LiveStreamViewer.tsx`.
///
/// Mirrors:
///   - Top header with avatar + display name + animated LIVE pill + viewers
///   - Loading / ended / waiting placeholder states (with retry button)
///   - Floating reaction emojis (animate up + fade)
///   - Comments overlay above the composer
///   - Bottom composer (text field + send + reaction picker w/ 6 emojis)
///
/// Realtime: live_stream_viewers / live_stream_comments / live_stream_reactions
/// plus Supabase Broadcast signaling for real WebRTC playback.
class LiveStreamViewer extends StatefulWidget {
  const LiveStreamViewer({super.key, required this.streamId});
  final String streamId;

  @override
  State<LiveStreamViewer> createState() => _LiveStreamViewerState();
}

const List<String> _kReactionEmojis = [
  '\u2764\uFE0F', // ❤️
  '\u{1F525}', // 🔥
  '\u{1F60D}', // 😍
  '\u{1F44F}', // 👏
  '\u{1F602}', // 😂
  '\u{1F62E}', // 😮
];

class _Comment {
  const _Comment({
    required this.id,
    required this.username,
    required this.avatarUrl,
    required this.displayName,
    required this.text,
  });
  final String id;
  final String? username;
  final String? displayName;
  final String? avatarUrl;
  final String text;
}

class _Float {
  const _Float({required this.id, required this.emoji, required this.right});
  final String id;
  final String emoji;
  final double right;
}

enum _StreamState { loading, live, ended, error }

class _LiveStreamViewerState extends State<LiveStreamViewer>
    with TickerProviderStateMixin {
  final TextEditingController _ctrl = TextEditingController();
  final ScrollController _scroll = ScrollController();

  _StreamState _state = _StreamState.loading;
  String? _broadcasterName;
  String? _broadcasterUsername;
  String? _broadcasterAvatar;
  String? _title;
  int _viewerCount = 0;
  final List<_Comment> _comments = <_Comment>[];
  bool _showReactions = false;
  final List<_Float> _floats = <_Float>[];

  RealtimeChannel? _viewersChan;
  RealtimeChannel? _commentsChan;
  RealtimeChannel? _reactionsChan;
  RealtimeChannel? _streamChan;
  RealtimeChannel? _moderationChan;
  Timer? _viewerHeartbeat;
  LiveWebRtcService? _liveRtc;
  MediaStream? _remoteStream;
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  String? _streamError;

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    unawaited(_remoteRenderer.initialize());
    _bootstrap();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    _pulse.dispose();
    _liveRtc?.dispose();
    _remoteRenderer.dispose();
    _leave();
    _viewersChan?.unsubscribe();
    _commentsChan?.unsubscribe();
    _reactionsChan?.unsubscribe();
    _streamChan?.unsubscribe();
    _moderationChan?.unsubscribe();
    _viewerHeartbeat?.cancel();
    super.dispose();
  }

  // --------------------------- lifecycle --------------------------

  Future<void> _bootstrap() async {
    await _loadStream();
    await _joinAndLoadComments();
    _subscribe();
    if (_state == _StreamState.live) {
      await _connectWebRtc();
    }
  }

  Future<void> _connectWebRtc() async {
    final uid = Supabase.instance.client.auth.currentUser?.id ??
        'viewer-${DateTime.now().microsecondsSinceEpoch}';
    _liveRtc = LiveWebRtcService(
      streamId: widget.streamId,
      userId: uid,
      isBroadcaster: false,
      onRemoteStream: (stream) {
        if (!mounted) return;
        setState(() {
          _remoteStream = stream;
          _remoteRenderer.srcObject = stream;
          _streamError = null;
        });
      },
      onError: (message) {
        if (mounted) setState(() => _streamError = message);
      },
    );
    try {
      await _liveRtc!.connect();
    } catch (e) {
      if (mounted) setState(() => _streamError = e.toString());
    }
  }

  Future<void> _loadStream() async {
    final supa = Supabase.instance.client;
    try {
      final s = await supa
          .from('live_streams')
          .select(
              'title, status, viewer_count, profiles:user_id(username, display_name, avatar_url)')
          .eq('id', widget.streamId)
          .maybeSingle();
      if (!mounted) return;
      if (s == null) {
        setState(() => _state = _StreamState.error);
        return;
      }
      final status = s['status'] as String?;
      _title = s['title'] as String?;
      _viewerCount = (s['viewer_count'] as int?) ?? 0;
      final p = s['profiles'] as Map<String, dynamic>?;
      _broadcasterUsername = p?['username'] as String?;
      _broadcasterName =
          (p?['display_name'] as String?) ?? _broadcasterUsername;
      _broadcasterAvatar = p?['avatar_url'] as String?;
      setState(() =>
          _state = status == 'ended' ? _StreamState.ended : _StreamState.live);
    } catch (_) {
      if (mounted) setState(() => _state = _StreamState.error);
    }
  }

  Future<void> _joinAndLoadComments() async {
    final supa = Supabase.instance.client;
    final uid = supa.auth.currentUser?.id;
    if (uid != null) {
      try {
        await supa.from('live_stream_viewers').upsert(
          {
            'stream_id': widget.streamId,
            'user_id': uid,
            'last_seen_at': DateTime.now().toUtc().toIso8601String(),
          },
          onConflict: 'stream_id,user_id',
        );
        _viewerHeartbeat?.cancel();
        _viewerHeartbeat = Timer.periodic(const Duration(seconds: 12), (_) {
          unawaited(supa.from('live_stream_viewers').upsert({
            'stream_id': widget.streamId,
            'user_id': uid,
            'last_seen_at': DateTime.now().toUtc().toIso8601String(),
          }, onConflict: 'stream_id,user_id'));
        });
      } catch (_) {}
    }
    try {
      final existing = await supa
          .from('live_stream_comments')
          .select('id, content, username, avatar_url, display_name, created_at')
          .eq('stream_id', widget.streamId)
          .order('created_at', ascending: false)
          .limit(50);
      final rows = (existing as List).reversed.toList();
      if (!mounted) return;
      setState(() {
        _comments
          ..clear()
          ..addAll(rows.map((r) => _Comment(
                id: r['id'].toString(),
                username: r['username'] as String?,
                displayName: r['display_name'] as String?,
                avatarUrl: r['avatar_url'] as String?,
                text: (r['content'] as String?) ?? '',
              )));
      });
      _scrollEnd();
    } catch (_) {}
  }

  Future<void> _leave() async {
    try {
      final supa = Supabase.instance.client;
      final uid = supa.auth.currentUser?.id;
      if (uid == null) return;
      await supa
          .from('live_stream_viewers')
          .delete()
          .eq('stream_id', widget.streamId)
          .eq('user_id', uid);
    } catch (_) {}
  }

  void _subscribe() {
    final supa = Supabase.instance.client;

    _viewersChan = supa
        .channel('viewer-viewers-${widget.streamId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'live_stream_viewers',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'stream_id',
            value: widget.streamId,
          ),
          callback: (_) async {
            try {
              final c = await supa
                  .from('live_stream_viewers')
                  .count(CountOption.exact)
                  .eq('stream_id', widget.streamId);
              if (mounted) setState(() => _viewerCount = c);
            } catch (_) {}
          },
        )
        .subscribe();

    _commentsChan = supa
        .channel('viewer-comments-${widget.streamId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'live_stream_comments',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'stream_id',
            value: widget.streamId,
          ),
          callback: (p) {
            final r = p.newRecord;
            if (!mounted) return;
            setState(() {
              _comments.add(_Comment(
                id: r['id']?.toString() ??
                    DateTime.now().millisecondsSinceEpoch.toString(),
                username: r['username'] as String?,
                displayName: r['display_name'] as String?,
                avatarUrl: r['avatar_url'] as String?,
                text: (r['content'] as String?) ?? '',
              ));
              if (_comments.length > 80) _comments.removeAt(0);
            });
            _scrollEnd();
          },
        )
        .subscribe();

    _reactionsChan = supa
        .channel('viewer-reactions-${widget.streamId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'live_stream_reactions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'stream_id',
            value: widget.streamId,
          ),
          callback: (p) {
            final emoji = (p.newRecord['emoji'] as String?) ?? '\u2764\uFE0F';
            _spawnFloat(emoji);
          },
        )
        .subscribe();

    _streamChan = supa
        .channel('viewer-stream-${widget.streamId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'live_streams',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.streamId,
          ),
          callback: (p) {
            final status = p.newRecord['status'] as String?;
            if (status == 'ended' && mounted) {
              setState(() => _state = _StreamState.ended);
              unawaited(_liveRtc?.dispose() ?? Future<void>.value());
            }
          },
        )
        .subscribe();

    _moderationChan = supa
        .channel('viewer-moderation-${widget.streamId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'live_stream_moderation_actions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'stream_id',
            value: widget.streamId,
          ),
          callback: (p) {
            final uid = supa.auth.currentUser?.id;
            final target = p.newRecord['target_user_id']?.toString();
            final action = p.newRecord['action_type']?.toString();
            if (uid == null ||
                target != uid ||
                (action != 'kick' && action != 'ban')) {
              return;
            }
            if (!mounted) return;
            Navigator.of(context).pop();
            AppToast.info(context, action == 'ban'
                    ? 'Live bloklandi'
                    : 'Live dan chiqarildingiz');
          },
        )
        .subscribe();
  }

  void _scrollEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  void _spawnFloat(String emoji) {
    final id =
        '${DateTime.now().millisecondsSinceEpoch}-${_floats.length}-$emoji';
    final right = 16.0 + (DateTime.now().millisecond % 80);
    setState(() => _floats.add(_Float(id: id, emoji: emoji, right: right)));
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _floats.removeWhere((f) => f.id == id));
    });
  }

  Future<void> _sendComment() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    final supa = Supabase.instance.client;
    final user = supa.auth.currentUser;
    if (user == null) return;
    _ctrl.clear();
    HapticFeedback.lightImpact();
    try {
      final me = await supa
          .from('profiles')
          .select('username, display_name, avatar_url')
          .eq('id', user.id)
          .maybeSingle();
      await supa.from('live_stream_comments').insert({
        'stream_id': widget.streamId,
        'user_id': user.id,
        'username': me?['username'],
        'display_name': me?['display_name'],
        'avatar_url': me?['avatar_url'],
        'content': text,
      });
    } catch (_) {}
  }

  Future<void> _react(String emoji) async {
    HapticFeedback.lightImpact();
    setState(() => _showReactions = false);
    _spawnFloat(emoji); // optimistic
    try {
      final supa = Supabase.instance.client;
      final uid = supa.auth.currentUser?.id;
      if (uid == null) return;
      await supa.from('live_stream_reactions').insert({
        'stream_id': widget.streamId,
        'user_id': uid,
        'emoji': emoji,
      });
    } catch (_) {}
  }

  Future<void> _reportStream() async {
    final supa = Supabase.instance.client;
    final uid = supa.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await supa.from('live_stream_reports').insert({
        'stream_id': widget.streamId,
        'reporter_id': uid,
        'reason': 'viewer_report',
      });
      if (!mounted) return;
      AppToast.success(context, 'Shikoyat yuborildi');
    } catch (_) {}
  }

  // ----------------------------- build ----------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _state == _StreamState.loading
          ? _buildLoading()
          : _state == _StreamState.ended
              ? _buildEnded()
              : _state == _StreamState.error
                  ? _buildError()
                  : _buildLive(),
    );
  }

  Widget _buildLoading() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            SizedBox(height: 12),
            Text('Yuklanmoqda...',
                style: TextStyle(color: Colors.white, fontSize: 13)),
          ],
        ),
      );

  Widget _buildEnded() {
    final c = AlsamosColors.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.radio,
              size: 56, color: c.mutedForeground.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          const Text(
            'Translatsiya tugadi',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Bu live tugatildi',
            style: TextStyle(color: Colors.white60, fontSize: 13),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.15),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            ),
            child: const Text('Yopish'),
          ),
        ],
      ),
    );
  }

  Widget _buildError() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.wifiOff, color: Colors.white54, size: 48),
            const SizedBox(height: 12),
            const Text(
              "Translatsiyani topib bo'lmadi",
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.15),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Yopish'),
            ),
          ],
        ),
      );

  Widget _buildLive() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Video placeholder (purple→pink gradient like web while WebRTC absent)
        if (_remoteStream != null)
          RTCVideoView(
            _remoteRenderer,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          )
        else
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF111827),
                  Color(0xFF7F1D1D),
                ],
              ),
            ),
            alignment: Alignment.center,
            child: FadeTransition(
              opacity: Tween(begin: 0.4, end: 0.85).animate(_pulse),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(LucideIcons.radio,
                      size: 80, color: Colors.white24),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      _streamError ?? 'Jonli video ulanmoqda...',
                      textAlign: TextAlign.center,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
        // Top gradient header backdrop
        const Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 140,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xCC000000), Colors.transparent],
                ),
              ),
            ),
          ),
        ),
        // Bottom gradient
        const Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: 280,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0xE6000000), Colors.transparent],
                ),
              ),
            ),
          ),
        ),
        // Header
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: const Color(0xFFEF4444), width: 2),
                    ),
                    padding: const EdgeInsets.all(1),
                    child: StoryAvatarRing(
                      userId: null,
                      avatarUrl: _broadcasterAvatar,
                      fallback:
                          (_broadcasterName ?? _broadcasterUsername ?? 'U')[0]
                              .toUpperCase(),
                      size: 36,
                      backgroundColor: const Color(0xFFEF4444),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(children: [
                          Flexible(
                            child: Text(
                              _broadcasterName ??
                                  _broadcasterUsername ??
                                  'Broadcaster',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FadeTransition(
                            opacity:
                                Tween(begin: 0.55, end: 1.0).animate(_pulse),
                            child: const _LivePill(),
                          ),
                        ]),
                        const SizedBox(height: 4),
                        Row(children: [
                          const Icon(LucideIcons.users,
                              size: 12, color: Colors.white70),
                          const SizedBox(width: 4),
                          Text(
                            '$_viewerCount',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 11),
                          ),
                        ]),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    color: Colors.black.withValues(alpha: 0.86),
                    icon: const Icon(LucideIcons.moreVertical,
                        color: Colors.white),
                    onSelected: (value) {
                      if (value == 'report') _reportStream();
                      if (value == 'close') Navigator.pop(context);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'report',
                        child: Text('Shikoyat qilish'),
                      ),
                      PopupMenuItem(value: 'close', child: Text('Chiqish')),
                    ],
                  ),
                ]),
                if (_title != null && _title!.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, left: 4),
                    child: Text(
                      _title!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
              ],
            ),
          ),
        ),
        // Comments overlay
        Positioned(
          left: 0,
          right: 80,
          bottom: 80,
          height: 220,
          child: IgnorePointer(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(12, 0, 8, 8),
              itemCount: _comments.length,
              itemBuilder: (_, i) => _CommentBubble(c: _comments[i]),
            ),
          ),
        ),
        // Floating reactions
        for (final f in _floats)
          Positioned(
            right: f.right,
            bottom: 160,
            child: _FloatingEmoji(emoji: f.emoji),
          ),
        // Bottom composer + reaction picker
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (_showReactions)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8, right: 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(28),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final e in _kReactionEmojis)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 4),
                                child: GestureDetector(
                                  onTap: () => _react(e),
                                  child: Text(
                                    e,
                                    style: const TextStyle(fontSize: 26),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: "Izoh qo'shing...",
                          hintStyle: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6)),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.1),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          suffixIcon: IconButton(
                            onPressed: _sendComment,
                            icon: const Icon(LucideIcons.send,
                                color: Colors.white70, size: 18),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide(
                                color: Colors.white.withValues(alpha: 0.2)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide(
                                color: Colors.white.withValues(alpha: 0.2)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: const BorderSide(color: Colors.white54),
                          ),
                        ),
                        onSubmitted: (_) => _sendComment(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _CircleBtn(
                      icon: LucideIcons.heart,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _showReactions = !_showReactions);
                      },
                      size: 40,
                      iconSize: 20,
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ============================== WIDGETS ==============================

class _LivePill extends StatelessWidget {
  const _LivePill();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        'LIVE',
        style: TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _CircleBtn extends StatelessWidget {
  const _CircleBtn({
    required this.icon,
    required this.onTap,
    this.size = 36,
    this.iconSize = 18,
  });
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.4),
      shape: const CircleBorder(),
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: iconSize, color: Colors.white),
        ),
      ),
    );
  }
}

class _CommentBubble extends StatelessWidget {
  const _CommentBubble({required this.c});
  final _Comment c;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StoryAvatarRing(
            userId: null,
            avatarUrl: c.avatarUrl,
            fallback: ((c.displayName ?? c.username ?? '?')[0]).toUpperCase(),
            size: 22,
            backgroundColor: Colors.deepPurple,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    c.displayName ?? c.username ?? 'user',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    c.text,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FloatingEmoji extends StatefulWidget {
  const _FloatingEmoji({required this.emoji});
  final String emoji;
  @override
  State<_FloatingEmoji> createState() => _FloatingEmojiState();
}

class _FloatingEmojiState extends State<_FloatingEmoji>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..forward();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Opacity(
        opacity: 1 - _c.value,
        child: Transform.translate(
          offset: Offset(0, -220 * _c.value),
          child: Transform.scale(
            scale: 1 + _c.value * 0.5,
            child: Text(widget.emoji, style: const TextStyle(fontSize: 30)),
          ),
        ),
      ),
    );
  }
}
