import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
        return SvgPicture.asset(
          'assets/wallpapers/${config.value}',
          fit: BoxFit.cover,
        );
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
