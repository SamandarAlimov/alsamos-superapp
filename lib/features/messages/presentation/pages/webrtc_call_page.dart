import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../data/models/call_quality.dart';
import '../providers_webrtc/call_provider.dart';
import '../widgets/network_quality_indicator.dart';

const bool _showCallDebugHud = bool.fromEnvironment(
  'SHOW_CALL_DEBUG_HUD',
  defaultValue: false,
);

/// Real WebRTC video/audio call page – mirrors web VideoCallOverlay.tsx
class WebRTCCallPage extends ConsumerStatefulWidget {
  final String roomId;
  final String? remoteName;
  final String? remoteAvatar;
  final bool isVideo;
  final VoidCallback? onCallEnd;

  const WebRTCCallPage({
    super.key,
    required this.roomId,
    this.remoteName,
    this.remoteAvatar,
    this.isVideo = true,
    this.onCallEnd,
  });

  @override
  ConsumerState<WebRTCCallPage> createState() => _WebRTCCallPageState();
}

class _WebRTCCallPageState extends ConsumerState<WebRTCCallPage> {
  final _localRenderer = RTCVideoRenderer();
  final Map<String, RTCVideoRenderer> _remoteRenderers = {};
  final Map<String, Future<RTCVideoRenderer>> _remoteRendererCreates = {};
  bool _controlsVisible = true;
  bool _leftRoom = false;
  bool _minimized = false;
  bool _localRendererReady = false;
  Offset? _pipOffset;
  String _lastParticipantLogKey = '';
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    unawaited(WakelockPlus.enable());
    _bootstrapCall();
    _scheduleHide();
  }

  Future<void> _bootstrapCall() async {
    await _localRenderer.initialize();
    _localRendererReady = true;
    if (!mounted) return;
    await _markJoined();
    if (!mounted) return;
    await ref
        .read(callProvider(widget.roomId).notifier)
        .joinRoom(videoOn: widget.isVideo);
  }

  Future<void> _markJoined() async {
    final sb = Supabase.instance.client;
    final uid = sb.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await sb.from('call_participants').upsert({
        'call_id': widget.roomId,
        'user_id': uid,
        'joined_at': DateTime.now().toUtc().toIso8601String(),
        'left_at': null,
        'is_muted': false,
        'is_video_on': widget.isVideo,
        'is_screen_sharing': false,
        'is_hand_raised': false,
        'connection_state': 'joining',
        'last_seen_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'call_id,user_id').timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('[WebRTCCallPage] participant join mark ignored: $e');
    }
  }

  Future<void> _markLeft() async {
    final sb = Supabase.instance.client;
    final uid = sb.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await sb
          .from('call_participants')
          .update({
            'left_at': DateTime.now().toUtc().toIso8601String(),
            'connection_state': 'left',
            'last_seen_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('call_id', widget.roomId)
          .eq('user_id', uid)
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('[WebRTCCallPage] participant leave mark ignored: $e');
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    if (!_leftRoom && !_minimized) {
      unawaited(ref.read(callProvider(widget.roomId).notifier).leaveRoom());
      unawaited(_markLeft());
      _leftRoom = true;
    }
    _localRenderer.dispose();
    for (final r in _remoteRenderers.values) {
      r.dispose();
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    unawaited(WakelockPlus.disable());
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _showControls() {
    setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  Future<RTCVideoRenderer> _getOrCreateRenderer(
      String id, MediaStream stream) async {
    final existing = _remoteRenderers[id];
    if (existing != null) {
      if (!identical(existing.srcObject, stream)) {
        if (kDebugMode) {
          debugPrint('[WebRTCCallPage][$id] remote renderer stream changed');
        }
        existing.srcObject = stream;
      }
      return existing;
    }
    return _remoteRendererCreates.putIfAbsent(id, () async {
      final r = RTCVideoRenderer();
      await r.initialize();
      r.srcObject = stream;
      _remoteRenderers[id] = r;
      if (mounted) setState(() {});
      return r;
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<CallState>(callProvider(widget.roomId), (previous, next) {
      if (kDebugMode) {
        final participantKey = next.participants.map((p) => p.id).join(',');
        if (participantKey != _lastParticipantLogKey) {
          debugPrint('[WebRTCCallPage][${widget.roomId}] participants '
              'count=${next.participants.length} ids=$participantKey');
          _lastParticipantLogKey = participantKey;
        }
      }
      if (_leftRoom || !next.hasEnded) return;
      _leftRoom = true;
      _hideTimer?.cancel();
      if (mounted) {
        Navigator.of(context).maybePop(next.elapsed);
      }
    });

    final callState = ref.watch(callProvider(widget.roomId));
    final notifier = ref.read(callProvider(widget.roomId).notifier);

    // Update local renderer
    if (_localRendererReady &&
        callState.localStream != null &&
        !identical(_localRenderer.srcObject, callState.localStream)) {
      if (kDebugMode) {
        debugPrint('[WebRTCCallPage] local renderer stream changed');
      }
      _localRenderer.srcObject = callState.localStream;
    }

    final elapsed = callState.elapsed;
    final timeStr =
        '${elapsed.inMinutes.toString().padLeft(2, '0')}:${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}';

    final quality = switch (callState.quality.quality) {
      CallNetworkQuality.excellent => NetworkQuality.excellent,
      CallNetworkQuality.good => NetworkQuality.good,
      CallNetworkQuality.fair => NetworkQuality.fair,
      CallNetworkQuality.poor => NetworkQuality.poor,
      CallNetworkQuality.disconnected => NetworkQuality.disconnected,
    };

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _showControls,
        child: Stack(
          children: [
            // ── Remote video(s) ───────────────────────────────────────────────
            if (callState.participants.isEmpty)
              _WaitingScreen(
                remoteName: widget.remoteName,
                remoteAvatar: widget.remoteAvatar,
                isConnecting: callState.isConnecting,
                isVideo: widget.isVideo,
              )
            else if (callState.participants.length == 1)
              _buildRemoteTile(
                callState.participants.first,
                participantCount: callState.participants.length,
              )
            else
              Positioned.fill(
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 96, 8, 120),
                    child: GridView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 0.78,
                      ),
                      itemCount: callState.participants.length,
                      itemBuilder: (_, i) => ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: _buildRemoteSurface(
                          callState.participants[i],
                          participantCount: callState.participants.length,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // ── Local PiP ─────────────────────────────────────────────────────
            if (widget.isVideo && callState.localStream != null)
              _buildLocalPip(callState),

            // ── Top bar ───────────────────────────────────────────────────────
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 48, 16, 52),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
                child: IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: AnimatedOpacity(
                    opacity: _controlsVisible ? 1 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: Row(children: [
                      IconButton(
                        tooltip: 'Kichraytirish',
                        onPressed: () {
                          _minimized = true;
                          ref.read(callMiniOverlayProvider.notifier).state =
                              MiniCallSession(
                            roomId: widget.roomId,
                            remoteName: widget.remoteName,
                            remoteAvatar: widget.remoteAvatar,
                            isVideo: widget.isVideo,
                          );
                          Navigator.of(context).pop();
                        },
                        icon: const Icon(LucideIcons.minimize2,
                            color: Colors.white),
                      ),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(widget.remoteName ?? 'Foydalanuvchi',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 18)),
                              Text(
                                _callStatusText(callState, timeStr),
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 13),
                              ),
                            ]),
                      ),
                      NetworkQualityIndicator(
                        quality: quality,
                        rttMs: callState.quality.rttMs,
                        packetLoss: callState.quality.packetLoss,
                        isReconnecting: callState.isReconnecting,
                        showDetails: _showCallDebugHud,
                      ),
                    ]),
                  ),
                ),
              ),
            ),

            // ── Bottom controls ───────────────────────────────────────────────
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 40, 16, 28),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
                child: IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: AnimatedOpacity(
                    opacity: _controlsVisible ? 1 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.38),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 14,
                            runSpacing: 10,
                            children: [
                              _CallBtn(
                                icon: callState.isMuted
                                    ? LucideIcons.micOff
                                    : LucideIcons.mic,
                                label: callState.isMuted
                                    ? 'Mikrofonni yoqish'
                                    : 'Mikrofonni o\'chirish',
                                active: callState.isMuted,
                                onTap: notifier.toggleMute,
                              ),
                              if (widget.isVideo)
                                _CallBtn(
                                  icon: callState.isVideoOn
                                      ? LucideIcons.video
                                      : LucideIcons.videoOff,
                                  label: callState.isVideoOn
                                      ? 'Kamerani o\'chirish'
                                      : 'Kamerani yoqish',
                                  active: !callState.isVideoOn,
                                  onTap: notifier.toggleVideo,
                                ),
                              _CallBtn(
                                icon: LucideIcons.handMetal,
                                label: callState.isHandRaised
                                    ? 'Qo\'lni tushirish'
                                    : 'Qo\'l ko\'tarish',
                                active: callState.isHandRaised,
                                onTap: notifier.toggleHandRaise,
                              ),
                              if (widget.isVideo)
                                _CallBtn(
                                  icon: callState.isScreenSharing
                                      ? LucideIcons.screenShareOff
                                      : LucideIcons.screenShare,
                                  label: callState.isScreenSharing
                                      ? 'Ekranni to\'xtatish'
                                      : 'Ekranni ulashish',
                                  active: callState.isScreenSharing,
                                  onTap: () => _toggleScreenShare(
                                    callState,
                                    notifier,
                                  ),
                                ),
                              _CallBtn(
                                icon: LucideIcons.userPlus,
                                label: 'Odam qo‘shish',
                                tooltip: 'Qo‘ng‘iroqqa odam qo‘shish',
                                active: false,
                                onTap: _showAddPeopleSheet,
                              ),
                              _CallBtn(
                                icon: LucideIcons.settings2,
                                label: 'Qurilmalar',
                                tooltip: 'Audio/video qurilmalari',
                                active: false,
                                onTap: () =>
                                    _showDeviceSheet(callState, notifier),
                              ),
                              _EndCallBtn(onTap: () async {
                                final elapsed = callState.elapsed;
                                _leftRoom = true;
                                ref
                                    .read(callMiniOverlayProvider.notifier)
                                    .state = null;
                                await notifier.leaveRoom();
                                if (mounted) {
                                  Navigator.of(context).pop(elapsed);
                                }
                                widget.onCallEnd?.call();
                              }),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ── Error overlay ─────────────────────────────────────────────────
            if (callState.error != null)
              Positioned(
                top: 100,
                left: 24,
                right: 24,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red[900]!.withAlpha(200),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(callState.error!,
                        style: const TextStyle(color: Colors.white),
                        textAlign: TextAlign.center),
                    if (widget.isVideo && _isCameraError(callState.error!)) ...[
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: notifier.retryCamera,
                        icon: const Icon(LucideIcons.refreshCw, size: 16),
                        label: const Text('Kamerani qayta urinish'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                        ),
                      ),
                    ],
                  ]),
                ),
              ),
            if (_showCallDebugHud) _CallDebugOverlay(callState: callState),
          ],
        ),
      ),
    );
  }

  Widget _buildLocalPip(CallState callState) {
    final size = MediaQuery.sizeOf(context);
    final pipWidth = (size.width * 0.15).clamp(156.0, 220.0);
    final pipHeight = pipWidth * 0.72;
    final offset = _pipOffset ??
        Offset(
          size.width - pipWidth - 16,
          size.height - pipHeight - 128,
        );
    final left = offset.dx.clamp(12.0, size.width - pipWidth - 12);
    final top = offset.dy.clamp(72.0, size.height - pipHeight - 112);

    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        onPanUpdate: (details) {
          final next = Offset(left, top) + details.delta;
          setState(() {
            _pipOffset = Offset(
              next.dx.clamp(12.0, size.width - pipWidth - 12),
              next.dy.clamp(72.0, size.height - pipHeight - 112),
            );
          });
        },
        child: Container(
          width: pipWidth,
          height: pipHeight,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (callState.isVideoOn)
                RTCVideoView(
                  _localRenderer,
                  mirror: true,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                )
              else
                Container(
                  color: Colors.grey[850],
                  child: const Icon(
                    LucideIcons.videoOff,
                    color: Colors.white54,
                    size: 28,
                  ),
                ),
              Positioned(
                left: 8,
                bottom: 8,
                child: _CallBadge(
                  icon: LucideIcons.user,
                  label: 'Siz',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _callStatusText(CallState callState, String timeText) {
    if (callState.isReconnecting) return 'Qayta ulanmoqda...';
    if (callState.isConnecting) return 'Ulanmoqda...';
    if (callState.participants.isEmpty) return 'Javob kutilmoqda...';
    if (callState.quality.quality == CallNetworkQuality.poor) {
      return 'Internet sifati past';
    }
    if (!widget.isVideo || !callState.isVideoOn) return 'Faqat audio';
    return timeText;
  }

  Widget _buildRemoteTile(
    WebRTCParticipant participant, {
    required int participantCount,
  }) {
    return Positioned.fill(
      child: _buildRemoteSurface(
        participant,
        participantCount: participantCount,
      ),
    );
  }

  Widget _buildRemoteSurface(
    WebRTCParticipant participant, {
    required int participantCount,
  }) {
    if (participant.stream != null) {
      unawaited(_getOrCreateRenderer(participant.id, participant.stream!));
    }
    final renderer = _remoteRenderers[participant.id];
    final hasVideoTrack = participant.stream
            ?.getVideoTracks()
            .any((track) => track.enabled && track.kind == 'video') ??
        false;
    if (renderer == null ||
        participant.stream == null ||
        !widget.isVideo ||
        !participant.isVideoOn ||
        !hasVideoTrack) {
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: _RemoteAudioScreen(
          key: ValueKey('avatar-${participant.id}'),
          name: _participantDisplayName(participant, participantCount),
          avatarUrl: _participantAvatarUrl(participantCount),
          isMuted: participant.isMuted,
          status: widget.isVideo && !participant.isVideoOn
              ? 'Kamera o\'chiq'
              : 'Faqat audio',
        ),
      );
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: Stack(
        key: ValueKey('video-${participant.id}'),
        fit: StackFit.expand,
        children: [
          RTCVideoView(
            renderer,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          ),
          if (participant.isScreenSharing)
            Positioned(
              left: 10,
              top: 10,
              child: _CallBadge(
                icon: LucideIcons.screenShare,
                label: 'Ekran',
              ),
            ),
        ],
      ),
    );
  }

  bool _isCameraError(String error) {
    final message = error.toLowerCase();
    return message.contains('kamera') ||
        message.contains('camera') ||
        message.contains('notreadable') ||
        message.contains('could not start video source');
  }

  String _participantDisplayName(
    WebRTCParticipant participant,
    int participantCount,
  ) {
    if (participantCount == 1 && widget.remoteName?.trim().isNotEmpty == true) {
      return widget.remoteName!.trim();
    }
    return 'Foydalanuvchi';
  }

  String? _participantAvatarUrl(int participantCount) {
    if (participantCount == 1 &&
        widget.remoteAvatar?.trim().isNotEmpty == true) {
      return widget.remoteAvatar!.trim();
    }
    return null;
  }

  Future<void> _toggleScreenShare(
    CallState callState,
    CallNotifier notifier,
  ) async {
    _showControls();
    if (callState.isScreenSharing || kIsWeb || !_isDesktopPlatform) {
      await notifier.toggleScreenShare();
      return;
    }

    final source = await _pickDesktopCaptureSource();
    if (source == null) return;
    await notifier.toggleScreenShare(sourceId: source.id);
  }

  bool get _isDesktopPlatform {
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  Future<DesktopCapturerSource?> _pickDesktopCaptureSource() async {
    try {
      final sources = await desktopCapturer.getSources(
        types: [SourceType.Screen, SourceType.Window],
        thumbnailSize: ThumbnailSize(320, 180),
      );
      if (!mounted) return null;
      if (sources.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ekran yoki oyna topilmadi')),
        );
        return null;
      }
      return showDialog<DesktopCapturerSource>(
        context: context,
        barrierColor: Colors.black87,
        builder: (context) => Dialog(
          backgroundColor: const Color(0xFF111827),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760, maxHeight: 620),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(LucideIcons.screenShare, color: Colors.white),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Ekran yoki oynani tanlang',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(LucideIcons.x, color: Colors.white70),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Flexible(
                    child: GridView.builder(
                      shrinkWrap: true,
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 220,
                        mainAxisExtent: 168,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: sources.length,
                      itemBuilder: (context, index) {
                        final source = sources[index];
                        return _DesktopCaptureSourceTile(
                          source: source,
                          onTap: () => Navigator.of(context).pop(source),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ekran ro\'yxati ochilmadi: $e')),
        );
      }
      return null;
    }
  }

  Future<void> _showAddPeopleSheet() async {
    if (!mounted) return;
    final sb = Supabase.instance.client;
    final uid = sb.auth.currentUser?.id;
    if (uid == null) return;

    var candidates = <_CallInviteCandidate>[];
    String? loadError;

    try {
      final call = await sb
          .from('video_calls')
          .select('conversation_id')
          .eq('id', widget.roomId)
          .maybeSingle()
          .timeout(const Duration(seconds: 8));
      final conversationId = call?['conversation_id']?.toString();
      if (conversationId == null || conversationId.isEmpty) {
        throw StateError('conversation_not_found');
      }

      final memberRows = await sb
          .from('conversation_participants')
          .select('user_id')
          .eq('conversation_id', conversationId)
          .timeout(const Duration(seconds: 8));

      final activeRows = await sb
          .from('call_participants')
          .select('user_id')
          .eq('call_id', widget.roomId)
          .isFilter('left_at', null)
          .timeout(const Duration(seconds: 8));

      final activeIds = <String>{uid};
      for (final row in activeRows as List) {
        if (row is Map && row['user_id'] != null) {
          activeIds.add(row['user_id'].toString());
        }
      }

      final candidateIds = <String>{};
      for (final row in memberRows as List) {
        if (row is! Map || row['user_id'] == null) continue;
        final id = row['user_id'].toString();
        if (!activeIds.contains(id)) candidateIds.add(id);
      }

      if (candidateIds.isNotEmpty) {
        final profileRows = await sb
            .from('profiles')
            .select('id,display_name,username,avatar_url,last_seen')
            .inFilter('id', candidateIds.toList())
            .timeout(const Duration(seconds: 8));

        candidates = (profileRows as List)
            .whereType<Map>()
            .map(
              (row) => _CallInviteCandidate(
                id: row['id'].toString(),
                name: row['display_name']?.toString().trim().isNotEmpty == true
                    ? row['display_name'].toString()
                    : row['username']?.toString().trim().isNotEmpty == true
                        ? row['username'].toString()
                        : 'Foydalanuvchi',
                avatarUrl: row['avatar_url']?.toString(),
                lastSeen: row['last_seen']?.toString(),
              ),
            )
            .toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      }
    } catch (error) {
      debugPrint('[WebRTCCallPage] add people load failed: $error');
      loadError = 'Kontaktlarni yuklab bo‘lmadi';
    }

    if (!mounted) return;
    final query = TextEditingController();
    final invited = <String>{};

    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111827),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final search = query.text.trim().toLowerCase();
            final visible = candidates
                .where((candidate) =>
                    search.isEmpty || candidate.name.toLowerCase().contains(search))
                .toList();

            return SafeArea(
              child: FractionallySizedBox(
                heightFactor: MediaQuery.sizeOf(context).height < 700 ? 0.86 : 0.72,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
                      child: Column(
                        children: [
                          Container(
                            width: 42,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          const SizedBox(height: 14),
                          const Row(
                            children: [
                              Icon(LucideIcons.userPlus,
                                  color: Colors.white70, size: 20),
                              SizedBox(width: 9),
                              Text(
                                'Odam qo‘shish',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: query,
                            onChanged: (_) => setSheetState(() {}),
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              hintText: 'Qidirish',
                              hintStyle: const TextStyle(color: Colors.white38),
                              prefixIcon: const Icon(
                                LucideIcons.search,
                                size: 18,
                                color: Colors.white38,
                              ),
                              filled: true,
                              fillColor: Colors.white.withValues(alpha: 0.06),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide:
                                    const BorderSide(color: Colors.white10),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: Colors.white10),
                    Expanded(
                      child: loadError != null
                          ? Center(
                              child: Text(
                                loadError!,
                                style: const TextStyle(color: Colors.white54),
                              ),
                            )
                          : visible.isEmpty
                              ? const Center(
                                  child: Text(
                                    'Taklif qilinadigan boshqa a’zo yo‘q',
                                    style: TextStyle(color: Colors.white54),
                                  ),
                                )
                              : ListView.builder(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  itemCount: visible.length,
                                  itemBuilder: (context, index) {
                                    final candidate = visible[index];
                                    final sent = invited.contains(candidate.id);
                                    return ListTile(
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 18, vertical: 3),
                                      leading: CircleAvatar(
                                        radius: 21,
                                        backgroundColor: Colors.white12,
                                        backgroundImage: candidate.avatarUrl
                                                    ?.trim()
                                                    .isNotEmpty ==
                                                true
                                            ? NetworkImage(candidate.avatarUrl!)
                                            : null,
                                        child: candidate.avatarUrl
                                                    ?.trim()
                                                    .isNotEmpty ==
                                                true
                                            ? null
                                            : Text(
                                                candidate.initials,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                      ),
                                      title: Text(
                                        candidate.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                      ),
                                      subtitle: Text(
                                        sent
                                            ? 'Taklif yuborildi'
                                            : candidate.statusLabel,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: sent
                                              ? const Color(0xFF4ADE80)
                                              : Colors.white38,
                                          fontSize: 12,
                                        ),
                                      ),
                                      trailing: sent
                                          ? const Icon(
                                              LucideIcons.check,
                                              color: Color(0xFF4ADE80),
                                              size: 20,
                                            )
                                          : Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                IconButton(
                                                  tooltip:
                                                      'Audio bilan taklif qilish',
                                                  onPressed: () async {
                                                    final ok =
                                                        await _inviteToCall(
                                                      candidate,
                                                      withVideo: false,
                                                    );
                                                    if (ok && context.mounted) {
                                                      setSheetState(() =>
                                                          invited.add(
                                                              candidate.id));
                                                    }
                                                  },
                                                  icon: const Icon(
                                                    LucideIcons.phone,
                                                    size: 19,
                                                    color: Colors.white70,
                                                  ),
                                                ),
                                                IconButton(
                                                  tooltip:
                                                      'Video bilan taklif qilish',
                                                  onPressed: () async {
                                                    final ok =
                                                        await _inviteToCall(
                                                      candidate,
                                                      withVideo: true,
                                                    );
                                                    if (ok && context.mounted) {
                                                      setSheetState(() =>
                                                          invited.add(
                                                              candidate.id));
                                                    }
                                                  },
                                                  icon: const Icon(
                                                    LucideIcons.video,
                                                    size: 19,
                                                    color: Colors.white70,
                                                  ),
                                                ),
                                              ],
                                            ),
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
      },
    );

    query.dispose();
  }

  Future<bool> _inviteToCall(
    _CallInviteCandidate candidate, {
    required bool withVideo,
  }) async {
    final sb = Supabase.instance.client;
    final callType = withVideo ? 'video' : 'audio';

    try {
      await sb.rpc('invite_to_video_call', params: {
        'p_call_id': widget.roomId,
        'p_invitee_id': candidate.id,
        'p_call_type': callType,
      }).timeout(const Duration(seconds: 8));
      return true;
    } catch (error) {
      if (!_isMissingCallInviteRpc(error)) {
        debugPrint('[WebRTCCallPage] invite RPC failed: $error');
      }
    }

    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final call = await sb
          .from('video_calls')
          .select('conversation_id')
          .eq('id', widget.roomId)
          .maybeSingle()
          .timeout(const Duration(seconds: 5));
      final conversationId = call?['conversation_id'];

      final existing = await sb
          .from('call_invites')
          .select('id')
          .eq('call_id', widget.roomId)
          .eq('invitee_id', candidate.id)
          .maybeSingle()
          .timeout(const Duration(seconds: 5));

      if (existing != null && existing['id'] != null) {
        await sb
            .from('call_invites')
            .update({
              'status': 'pending',
              'call_type': callType,
              'updated_at': now,
            })
            .eq('id', existing['id'])
            .timeout(const Duration(seconds: 5));
      } else {
        await sb.from('call_invites').insert({
          'call_id': widget.roomId,
          'conversation_id': conversationId,
          'inviter_id': sb.auth.currentUser?.id,
          'invitee_id': candidate.id,
          'status': 'pending',
          'call_type': callType,
          'metadata': const <String, dynamic>{},
          'updated_at': now,
        }).timeout(const Duration(seconds: 5));
      }
      return true;
    } catch (error) {
      debugPrint('[WebRTCCallPage] invite compatibility fallback failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Taklif yuborilmadi. Qayta urinib ko‘ring.')),
        );
      }
      return false;
    }
  }

  bool _isMissingCallInviteRpc(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('pgrst202') ||
        text.contains('42883') ||
        text.contains('invite_to_video_call') &&
            (text.contains('does not exist') || text.contains('could not find'));
  }

  Future<void> _showDeviceSheet(
    CallState state,
    CallNotifier notifier,
  ) async {
    await notifier.refreshDevices();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF111827),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final devices = ref.watch(callProvider(widget.roomId)).devices;
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              const Text('Qurilmalar',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 18)),
              const SizedBox(height: 12),
              _DeviceSection(
                title: 'Mikrofon',
                devices: devices.where((d) => d.kind == 'audioinput').toList(),
                selectedId: state.selectedAudioInputId,
                onTap: (id) async {
                  Navigator.pop(context);
                  await notifier.switchMicrophone(id);
                },
              ),
              _DeviceSection(
                title: 'Kamera',
                devices: devices.where((d) => d.kind == 'videoinput').toList(),
                selectedId: state.selectedVideoInputId,
                onTap: (id) async {
                  Navigator.pop(context);
                  await notifier.switchCamera(id);
                },
              ),
              _DeviceSection(
                title: 'Speaker',
                devices: devices.where((d) => d.kind == 'audiooutput').toList(),
                selectedId: state.selectedAudioOutputId,
                onTap: (id) async {
                  Navigator.pop(context);
                  await notifier.selectSpeaker(id);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Helper widgets ───────────────────────────────────────────────────────────
class _CallInviteCandidate {
  const _CallInviteCandidate({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.lastSeen,
  });

  final String id;
  final String name;
  final String? avatarUrl;
  final String? lastSeen;

  String get initials => name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2)
      .map((part) => part[0].toUpperCase())
      .join();

  String get statusLabel {
    final parsed = DateTime.tryParse(lastSeen ?? '');
    if (parsed == null) return 'Qo‘ng‘iroqqa taklif qilish';
    final age = DateTime.now().toUtc().difference(parsed.toUtc());
    if (age.inMinutes < 2) return 'hozirgina faol';
    if (age.inMinutes < 60) return age.inMinutes.toString() + ' daqiqa oldin faol';
    if (age.inHours < 24) return age.inHours.toString() + ' soat oldin faol';
    return 'yaqinda faol';
  }
}

class _CallDebugOverlay extends StatelessWidget {
  const _CallDebugOverlay({required this.callState});

  final CallState callState;

  @override
  Widget build(BuildContext context) {
    final q = callState.quality;
    return Positioned(
      left: 12,
      bottom: 132,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withAlpha(165),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white24),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: DefaultTextStyle(
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                height: 1.25,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('ICE ${callState.iceConnectionState}'),
                  Text('PC ${callState.peerConnectionState}'),
                  Text('pair ${q.selectedCandidateType ?? 'unknown'}'),
                  Text('aud ${q.audioBytesSent}/${q.audioBytesReceived}'),
                  Text('vid ${q.videoBytesSent}/${q.videoBytesReceived}'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WaitingScreen extends StatelessWidget {
  final String? remoteName;
  final String? remoteAvatar;
  final bool isConnecting;
  final bool isVideo;

  const _WaitingScreen(
      {this.remoteName,
      this.remoteAvatar,
      required this.isConnecting,
      required this.isVideo});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.blueGrey[900]!, Colors.blueGrey[800]!],
        ),
      ),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (remoteAvatar != null && remoteAvatar!.isNotEmpty)
            CircleAvatar(
                radius: 48, backgroundImage: NetworkImage(remoteAvatar!))
          else
            CircleAvatar(
              radius: 48,
              backgroundColor: Colors.white24,
              child: Text(
                (remoteName?.isNotEmpty == true
                    ? remoteName![0].toUpperCase()
                    : '?'),
                style: const TextStyle(
                    fontSize: 32,
                    color: Colors.white,
                    fontWeight: FontWeight.bold),
              ),
            ),
          const SizedBox(height: 16),
          Text(remoteName ?? 'Foydalanuvchi',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(
            isConnecting ? 'Ulanmoqda...' : 'Kutmoqda...',
            style: const TextStyle(color: Colors.white70, fontSize: 15),
          ),
          if (isConnecting) ...[
            const SizedBox(height: 24),
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2),
            ),
          ]
        ]),
      ),
    );
  }
}

