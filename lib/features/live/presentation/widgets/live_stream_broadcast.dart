import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../../shared/widgets/user_avatar.dart';
import '../providers/live_webrtc_service.dart';

/// Pixel-perfect Flutter port of web `LiveStreamBroadcast.tsx`.
///
/// Mirrors the two-stage UX:
///   1. **Pre-live**: full-screen camera preview, title input, switch-camera
///      pill, big red "Go Live" CTA, X close.
///   2. **Live**: header (avatar + name + pulsing LIVE badge + viewer count +
///      elapsed time + End button), floating reactions, comments overlay,
///      bottom controls (mic, camera, switch, screen-share, comments toggle).
///
/// Real Supabase wiring:
///   - `live_streams` insert/update (status: live/ended, started_at/ended_at)
///   - `live_stream_viewers` realtime count via postgres_changes
///   - `live_stream_comments` realtime insert subscription
///   - `live_stream_reactions` realtime insert subscription
///
/// Uses `flutter_webrtc` for the actual live audio/video stream.
class LiveStreamBroadcast extends StatefulWidget {
  const LiveStreamBroadcast({super.key, this.initialTitle});
  final String? initialTitle;

  @override
  State<LiveStreamBroadcast> createState() => _LiveStreamBroadcastState();
}

class _LiveStreamBroadcastState extends State<LiveStreamBroadcast>
    with TickerProviderStateMixin {
  // -------------------------- camera ------------------------------
  CameraController? _cam;
  List<CameraDescription> _cams = const [];
  int _camIndex = 0;
  bool _initing = true;
  bool _isCameraOn = true;
  bool _isMuted = false;
  MediaStream? _localStream;
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  LiveWebRtcService? _liveRtc;

  // -------------------------- live state --------------------------
  bool _isLive = false;
  bool _starting = false;
  String? _streamId;
  DateTime? _startedAt;
  int _viewerCount = 0;
  Timer? _tickTimer;
  Duration _elapsed = Duration.zero;

  // -------------------------- ui state ----------------------------
  bool _showComments = true;
  final TextEditingController _titleCtrl = TextEditingController();
  final ScrollController _commentsScroll = ScrollController();

  // -------------------------- realtime ----------------------------
  RealtimeChannel? _viewersChan;
  RealtimeChannel? _commentsChan;
  RealtimeChannel? _reactionsChan;
  final List<_LiveComment> _comments = <_LiveComment>[];
  final List<_FloatingReaction> _floats = <_FloatingReaction>[];

  // -------------------------- profile -----------------------------
  String? _meName;
  String? _meAvatar;

  // -------------------------- animations --------------------------
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _titleCtrl.text = widget.initialTitle ?? '';
    unawaited(_localRenderer.initialize());
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await Future.wait([_initCamera(), _loadProfile()]);
  }

  Future<void> _loadProfile() async {
    try {
      final supa = Supabase.instance.client;
      final uid = supa.auth.currentUser?.id;
      if (uid == null) return;
      final r = await supa
          .from('profiles')
          .select('username, display_name, avatar_url')
          .eq('id', uid)
          .maybeSingle();
      if (!mounted || r == null) return;
      setState(() {
        _meName = (r['display_name'] as String?) ?? (r['username'] as String?);
        _meAvatar = r['avatar_url'] as String?;
      });
    } catch (_) {}
  }

  Future<void> _initCamera() async {
    try {
      _cams = await availableCameras();
      if (_cams.isNotEmpty) {
        _cam = CameraController(
          _cams[_camIndex],
          ResolutionPreset.high,
          enableAudio: true,
        );
        await _cam!.initialize();
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() => _initing = false);
  }

  Future<void> _switchCamera() async {
    HapticFeedback.selectionClick();
    if (_cams.length < 2) return;
    _camIndex = (_camIndex + 1) % _cams.length;
    await _cam?.dispose();
    _cam = CameraController(
      _cams[_camIndex],
      ResolutionPreset.high,
      enableAudio: !_isMuted,
    );
    try {
      await _cam!.initialize();
    } catch (_) {}
    if (mounted) setState(() {});
  }

  void _toggleMute() {
    HapticFeedback.selectionClick();
    setState(() => _isMuted = !_isMuted);
    for (final track in _localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = !_isMuted;
    }
    _cam?.setDescription(_cams[_camIndex]);
  }

  void _toggleCamera() {
    HapticFeedback.selectionClick();
    setState(() => _isCameraOn = !_isCameraOn);
    for (final track in _localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = _isCameraOn;
    }
  }

  // -------------------------- live flow ---------------------------

  Future<void> _goLive() async {
    final supa = Supabase.instance.client;
    final uid = supa.auth.currentUser?.id;
    if (uid == null) {
      _snack('Tizimga kiring');
      return;
    }
    setState(() => _starting = true);
    try {
      // End any existing live streams from this user first.
      await supa
          .from('live_streams')
          .update({
            'status': 'ended',
            'ended_at': DateTime.now().toIso8601String(),
          })
          .eq('user_id', uid)
          .eq('status', 'live');

      final r = await supa
          .from('live_streams')
          .insert({
            'user_id': uid,
            'title': _titleCtrl.text.trim().isEmpty
                ? 'Live Stream'
                : _titleCtrl.text.trim(),
            'status': 'live',
            'viewer_count': 0,
            'started_at': DateTime.now().toIso8601String(),
          })
          .select()
          .single();

      _streamId = r['id'] as String;
      _startedAt = DateTime.tryParse(r['started_at'] as String? ?? '') ??
          DateTime.now();
      await _startLiveWebRtc(_streamId!);
      _subscribeRealtime(_streamId!);
      _startTimer();
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      setState(() => _isLive = true);
      _snack('Endi LIVE!', destructive: false);
    } catch (e) {
      _snack('Boshlab bo\'lmadi: $e');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _startLiveWebRtc(String id) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) throw Exception('Not logged in');
    await _cam?.dispose();
    _cam = null;
    _localStream = await navigator.mediaDevices.getUserMedia({
      'video': _isCameraOn
          ? {
              'facingMode': _camIndex == 0 ? 'user' : 'environment',
              'width': 1280,
              'height': 720,
              'frameRate': 30,
            }
          : false,
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
    }).timeout(const Duration(seconds: 15));
    for (final track in _localStream!.getAudioTracks()) {
      track.enabled = !_isMuted;
    }
    _localRenderer.srcObject = _localStream;
    _liveRtc = LiveWebRtcService(
      streamId: id,
      userId: uid,
      isBroadcaster: true,
      localStream: _localStream,
      onRemoteStream: (_) {},
      onError: (message) => _snack(message),
    );
    await _liveRtc!.connect();
  }

  Future<void> _stopLiveWebRtc() async {
    await _liveRtc?.dispose();
    _liveRtc = null;
    _localStream?.getTracks().forEach((track) => track.stop());
    _localStream = null;
    _localRenderer.srcObject = null;
  }

  void _subscribeRealtime(String id) {
    final supa = Supabase.instance.client;
    _viewersChan = supa
        .channel('bcast-viewers-$id')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'live_stream_viewers',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'stream_id',
            value: id,
          ),
          callback: (_) async {
            try {
              final c = await supa
                  .from('live_stream_viewers')
                  .count(CountOption.exact)
                  .eq('stream_id', id);
              if (mounted) setState(() => _viewerCount = c);
            } catch (_) {}
          },
        )
        .subscribe();

    _commentsChan = supa
        .channel('bcast-comments-$id')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'live_stream_comments',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'stream_id',
            value: id,
          ),
          callback: (p) {
            final r = p.newRecord;
            if (!mounted) return;
            setState(() {
              _comments.add(_LiveComment(
                id: r['id']?.toString() ??
                    DateTime.now().millisecondsSinceEpoch.toString(),
                username: r['username'] as String?,
                avatarUrl: r['avatar_url'] as String?,
                text: (r['content'] as String?) ?? '',
              ));
              if (_comments.length > 80) _comments.removeAt(0);
            });
            _scrollCommentsToEnd();
          },
        )
        .subscribe();

    _reactionsChan = supa
        .channel('bcast-reactions-$id')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'live_stream_reactions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'stream_id',
            value: id,
          ),
          callback: (p) {
            final emoji = (p.newRecord['emoji'] as String?) ?? '\u2764\uFE0F';
            _spawnFloating(emoji);
          },
        )
        .subscribe();
  }

  void _scrollCommentsToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_commentsScroll.hasClients) return;
      _commentsScroll.animateTo(
        _commentsScroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  void _startTimer() {
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_startedAt == null || !mounted) return;
      setState(() => _elapsed = DateTime.now().difference(_startedAt!));
    });
  }

  void _spawnFloating(String emoji) {
    final id =
        '${DateTime.now().millisecondsSinceEpoch}-${_floats.length}-$emoji';
    final offset = 16.0 + (DateTime.now().millisecond % 80);
    setState(() => _floats.add(_FloatingReaction(id: id, emoji: emoji, right: offset)));
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _floats.removeWhere((f) => f.id == id));
    });
  }

  Future<void> _endStream() async {
    HapticFeedback.mediumImpact();
    try {
      final supa = Supabase.instance.client;
      if (_streamId != null) {
        await supa.from('live_streams').update({
          'status': 'ended',
          'ended_at': DateTime.now().toIso8601String(),
        }).eq('id', _streamId!);
      }
      await _stopLiveWebRtc();
      final uid = supa.auth.currentUser?.id;
      if (uid != null) {
        await supa
            .from('live_streams')
            .update({
              'status': 'ended',
              'ended_at': DateTime.now().toIso8601String(),
            })
            .eq('user_id', uid)
            .eq('status', 'live');
      }
    } catch (_) {}
    if (mounted) Navigator.pop(context);
  }

  void _snack(String msg, {bool destructive = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: destructive ? const Color(0xFFEF4444) : null,
      ),
    );
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _liveRtc?.dispose();
    _localStream?.getTracks().forEach((track) => track.stop());
    _localRenderer.dispose();
    _viewersChan?.unsubscribe();
    _commentsChan?.unsubscribe();
    _reactionsChan?.unsubscribe();
    _cam?.dispose();
    _titleCtrl.dispose();
    _commentsScroll.dispose();
    _pulse.dispose();
    super.dispose();
  }

  // ----------------------------- build ----------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _isLive ? _buildLive() : _buildPreLive(),
    );
  }

  // -------------------------- pre-live ----------------------------

  Widget _buildPreLive() {
    final primary = Theme.of(context).colorScheme.primary;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Camera preview / loader
        if (_initing)
          const ColoredBox(
            color: Colors.black,
            child: Center(
                child: SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )),
          )
        else if (_cam != null && _cam!.value.isInitialized && _isCameraOn)
          _CameraSurface(controller: _cam!, mirror: _camIndex == 0)
        else
          Container(
            color: const Color(0xFF101010),
            alignment: Alignment.center,
            child: UserAvatar(
              avatarUrl: _meAvatar,
              fallback: (_meName ?? 'U')[0].toUpperCase(),
              size: 96,
              backgroundColor: const Color(0xFFEF4444),
            ),
          ),
        // Bottom gradient for legibility
        const Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.transparent, Color(0xCC000000)],
                  stops: [0, 0.5, 1],
                ),
              ),
            ),
          ),
        ),
        // Header
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(children: [
              _CircleBtn(
                icon: LucideIcons.x,
                onTap: () => Navigator.pop(context),
              ),
              const Expanded(
                child: Center(
                  child: Text(
                    "Yangi Live Video",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 40),
            ]),
          ),
        ),
        // Switch camera button (top-right)
        Positioned(
          top: MediaQuery.of(context).padding.top + 56,
          right: 12,
          child: _CircleBtn(
            icon: LucideIcons.switchCamera,
            onTap: _switchCamera,
            size: 40,
            iconSize: 18,
          ),
        ),
        // Bottom: title + Go Live
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _titleCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: "Live video uchun sarlavha qo'shing...",
                      hintStyle:
                          TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.1),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.2)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.2)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.white60),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton(
                      onPressed:
                          _starting || _initing ? null : _goLive,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            const Color(0xFFEF4444).withValues(alpha: 0.5),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _starting
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Icon(LucideIcons.radio, size: 18),
                                SizedBox(width: 8),
                                Text(
                                  'Go Live',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                  // Mute / camera toggles
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _ControlBtn(
                          icon: _isMuted ? LucideIcons.micOff : LucideIcons.mic,
                          active: !_isMuted,
                          onTap: _toggleMute,
                        ),
                        const SizedBox(width: 16),
                        _ControlBtn(
                          icon: _isCameraOn
                              ? LucideIcons.camera
                              : LucideIcons.cameraOff,
                          active: _isCameraOn,
                          onTap: _toggleCamera,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Hide unused primary tint -- only used inside FilledButton already.
        // ignore: avoid_unnecessary_containers
        Container(color: primary.withValues(alpha: 0)),
      ],
    );
  }

  // --------------------------- live -------------------------------

  Widget _buildLive() {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_localRenderer.srcObject != null && _isCameraOn)
          RTCVideoView(
            _localRenderer,
            mirror: _camIndex == 0,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          )
        else if (_cam != null && _cam!.value.isInitialized && _isCameraOn)
          _CameraSurface(controller: _cam!, mirror: _camIndex == 0)
        else
          Container(
            color: const Color(0xFF101010),
            alignment: Alignment.center,
            child: UserAvatar(
              avatarUrl: _meAvatar,
              fallback: (_meName ?? 'U')[0].toUpperCase(),
              size: 96,
              backgroundColor: const Color(0xFFEF4444),
            ),
          ),
        // Gradient overlays
        const Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x99000000),
                    Colors.transparent,
                    Colors.transparent,
                    Color(0xCC000000),
                  ],
                  stops: [0, 0.25, 0.6, 1],
                ),
              ),
            ),
          ),
        ),
        // Header
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    UserAvatar(
                      avatarUrl: _meAvatar,
                      fallback: (_meName ?? 'U')[0].toUpperCase(),
                      size: 36,
                      backgroundColor: const Color(0xFFEF4444),
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
                                _meName ?? 'You',
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
                            const SizedBox(width: 12),
                            const Icon(LucideIcons.clock,
                                size: 12, color: Colors.white70),
                            const SizedBox(width: 4),
                            Text(
                              _formatElapsed(_elapsed),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ]),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: 32,
                      child: FilledButton(
                        onPressed: _endStream,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFEF4444),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          textStyle: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                        child: const Text('End'),
                      ),
                    ),
                  ],
                ),
                if (_titleCtrl.text.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _titleCtrl.text.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 13),
                    ),
                  ),
              ],
            ),
          ),
        ),
        // Comments overlay
        if (_showComments)
          Positioned(
            left: 0,
            right: 80,
            bottom: 92,
            height: 200,
            child: IgnorePointer(
              child: ListView.builder(
                controller: _commentsScroll,
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
            bottom: 140,
            child: _FloatingEmoji(emoji: f.emoji),
          ),
        // Bottom controls
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ControlBtn(
                    icon: _isMuted ? LucideIcons.micOff : LucideIcons.mic,
                    active: !_isMuted,
                    onTap: _toggleMute,
                  ),
                  const SizedBox(width: 12),
                  _ControlBtn(
                    icon: _isCameraOn
                        ? LucideIcons.camera
                        : LucideIcons.cameraOff,
                    active: _isCameraOn,
                    onTap: _toggleCamera,
                  ),
                  const SizedBox(width: 12),
                  _ControlBtn(
                    icon: LucideIcons.switchCamera,
                    active: true,
                    onTap: _switchCamera,
                  ),
                  const SizedBox(width: 12),
                  _ControlBtn(
                    icon: LucideIcons.messageCircle,
                    active: _showComments,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _showComments = !_showComments);
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ------------------------------ utils ---------------------------

  String _formatElapsed(Duration d) {
    if (_startedAt == null) return '0:00';
    // Web uses formatDistanceToNow → mirror with timeago for >1m, else mm:ss.
    if (d.inMinutes < 1) {
      final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
      return '0:$s';
    }
    if (d.inMinutes < 60) {
      final m = d.inMinutes;
      final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
      return '$m:$s';
    }
    return timeago.format(_startedAt!, locale: 'en');
  }
}

// ============================== WIDGETS ==============================

class _CameraSurface extends StatelessWidget {
  const _CameraSurface({required this.controller, required this.mirror});
  final CameraController controller;
  final bool mirror;
  @override
  Widget build(BuildContext context) {
    final preview = CameraPreview(controller);
    if (!mirror) return preview;
    return Transform(
      alignment: Alignment.center,
      // ignore: deprecated_member_use
      transform: Matrix4.identity()..scale(-1.0, 1.0, 1.0),
      child: preview,
    );
  }
}

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
      color: Colors.white.withValues(alpha: 0.2),
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

class _ControlBtn extends StatelessWidget {
  const _ControlBtn({
    required this.icon,
    required this.active,
    required this.onTap,
  });
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active
          ? Colors.white.withValues(alpha: 0.2)
          : const Color(0xFFEF4444),
      shape: const CircleBorder(),
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

class _CommentBubble extends StatelessWidget {
  const _CommentBubble({required this.c});
  final _LiveComment c;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserAvatar(
            avatarUrl: c.avatarUrl,
            fallback: (c.username ?? '?')[0].toUpperCase(),
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
                    c.username ?? 'user',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    c.text,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 13),
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
          offset: Offset(0, -200 * _c.value),
          child: Transform.scale(
            scale: 1 + _c.value * 0.5,
            child: Text(widget.emoji,
                style: const TextStyle(fontSize: 30)),
          ),
        ),
      ),
    );
  }
}

class _LiveComment {
  const _LiveComment({
    required this.id,
    required this.username,
    required this.avatarUrl,
    required this.text,
  });
  final String id;
  final String? username;
  final String? avatarUrl;
  final String text;
}

class _FloatingReaction {
  const _FloatingReaction({
    required this.id,
    required this.emoji,
    required this.right,
  });
  final String id;
  final String emoji;
  final double right;
}
