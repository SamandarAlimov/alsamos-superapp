import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:video_player/video_player.dart';

import 'video_seek_bar.dart';

enum VideoDisplayMode {
  reel,
  landscape,
  inline,
  mini,
}

class UnifiedVideoPlayer extends StatefulWidget {
  final VideoPlayerController controller;
  final VideoDisplayMode mode;
  final bool autoHideControls;
  final Duration autoHideDuration;
  final VoidCallback? onExpandToggle;
  final VoidCallback? onClose;
  final bool showTopBar;
  final String? title;
  final String? subtitle;
  final List<double>? heatmapData;
  final Widget? bottomExtra;

  const UnifiedVideoPlayer({
    super.key,
    required this.controller,
    this.mode = VideoDisplayMode.landscape,
    this.autoHideControls = true,
    this.autoHideDuration = const Duration(seconds: 3),
    this.onExpandToggle,
    this.onClose,
    this.showTopBar = true,
    this.title,
    this.subtitle,
    this.heatmapData,
    this.bottomExtra,
  });

  @override
  State<UnifiedVideoPlayer> createState() => _UnifiedVideoPlayerState();
}

class _UnifiedVideoPlayerState extends State<UnifiedVideoPlayer>
    with SingleTickerProviderStateMixin {
  bool _showControls = true;
  bool _dragging = false;
  Timer? _hideTimer;
  double _playbackSpeed = 1.0;
  bool _showSpeedMenu = false;
  bool _showSeekIndicator = false;
  int _seekSeconds = 0;
  bool _seekForward = true;
  late final AnimationController _controlsFade;
  final FocusNode _focusNode = FocusNode();

  static const _speeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  @override
  void initState() {
    super.initState();
    _controlsFade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      value: 1.0,
    );
    widget.controller.addListener(_onVideoUpdate);
    _scheduleHide();
  }

  @override
  void didUpdateWidget(covariant UnifiedVideoPlayer old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onVideoUpdate);
      widget.controller.addListener(_onVideoUpdate);
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controlsFade.dispose();
    _focusNode.dispose();
    widget.controller.removeListener(_onVideoUpdate);
    super.dispose();
  }

  void _onVideoUpdate() {
    if (mounted) setState(() {});
  }

  void _scheduleHide() {
    if (!widget.autoHideControls) return;
    _hideTimer?.cancel();
    _hideTimer = Timer(widget.autoHideDuration, () {
      if (mounted && widget.controller.value.isPlaying && !_dragging) {
        _setControlsVisible(false);
      }
    });
  }

  void _setControlsVisible(bool visible) {
    setState(() => _showControls = visible);
    if (visible) {
      _controlsFade.forward();
      _scheduleHide();
    } else {
      _controlsFade.reverse();
      _showSpeedMenu = false;
    }
  }

  void _toggleControls() {
    _setControlsVisible(!_showControls);
  }

  void _togglePlay() {
    HapticFeedback.selectionClick();
    if (widget.controller.value.isPlaying) {
      widget.controller.pause();
      _setControlsVisible(true);
    } else {
      widget.controller.play();
      _scheduleHide();
    }
  }

  void _seek(Duration offset) {
    final current = widget.controller.value.position;
    final duration = widget.controller.value.duration;
    final target = current + offset;
    widget.controller.seekTo(
      target < Duration.zero
          ? Duration.zero
          : target > duration
              ? duration
              : target,
    );
  }

  void _seekToFraction(double fraction) {
    final duration = widget.controller.value.duration;
    widget.controller.seekTo(duration * fraction);
  }

  void _doubleTapSeek({required bool forward}) {
    HapticFeedback.lightImpact();
    final seconds = forward ? 10 : -10;
    _seek(Duration(seconds: seconds));
    setState(() {
      _showSeekIndicator = true;
      _seekSeconds = seconds.abs();
      _seekForward = forward;
    });
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _showSeekIndicator = false);
    });
  }

  void _setSpeed(double speed) {
    setState(() {
      _playbackSpeed = speed;
      _showSpeedMenu = false;
    });
    widget.controller.setPlaybackSpeed(speed);
    _scheduleHide();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.keyK) {
      _togglePlay();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.keyJ) {
      _seek(const Duration(seconds: -5));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.keyL) {
      _seek(const Duration(seconds: 5));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      final vol = (widget.controller.value.volume + 0.1).clamp(0.0, 1.0);
      widget.controller.setVolume(vol);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      final vol = (widget.controller.value.volume - 0.1).clamp(0.0, 1.0);
      widget.controller.setVolume(vol);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyM) {
      final vol = widget.controller.value.volume;
      widget.controller.setVolume(vol > 0 ? 0 : 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyF) {
      widget.onExpandToggle?.call();
      return KeyEventResult.handled;
    }

    // 0-9: jump to percentage
    final digit = _digitFromKey(key);
    if (digit != null) {
      _seekToFraction(digit / 10);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  int? _digitFromKey(LogicalKeyboardKey key) {
    const keys = [
      LogicalKeyboardKey.digit0,
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8,
      LogicalKeyboardKey.digit9,
    ];
    final idx = keys.indexOf(key);
    return idx >= 0 ? idx : null;
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.controller.value;
    final isReelMode = widget.mode == VideoDisplayMode.reel;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: MouseRegion(
        onEnter: (_) => _setControlsVisible(true),
        onExit: (_) {
          if (value.isPlaying && !_dragging) _setControlsVisible(false);
        },
        child: GestureDetector(
          onTap: isReelMode ? _togglePlay : _toggleControls,
          behavior: HitTestBehavior.opaque,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Video surface
              _buildVideoSurface(value),

              // Double-tap seek zones (non-reel modes)
              if (!isReelMode) _buildDoubleTapZones(),

              // Seek indicator animation
              if (_showSeekIndicator) _buildSeekIndicator(),

              // Controls overlay
              if (!isReelMode)
                FadeTransition(
                  opacity: _controlsFade,
                  child: IgnorePointer(
                    ignoring: !_showControls,
                    child: _buildControlsOverlay(context, value),
                  ),
                ),

              // Reel mode: minimal bottom progress bar
              if (isReelMode) _buildReelProgressBar(value),

              // Speed menu
              if (_showSpeedMenu) _buildSpeedMenu(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoSurface(VideoPlayerValue value) {
    if (!value.isInitialized) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: value.aspectRatio,
          child: VideoPlayer(widget.controller),
        ),
      ),
    );
  }

  Widget _buildDoubleTapZones() {
    return Positioned.fill(
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onDoubleTap: () => _doubleTapSeek(forward: false),
              behavior: HitTestBehavior.translucent,
            ),
          ),
          const Expanded(child: SizedBox.expand()),
          Expanded(
            child: GestureDetector(
              onDoubleTap: () => _doubleTapSeek(forward: true),
              behavior: HitTestBehavior.translucent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeekIndicator() {
    return Positioned(
      left: _seekForward ? null : 48,
      right: _seekForward ? 48 : null,
      top: 0,
      bottom: 0,
      child: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 300),
          builder: (_, val, child) => Opacity(opacity: val, child: child),
          child: Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              shape: BoxShape.circle,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _seekForward ? LucideIcons.rotateCw : LucideIcons.rotateCcw,
                  color: Colors.white,
                  size: 28,
                ),
                const SizedBox(height: 4),
                Text(
                  '$_seekSeconds soniya',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControlsOverlay(BuildContext context, VideoPlayerValue value) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Gradient scrim
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0x66000000),
                Colors.transparent,
                Colors.transparent,
                Color(0xAA000000),
              ],
              stops: [0.0, 0.2, 0.7, 1.0],
            ),
          ),
        ),

        // Top bar
        if (widget.showTopBar)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildTopBar(context),
          ),

        // Center play/pause
        Center(child: _buildCenterButton(value)),

        // Bottom bar with seek + controls
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _buildBottomBar(context, value),
        ),
      ],
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            if (widget.onClose != null)
              _ControlButton(
                icon: LucideIcons.chevronDown,
                onTap: widget.onClose!,
              ),
            if (widget.title != null) ...[
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.title!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (widget.subtitle != null)
                      Text(
                        widget.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
            ] else
              const Spacer(),
            _ControlButton(
              icon: LucideIcons.settings,
              onTap: () => setState(() => _showSpeedMenu = !_showSpeedMenu),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterButton(VideoPlayerValue value) {
    if (value.isBuffering) {
      return const SizedBox(
        width: 48,
        height: 48,
        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
      );
    }
    return GestureDetector(
      onTap: _togglePlay,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          shape: BoxShape.circle,
        ),
        child: Icon(
          value.isPlaying ? LucideIcons.pause : LucideIcons.play,
          color: Colors.white,
          size: 28,
        ),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context, VideoPlayerValue value) {
    final position = value.position;
    final duration = value.duration;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Professional seek bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: VideoSeekBar(
                controller: widget.controller,
                heatmapData: widget.heatmapData,
                onDragStart: () {
                  _dragging = true;
                  _hideTimer?.cancel();
                },
                onDragEnd: () {
                  _dragging = false;
                  _scheduleHide();
                },
              ),
            ),
            const SizedBox(height: 6),
            // Bottom controls row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final showSkipButtons = width >= 400;
                  final showSpeedIndicator = width >= 350;
                  
                  return Row(
                    children: [
                      // Play/pause small
                      _ControlButton(
                        icon: value.isPlaying ? LucideIcons.pause : LucideIcons.play,
                        size: 20,
                        onTap: _togglePlay,
                      ),
                      const SizedBox(width: 8),
                      // Skip back (hidden on narrow screens)
                      if (showSkipButtons) ...[
                        _ControlButton(
                          icon: LucideIcons.skipBack,
                          size: 18,
                          onTap: () => _seek(const Duration(seconds: -10)),
                        ),
                        const SizedBox(width: 4),
                        // Skip forward
                        _ControlButton(
                          icon: LucideIcons.skipForward,
                          size: 18,
                          onTap: () => _seek(const Duration(seconds: 10)),
                        ),
                        const SizedBox(width: 10),
                      ],
                      // Time
                      Expanded(
                        child: Text(
                          '${_formatDuration(position)} / ${_formatDuration(duration)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Right controls — speed, volume, fullscreen
                      if (showSpeedIndicator)
                        GestureDetector(
                          onTap: () =>
                              setState(() => _showSpeedMenu = !_showSpeedMenu),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _playbackSpeed != 1.0
                                  ? Colors.white.withValues(alpha: 0.15)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${_playbackSpeed}x',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      if (showSpeedIndicator) const SizedBox(width: 8),
                      _VolumeControl(controller: widget.controller),
                      if (widget.onExpandToggle != null) ...[
                        const SizedBox(width: 8),
                        _ControlButton(
                          icon: LucideIcons.maximize2,
                          size: 18,
                          onTap: widget.onExpandToggle!,
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
            if (widget.bottomExtra != null) ...[
              const SizedBox(height: 4),
              widget.bottomExtra!,
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildReelProgressBar(VideoPlayerValue value) {
    if (!value.isInitialized) return const SizedBox.shrink();
    final duration = value.duration.inMilliseconds;
    if (duration <= 0) return const SizedBox.shrink();
    final progress = value.position.inMilliseconds / duration;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: LinearProgressIndicator(
        value: progress.clamp(0.0, 1.0),
        minHeight: 2.5,
        backgroundColor: Colors.white.withValues(alpha: 0.2),
        valueColor: const AlwaysStoppedAnimation(Colors.white),
      ),
    );
  }

  Widget _buildSpeedMenu(BuildContext context) {
    return Positioned(
      right: 12,
      bottom: 80,
      child: Container(
        width: 140,
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xE6212121),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 4, left: 12, right: 12),
              child: Text(
                'Tezlik',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ..._speeds.map((s) {
              final active = s == _playbackSpeed;
              return InkWell(
                onTap: () => _setSpeed(s),
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  color: active
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.transparent,
                  child: Row(
                    children: [
                      if (active)
                        const Icon(LucideIcons.check,
                            size: 14, color: Colors.white)
                      else
                        const SizedBox(width: 14),
                      const SizedBox(width: 8),
                      Text(
                        '${s}x',
                        style: TextStyle(
                          color: active ? Colors.white : Colors.white70,
                          fontSize: 13,
                          fontWeight:
                              active ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                      if (s == 1.0) ...[
                        const Spacer(),
                        Text(
                          'Normal',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;

  const _ControlButton({
    required this.icon,
    required this.onTap,
    this.size = 22,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkResponse(
        onTap: onTap,
        radius: size + 4,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: size, color: Colors.white),
        ),
      ),
    );
  }
}

class _VolumeControl extends StatefulWidget {
  final VideoPlayerController controller;
  const _VolumeControl({required this.controller});

  @override
  State<_VolumeControl> createState() => _VolumeControlState();
}

class _VolumeControlState extends State<_VolumeControl> {
  bool _expanded = false;
  double _volume = 1.0;

  @override
  void initState() {
    super.initState();
    _volume = widget.controller.value.volume;
    widget.controller.addListener(_sync);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sync);
    super.dispose();
  }

  void _sync() {
    if (mounted) {
      final v = widget.controller.value.volume;
      if (v != _volume) setState(() => _volume = v);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return MouseRegion(
        onEnter: (_) => setState(() => _expanded = true),
        onExit: (_) => setState(() => _expanded = false),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ControlButton(
              icon: _volume == 0
                  ? LucideIcons.volumeX
                  : _volume < 0.5
                      ? LucideIcons.volume1
                      : LucideIcons.volume2,
              size: 18,
              onTap: () {
                final next = _volume > 0 ? 0.0 : 1.0;
                setState(() => _volume = next);
                widget.controller.setVolume(next);
              },
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: _expanded ? 70 : 0,
              clipBehavior: Clip.hardEdge,
              decoration: const BoxDecoration(),
              child: _expanded
                  ? SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape:
                            const RoundSliderThumbShape(enabledThumbRadius: 5),
                        overlayShape:
                            const RoundSliderOverlayShape(overlayRadius: 10),
                        activeTrackColor: Colors.white,
                        inactiveTrackColor: Colors.white30,
                        thumbColor: Colors.white,
                      ),
                      child: Slider(
                        value: _volume,
                        onChanged: (v) {
                          setState(() => _volume = v);
                          widget.controller.setVolume(v);
                        },
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      );
    }
    // Mobile: just mute toggle
    return _ControlButton(
      icon: _volume == 0 ? LucideIcons.volumeX : LucideIcons.volume2,
      size: 18,
      onTap: () {
        final next = _volume > 0 ? 0.0 : 1.0;
        setState(() => _volume = next);
        widget.controller.setVolume(next);
      },
    );
  }
}
