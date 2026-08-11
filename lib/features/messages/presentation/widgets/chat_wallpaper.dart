import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../providers/chat_background_provider.dart';

class ChatWallpaper extends ConsumerStatefulWidget {
  final String? conversationId;
  final ChatWallpaperConfig? preview;

  const ChatWallpaper({
    super.key,
    this.conversationId,
    this.preview,
  });

  @override
  ConsumerState<ChatWallpaper> createState() => _ChatWallpaperState();
}

class _ChatWallpaperState extends ConsumerState<ChatWallpaper> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final id = widget.conversationId;
      if (id != null) {
        ref.read(chatWallpaperProvider.notifier).loadForConversation(id);
      }
    });
  }

  @override
  void didUpdateWidget(covariant ChatWallpaper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversationId != widget.conversationId) {
      final id = widget.conversationId;
      if (id != null) {
        ref.read(chatWallpaperProvider.notifier).loadForConversation(id);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ChatWallpaperConfig config = widget.preview ??
        ref.watch(resolvedChatWallpaperProvider(widget.conversationId)) ??
        ChatWallpaperConfig.fallback;
    return Positioned.fill(
      child: RepaintBoundary(child: WallpaperPaint(config: config)),
    );
  }
}

class WallpaperPaint extends StatelessWidget {
  final ChatWallpaperConfig config;

  const WallpaperPaint({super.key, required this.config});

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final dim = (config.dim + (dark ? 0.08 : 0)).clamp(0.0, 0.86);
    Widget child = _wallpaperBody(context, c);
    if (config.blur > 0) {
      child = ImageFiltered(
        imageFilter: ImageFilter.blur(
          sigmaX: config.blur,
          sigmaY: config.blur,
        ),
        child: child,
      );
    }
    return Stack(fit: StackFit.expand, children: [
      child,
      ColoredBox(color: c.background.withValues(alpha: dim)),
    ]);
  }

  Widget _wallpaperBody(BuildContext context, AlsamosColors c) {
    switch (config.type) {
      case ChatWallpaperType.preset:
        return _PresetWallpaper(value: config.value);
      case ChatWallpaperType.color:
        return ColoredBox(color: _hexToColor(config.value) ?? c.background);
      case ChatWallpaperType.gradient:
        final gradient = _decodeGradient(config.value);
        return DecoratedBox(decoration: BoxDecoration(gradient: gradient));
      case ChatWallpaperType.image:
        return _WallpaperImage(value: config.value);
    }
  }
}

class _PresetWallpaper extends StatelessWidget {
  final String value;

  const _PresetWallpaper({required this.value});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PresetWallpaperPainter(value),
      child: const SizedBox.expand(),
    );
  }
}

class _PresetWallpaperPainter extends CustomPainter {
  static const double _patternTile = 300;
  static const double _tileStep = _patternTile;

  final String value;

  const _PresetWallpaperPainter(this.value);

  bool get _dark => value == 'wallpaper2.svg' || value == 'wallpaper4.svg';

  bool get _softGradient =>
      value == 'wallpaper3.svg' || value == 'wallpaper4.svg';

  @override
  void paint(Canvas canvas, Size size) {
    _paintBackground(canvas, size);
    if (_softGradient) {
      _paintSoftShapes(canvas, size);
    } else {
      _paintPattern(canvas, size);
    }
  }

