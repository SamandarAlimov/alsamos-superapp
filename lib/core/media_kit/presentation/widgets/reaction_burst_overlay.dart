import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../shared/communication/emoji/animated_emoji.dart';

class ReactionBurstOverlay extends StatefulWidget {
  final String emoji;
  final Offset origin;
  final double particleSize;
  final int particleCount;
  final Duration duration;
  final VoidCallback? onComplete;

  const ReactionBurstOverlay({
    super.key,
    required this.emoji,
    required this.origin,
    this.particleSize = 32,
    this.particleCount = 8,
    this.duration = const Duration(milliseconds: 900),
    this.onComplete,
  });

  static OverlayEntry? show(
    BuildContext context, {
    required String emoji,
    required Offset origin,
    int particleCount = 8,
  }) {
    HapticFeedback.mediumImpact();
    final overlay = Overlay.of(context);
    OverlayEntry? entry;
    entry = OverlayEntry(
      builder: (_) => ReactionBurstOverlay(
        emoji: emoji,
        origin: origin,
        particleCount: particleCount,
        onComplete: () => entry?.remove(),
      ),
    );
    overlay.insert(entry);
    return entry;
  }

  @override
  State<ReactionBurstOverlay> createState() => _ReactionBurstOverlayState();
}

class _ReactionBurstOverlayState extends State<ReactionBurstOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Particle> _particles;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _particles = _generateParticles();
    _controller.forward().then((_) {
      widget.onComplete?.call();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<_Particle> _generateParticles() {
    final random = Random(widget.emoji.hashCode);
    return List.generate(widget.particleCount, (i) {
      final angle =
          (2 * pi * i / widget.particleCount) + random.nextDouble() * 0.4;
      final distance = 60.0 + random.nextDouble() * 80;
      final scale = 0.5 + random.nextDouble() * 0.8;
      final rotationSpeed = (random.nextDouble() - 0.5) * 2;
      return _Particle(
        angle: angle,
        distance: distance,
        scale: scale,
        rotationSpeed: rotationSpeed,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        final t = _controller.value;
        final opacity = (1.0 - Curves.easeIn.transform(t)).clamp(0.0, 1.0);

        return Stack(
          children: [
            for (final particle in _particles)
              Positioned(
                left: widget.origin.dx +
                    cos(particle.angle) *
                        particle.distance *
                        Curves.easeOutCubic.transform(t) -
                    widget.particleSize * particle.scale / 2,
                top: widget.origin.dy +
                    sin(particle.angle) *
                        particle.distance *
                        Curves.easeOutCubic.transform(t) -
                    widget.particleSize * particle.scale / 2 +
                    30 * t * t,
                child: Opacity(
                  opacity: opacity,
                  child: Transform.scale(
                    scale: particle.scale *
                        (1.0 + 0.3 * Curves.easeOut.transform(t)),
                    child: Transform.rotate(
                      angle: particle.rotationSpeed * t * pi,
                      child: Text(
                        widget.emoji,
                        style: TextStyle(
                            fontSize: widget.particleSize * particle.scale),
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              left: widget.origin.dx - widget.particleSize,
              top: widget.origin.dy - widget.particleSize,
              child: Opacity(
                opacity: opacity,
                child: Transform.scale(
                  scale:
                      1.0 + 1.2 * Curves.easeOutBack.transform(min(t * 2, 1.0)),
                  child: AnimatedEmoji(
                    emoji: widget.emoji,
                    size: widget.particleSize * 2,
                    replayOnTap: false,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Particle {
  final double angle;
  final double distance;
  final double scale;
  final double rotationSpeed;

  const _Particle({
    required this.angle,
    required this.distance,
    required this.scale,
    required this.rotationSpeed,
  });
}