class _RemoteAudioScreen extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  final bool isMuted;
  final String? status;

  const _RemoteAudioScreen({
    super.key,
    required this.name,
    this.avatarUrl,
    required this.isMuted,
    this.status,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.blueGrey[900],
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircleAvatar(
            radius: 48,
            backgroundColor: Colors.white24,
            backgroundImage:
                avatarUrl?.isNotEmpty == true ? NetworkImage(avatarUrl!) : null,
            child: avatarUrl?.isNotEmpty == true
                ? null
                : Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(fontSize: 32, color: Colors.white)),
          ),
          const SizedBox(height: 12),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (status != null) ...[
            const SizedBox(height: 6),
            Text(
              status!,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
          const SizedBox(height: 12),
          if (isMuted)
            const Icon(LucideIcons.micOff, color: Colors.white54, size: 20),
        ]),
      ),
    );
  }
}

class _CallBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? tooltip;
  final bool active;
  final VoidCallback onTap;

  const _CallBtn(
      {required this.icon,
      required this.label,
      this.tooltip,
      required this.onTap,
      this.active = false});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? label,
      child: Semantics(
        button: true,
        label: tooltip ?? label,
        child: GestureDetector(
          onTap: onTap,
          child: SizedBox(
            width: 76,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: active ? Colors.white : Colors.white24,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon,
                    color: active ? Colors.black : Colors.white, size: 22),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _DesktopCaptureSourceTile extends StatelessWidget {
  const _DesktopCaptureSourceTile({
    required this.source,
    required this.onTap,
  });

  final DesktopCapturerSource source;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final thumbnail = source.thumbnail;
    return Material(
      color: Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: thumbnail == null || thumbnail.isEmpty
                  ? Container(
                      color: Colors.black26,
                      child: Icon(
                        source.type == SourceType.Screen
                            ? LucideIcons.monitor
                            : LucideIcons.panelTop,
                        color: Colors.white54,
                        size: 38,
                      ),
                    )
                  : Image.memory(
                      thumbnail,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Icon(
                    source.type == SourceType.Screen
                        ? LucideIcons.monitor
                        : LucideIcons.panelTop,
                    color: Colors.white70,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      source.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
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
}

class _CallBadge extends StatelessWidget {
  const _CallBadge({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}

class _DeviceSection extends StatelessWidget {
  const _DeviceSection({
    required this.title,
    required this.devices,
    required this.selectedId,
    required this.onTap,
  });

  final String title;
  final List<CallMediaDevice> devices;
  final String? selectedId;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    if (devices.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 6),
        child: Text(title,
            style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w700)),
      ),
      for (final d in devices)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            selectedId == d.deviceId
                ? LucideIcons.circleCheck
                : LucideIcons.circle,
            color: selectedId == d.deviceId
                ? const Color(0xFF22C55E)
                : Colors.white54,
          ),
          title: Text(d.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white)),
          onTap: () => onTap(d.deviceId),
        ),
    ]);
  }
}

class _EndCallBtn extends StatelessWidget {
  final VoidCallback onTap;
  const _EndCallBtn({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Qo\'ng\'iroqni tugatish',
      child: Semantics(
        button: true,
        label: 'Qo\'ng\'iroqni tugatish',
        child: GestureDetector(
          onTap: onTap,
          child: SizedBox(
            width: 76,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 54,
                height: 54,
                decoration: const BoxDecoration(
                  color: Color(0xFFEF4444),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  LucideIcons.phoneOff,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(height: 6),
              const Text('Tugatish',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white70, fontSize: 11)),
            ]),
          ),
        ),
      ),
    );
  }
}
