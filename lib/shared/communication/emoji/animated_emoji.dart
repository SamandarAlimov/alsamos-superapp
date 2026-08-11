import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'emoji_animation_renderer.dart';
import 'emoji_asset.dart';
import 'emoji_asset_provider.dart';
import 'emoji_playback_policy.dart';

class AnimatedEmojiAssets {
  AnimatedEmojiAssets._();

  static final Set<String> _loggedMissing = <String>{};

  static String? assetFor(String emoji) {
    return resolve(emoji)?.assetPath;
  }

  static EmojiAsset? resolve(String emoji) {
    return AlsamosAnimatedEmojiEngine.resolve(emoji);
  }

  static bool hasAsset(String emoji) => resolve(emoji) != null;

  static void logMissing(String emoji) {
    if (!kDebugMode || _loggedMissing.contains(emoji)) return;
    _loggedMissing.add(emoji);
    debugPrint('[AnimatedEmoji] Missing animated asset for $emoji');
  }
}

class AnimatedEmoji extends StatefulWidget {
  final String emoji;
  final double size;
  final bool animate;
  final BoxFit fit;
  final bool replayOnTap;
  final String? playbackKey;
  final double restingProgress;

  const AnimatedEmoji({
    super.key,
    required this.emoji,
    required this.size,
    this.animate = true,
    this.fit = BoxFit.contain,
    this.replayOnTap = true,
    this.playbackKey,
    this.restingProgress = 0,
  });

  @override
  State<AnimatedEmoji> createState() => _AnimatedEmojiState();
}

enum EmojiPlaybackState {
  initial,
  visible,
  playing,
  completed,
  static,
}

class _AnimatedEmojiState extends State<AnimatedEmoji>
    with SingleTickerProviderStateMixin {
  static final EmojiPlaybackHistory _playbackHistory =
      EmojiPlaybackHistory(maxEntries: 512);

  late final AnimationController _controller;
  EmojiAsset? _asset;
  EmojiPlaybackState _playbackState = EmojiPlaybackState.initial;
  String? _loadedAssetPath;
  int _playGeneration = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    _asset = AnimatedEmojiAssets.resolve(widget.emoji);
  }

  @override
  void didUpdateWidget(covariant AnimatedEmoji oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.emoji != widget.emoji ||
        oldWidget.playbackKey != widget.playbackKey) {
      _asset = AnimatedEmojiAssets.resolve(widget.emoji);
      _loadedAssetPath = null;
      _playbackState = EmojiPlaybackState.initial;
      _playGeneration++;
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _playOnce() {
    if (!_canAnimate) {
      _showRestingFrame();
      return;
    }
    final generation = ++_playGeneration;
    _setPlaybackState(EmojiPlaybackState.playing);
    _controller.stop();
    _controller.reset();
    _controller.forward().whenCompleteOrCancel(() {
      if (!mounted || generation != _playGeneration) return;
      _setPlaybackState(EmojiPlaybackState.completed);
      _showRestingFrame(setStaticState: true);
    });
  }

  void _showRestingFrame({bool setStaticState = true}) {
    if (!mounted) return;
    final progress = widget.restingProgress.clamp(0.0, 1.0).toDouble();
    _controller
      ..stop()
      ..value = progress;
    if (setStaticState) _setPlaybackState(EmojiPlaybackState.static);
  }

  bool get _canAnimate => widget.animate && !_reduceMotion;

  bool get _reduceMotion {
    final mediaQuery = MediaQuery.maybeOf(context);
    return mediaQuery?.disableAnimations == true ||
        mediaQuery?.accessibleNavigation == true;
  }

  String get _stablePlaybackKey {
    final asset = _asset;
    if (widget.playbackKey case final key?) return key;
    if (asset == null) return widget.emoji;
    return '${asset.source.name}:${asset.id}:${asset.emoji}';
  }

  bool _hasSeenPlaybackKey(String key) => _playbackHistory.hasSeen(key);

  void _setPlaybackState(EmojiPlaybackState state) {
    if (_playbackState == state) return;
    _playbackState = state;
  }

  void _handleLoaded(EmojiAsset asset, Duration duration) {
    _controller.duration = duration;
    if (_loadedAssetPath == asset.assetPath &&
        _playbackState != EmojiPlaybackState.initial) {
      return;
    }

    _loadedAssetPath = asset.assetPath;
    _setPlaybackState(EmojiPlaybackState.visible);
    if (!_canAnimate) {
      _showRestingFrame();
      return;
    }

    final key = _stablePlaybackKey;
    if (_hasSeenPlaybackKey(key)) {
      _showRestingFrame();
      return;
    }

    _playbackHistory.markSeen(key);
    _playOnce();
  }

  void _logRenderError(EmojiAsset asset, Object error) {
    if (!kDebugMode) return;
    debugPrint('[AnimatedEmoji] Failed to load ${asset.assetPath}: $error');
  }

  @override
  Widget build(BuildContext context) {
    final asset = _asset;
    if (asset == null) {
      AnimatedEmojiAssets.logMissing(widget.emoji);
      return _textFallback();
    }

    final renderer = EmojiAnimationRenderers.resolve(asset);
    if (renderer == null) return _textFallback();

    final rendered = renderer.build(
      asset: asset,
      controller: _controller,
      size: widget.size,
      fit: widget.fit,
      fallback: _textFallback(),
      onLoaded: (duration) => _handleLoaded(asset, duration),
      onError: (error) => _logRenderError(asset, error),
    );

    if (!widget.replayOnTap || !_canAnimate) return rendered;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _playOnce,
      child: rendered,
    );
  }

  Widget _textFallback() {
    return Semantics(
      label: widget.emoji,
      child: Text(
        widget.emoji,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: widget.size, height: 1),
      ),
    );
  }
}