  void _paintBackground(Canvas canvas, Size size) {
    if (value == 'wallpaper3.svg') {
      final paint = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFEEDD), Color(0xFFFBCC93), Color(0xFFF0913F)],
          stops: [0, 0.52, 1],
        ).createShader(Offset.zero & size);
      canvas.drawRect(Offset.zero & size, paint);
      return;
    }
    if (value == 'wallpaper4.svg') {
      final paint = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF161514), Color(0xFF171009), Color(0xFF241809)],
          stops: [0, 0.62, 1],
        ).createShader(Offset.zero & size);
      canvas.drawRect(Offset.zero & size, paint);
      return;
    }

    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = _dark ? const Color(0xFF171310) : const Color(0xFFFFF7F0),
    );
  }

  void _paintSoftShapes(Canvas canvas, Size size) {
    final white = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = Colors.white.withValues(alpha: _dark ? 0.05 : 0.16);
    _drawHexagon(
        canvas, Offset(size.width * 0.18, size.height * 0.28), 120, white);
    _drawHexagon(
        canvas, Offset(size.width * 0.72, size.height * 0.62), 140, white);

    if (!_dark) {
      final glow = Paint()
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 70)
        ..color = Colors.white.withValues(alpha: 0.22);
      canvas.drawCircle(
          Offset(size.width * 0.78, size.height * 0.12), 170, glow);
      canvas.drawCircle(
          Offset(size.width * 0.18, size.height * 0.62), 160, glow);
    } else {
      final glow = Paint()
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 80)
        ..color = const Color(0xFFE8863B).withValues(alpha: 0.28);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(size.width * 0.55, size.height * 0.90),
          width: 520,
          height: 260,
        ),
        glow,
      );
    }
  }

  void _paintPattern(Canvas canvas, Size size) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = (_dark ? const Color(0xFFC6712F) : const Color(0xFFE8863B))
          .withValues(alpha: _dark ? 0.62 : 0.50);
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = stroke.color;

    for (double y = 0; y < size.height + _patternTile; y += _tileStep) {
      for (double x = 0; x < size.width + _patternTile; x += _tileStep) {
        final origin = Offset(x, y);
        _drawPatternTile(canvas, origin, stroke, fill);
      }
    }
  }

  void _drawPatternTile(
      Canvas canvas, Offset origin, Paint stroke, Paint fill) {
    _withIconTransform(canvas, origin + const Offset(33, 28), 6.6, 0.74, () {
      _drawEnvelope(canvas, stroke);
    });
    _withIconTransform(canvas, origin + const Offset(114, 34), -19.4, 0.84, () {
      _drawVideo(canvas, stroke, fill);
    });
    _withIconTransform(canvas, origin + const Offset(175, 36), -18.9, 0.74, () {
      _drawHeart(canvas, stroke);
    });
    _withIconTransform(canvas, origin + const Offset(260, 47), -16.6, 0.77, () {
      _drawBubble(canvas, stroke);
    });
    _withIconTransform(canvas, origin + const Offset(41, 125), 3.4, 0.81, () {
      _drawBag(canvas, stroke);
    });
    _withIconTransform(canvas, origin + const Offset(126, 100), 15.8, 0.79, () {
      _drawRings(canvas, stroke);
    });
    _withIconTransform(canvas, origin + const Offset(178, 102), -8.4, 0.91, () {
      _drawHexagon(canvas, Offset.zero, 16, stroke);
    });
    _withIconTransform(canvas, origin + const Offset(254, 115), 6.1, 0.81, () {
      _drawPin(canvas, stroke);
    });
    _withIconTransform(canvas, origin + const Offset(39, 175), -19.4, 0.77, () {
      _drawCamera(canvas, stroke);
    });
    _withIconTransform(canvas, origin + const Offset(118, 186), -8.2, 0.85, () {
      _drawMusic(canvas, stroke);
    });
    _withIconTransform(canvas, origin + const Offset(186, 182), 13, 0.88, () {
      _drawEnvelope(canvas, stroke);
    });
    _withIconTransform(canvas, origin + const Offset(255, 190), 1.1, 0.92, () {
      _drawVideo(canvas, stroke, fill);
    });
    _withIconTransform(canvas, origin + const Offset(44, 257), 21.1, 0.75, () {
      _drawHeart(canvas, stroke);
    });
    _withIconTransform(canvas, origin + const Offset(110, 270), -15.3, 0.83,
        () {
      _drawBubble(canvas, stroke);
    });
    _withIconTransform(canvas, origin + const Offset(175, 267), 11.6, 0.85, () {
      _drawBag(canvas, stroke);
    });
    _withIconTransform(canvas, origin + const Offset(273, 257), 8.6, 0.86, () {
      _drawRings(canvas, stroke);
    });
  }

  void _withIconTransform(
    Canvas canvas,
    Offset center,
    double degrees,
    double scale,
    VoidCallback draw,
  ) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(degrees * math.pi / 180);
    canvas.scale(scale);
    canvas.translate(-20, -20);
    draw();
    canvas.restore();
  }

  void _drawEnvelope(Canvas canvas, Paint paint) {
    canvas.drawRect(const Rect.fromLTWH(4, 11, 32, 19), paint);
    final path = Path()
      ..moveTo(4, 11)
      ..lineTo(20, 24)
      ..lineTo(36, 11);
    canvas.drawPath(path, paint);
  }

  void _drawVideo(Canvas canvas, Paint stroke, Paint fill) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          const Rect.fromLTWH(3, 9, 34, 22), const Radius.circular(3)),
      stroke,
    );
    final play = Path()
      ..moveTo(17, 15)
      ..lineTo(26, 20)
      ..lineTo(17, 25)
      ..close();
    canvas.drawPath(play, fill);
  }

  void _drawHeart(Canvas canvas, Paint paint) {
    final path = Path()
      ..moveTo(20, 34)
      ..cubicTo(6, 24, 6, 12, 14, 12)
      ..cubicTo(18, 12, 20, 15, 20, 17)
      ..cubicTo(20, 15, 22, 12, 26, 12)
      ..cubicTo(34, 12, 34, 24, 20, 34);
    canvas.drawPath(path, paint);
  }

  void _drawBubble(Canvas canvas, Paint paint) {
    final path = Path()
      ..moveTo(6, 8)
      ..lineTo(32, 8)
      ..quadraticBezierTo(36, 8, 36, 12)
      ..lineTo(36, 25)
      ..quadraticBezierTo(36, 29, 32, 29)
      ..lineTo(17, 29)
      ..lineTo(9, 35)
      ..lineTo(9, 29)
      ..lineTo(6, 29)
      ..quadraticBezierTo(2, 29, 2, 25)
      ..lineTo(2, 12)
      ..quadraticBezierTo(2, 8, 6, 8);
    canvas.drawPath(path, paint);
  }

  void _drawBag(Canvas canvas, Paint paint) {
    final path = Path()
      ..moveTo(11, 14)
      ..lineTo(29, 14)
      ..lineTo(31, 36)
      ..lineTo(9, 36)
      ..close();
    canvas.drawPath(path, paint);
    canvas.drawArc(
        const Rect.fromLTWH(15, 9, 10, 12), math.pi, math.pi, false, paint);
  }

  void _drawRings(Canvas canvas, Paint paint) {
    canvas.drawCircle(const Offset(20, 20), 14, paint);
    canvas.drawCircle(const Offset(20, 20), 8, paint);
  }

  void _drawHexagon(Canvas canvas, Offset center, double radius, Paint paint) {
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final angle = -math.pi / 2 + i * math.pi / 3;
      final point =
          center + Offset(math.cos(angle) * radius, math.sin(angle) * radius);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawPin(Canvas canvas, Paint paint) {
    final path = Path()
      ..moveTo(20, 4)
      ..cubicTo(11, 4, 5, 11, 5, 18)
      ..cubicTo(5, 28, 20, 37, 20, 37)
      ..cubicTo(20, 37, 35, 28, 35, 18)
      ..cubicTo(35, 11, 29, 4, 20, 4);
    canvas.drawPath(path, paint);
    canvas.drawCircle(const Offset(20, 17), 5, paint);
  }

  void _drawCamera(Canvas canvas, Paint paint) {
    final path = Path()
      ..moveTo(6, 14)
      ..lineTo(12, 14)
      ..lineTo(15, 10)
      ..lineTo(25, 10)
      ..lineTo(28, 14)
      ..lineTo(34, 14)
      ..lineTo(34, 31)
      ..lineTo(6, 31)
      ..close();
    canvas.drawPath(path, paint);
    canvas.drawCircle(const Offset(20, 23), 6, paint);
  }

  void _drawMusic(Canvas canvas, Paint paint) {
    final path = Path()
      ..moveTo(16, 28)
      ..lineTo(16, 9)
      ..lineTo(28, 6)
      ..lineTo(28, 25);
    canvas.drawPath(path, paint);
    canvas.drawCircle(const Offset(13, 28), 3.2, paint);
    canvas.drawCircle(const Offset(25, 25), 3.2, paint);
  }

  @override
  bool shouldRepaint(covariant _PresetWallpaperPainter oldDelegate) {
    return oldDelegate.value != value;
  }
}

class _WallpaperImage extends StatefulWidget {
  final String value;
  const _WallpaperImage({required this.value});

  @override
  State<_WallpaperImage> createState() => _WallpaperImageState();
}

class _WallpaperImageState extends State<_WallpaperImage> {
  static final Map<String, String> _signedCache = {};
  late Future<String?> _url;

  @override
  void initState() {
    super.initState();
    _url = _resolveUrl(widget.value);
  }

  @override
  void didUpdateWidget(covariant _WallpaperImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _url = _resolveUrl(widget.value);
    }
  }

  Future<String?> _resolveUrl(String value) async {
    if (value.startsWith('storage://')) {
      final cached = _signedCache[value];
      if (cached != null) return cached;
      final rest = value.substring('storage://'.length);
      final slash = rest.indexOf('/');
      if (slash <= 0) return null;
      final bucket = rest.substring(0, slash);
      final path = rest.substring(slash + 1);
      final signed = await Supabase.instance.client.storage
          .from(bucket)
          .createSignedUrl(path, 60 * 60 * 24 * 7);
      _signedCache[value] = signed;
      return signed;
    }
    return value;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.value.startsWith('/') || widget.value.startsWith('file:')) {
      final path = widget.value.replaceFirst('file://', '');
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    }
    return FutureBuilder<String?>(
      future: _url,
      builder: (context, snap) {
        final url = snap.data;
        if (url == null || url.isEmpty) return const SizedBox.shrink();
        return Image.network(
          url,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        );
      },
    );
  }
}

Color? _hexToColor(String value) {
  final cleaned = value.replaceAll('#', '').trim();
  final full = cleaned.length == 6 ? 'FF$cleaned' : cleaned;
  final intValue = int.tryParse(full, radix: 16);
  return intValue == null ? null : Color(intValue);
}

LinearGradient _decodeGradient(String value) {
  try {
    final json = jsonDecode(value) as Map<String, dynamic>;
    final a =
        _hexToColor(json['a'] as String? ?? '') ?? const Color(0xFFFF7A1A);
    final b =
        _hexToColor(json['b'] as String? ?? '') ?? const Color(0xFF2DD4BF);
    final angle = ((json['angle'] as num?)?.toDouble() ?? 135) * math.pi / 180;
    final x = math.cos(angle);
    final y = math.sin(angle);
    return LinearGradient(
      begin: Alignment(-x, -y),
      end: Alignment(x, y),
      colors: [a, b],
    );
  } catch (_) {
    return const LinearGradient(
      colors: [Color(0xFFFF7A1A), Color(0xFF2DD4BF)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }
}
