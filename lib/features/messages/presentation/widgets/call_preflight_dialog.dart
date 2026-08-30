import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

/// Telegram-style pre-call surface shared by desktop/mobile Flutter targets.
///
/// The preview stream is intentionally isolated from the production call
/// stream and is fully released BEFORE [onStart] executes. This avoids
/// camera-busy / NotReadable errors on Windows, Linux, browsers and phones
/// that only permit one active capture session.
class CallPreflightDialog extends StatefulWidget {
  const CallPreflightDialog({
    super.key,
    required this.peerName,
    this.peerAvatar,
    required this.initialType,
    required this.onStart,
  });

  final String peerName;
  final String? peerAvatar;
  final String initialType; // audio | video
  final Future<void> Function(String type) onStart;

  static Future<void> show(
    BuildContext context, {
    required String peerName,
    String? peerAvatar,
    required String initialType,
    required Future<void> Function(String type) onStart,
  }) {
    return showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.76),
      builder: (_) => CallPreflightDialog(
        peerName: peerName,
        peerAvatar: peerAvatar,
        initialType: initialType,
        onStart: onStart,
      ),
    );
  }

  @override
  State<CallPreflightDialog> createState() => _CallPreflightDialogState();
}

class _CallPreflightDialogState extends State<CallPreflightDialog> {
  final RTCVideoRenderer _renderer = RTCVideoRenderer();
  MediaStream? _previewStream;

  bool _rendererReady = false;
  bool _previewing = false;
  bool _previewBusy = false;
  String? _previewError;
  String? _startingType;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    await _renderer.initialize();
    if (!mounted) {
      await _renderer.dispose();
      return;
    }
    setState(() => _rendererReady = true);

    if (widget.initialType == 'video') {
      await _startPreview();
    }
  }

  Future<void> _startPreview() async {
    if (_previewBusy || _startingType != null) return;
    _previewBusy = true;
    if (mounted) {
      setState(() {
        _previewError = null;
      });
    }

    await _stopPreview(notify: false);

    try {
      final stream = await navigator.mediaDevices.getUserMedia({
        'video': {
          'width': {'ideal': 1280, 'max': 1920},
          'height': {'ideal': 720, 'max': 1080},
          'frameRate': {'ideal': 30, 'max': 60},
          'facingMode': 'user',
        },
        'audio': false,
      }).timeout(const Duration(seconds: 12));

      if (!mounted) {
        for (final track in stream.getTracks()) {
          track.stop();
        }
        await stream.dispose();
        return;
      }

      _previewStream = stream;
      _renderer.srcObject = stream;
      setState(() => _previewing = true);
    } catch (error) {
      if (!mounted) return;
      final raw = error.toString().toLowerCase();
      setState(() {
        _previewing = false;
        _previewError = raw.contains('permission') ||
                raw.contains('notallowed') ||
                raw.contains('denied')
            ? 'Kameraga ruxsat berilmadi'
            : raw.contains('notfound') || raw.contains('no device')
                ? 'Kamera topilmadi'
                : raw.contains('busy') ||
                        raw.contains('readable') ||
                        raw.contains('in use')
                    ? 'Kamera boshqa dastur tomonidan ishlatilmoqda'
                    : 'Kamerani ishga tushirib bo‘lmadi';
      });
    } finally {
      _previewBusy = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _stopPreview({bool notify = true}) async {
    final stream = _previewStream;
    _previewStream = null;
    _renderer.srcObject = null;

    if (stream != null) {
      for (final track in stream.getTracks()) {
        track.stop();
      }
      try {
        await stream.dispose();
      } catch (_) {}
    }

    if (notify && mounted) setState(() => _previewing = false);
  }

  Future<void> _begin(String type) async {
    if (_startingType != null) return;
    HapticFeedback.mediumImpact();
    setState(() => _startingType = type);

    // Important: free the preview camera first, then acquire the real call
    // media inside CallNotifier/WebRTCCallPage.
    await _stopPreview(notify: false);
    await Future<void>.delayed(const Duration(milliseconds: 80));

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    try {
      await widget.onStart(type);
    } catch (_) {
      // The call starter owns user-facing error mapping.
    }
  }

  @override
  void dispose() {
    final stream = _previewStream;
    _previewStream = null;
    if (stream != null) {
      for (final track in stream.getTracks()) {
        track.stop();
      }
      unawaited(stream.dispose());
    }
    _renderer.srcObject = null;
    unawaited(_renderer.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 600 || size.height < 650;
    final maxWidth = compact ? size.width - 20 : 680.0;
    final previewHeight = compact
        ? (size.height * 0.52).clamp(300.0, 480.0)
        : 430.0;

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 28,
        vertical: compact ? 18 : 28,
      ),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(compact ? 24 : 30),
          child: Material(
            color: const Color(0xFF11161D),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: previewHeight,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildPreviewStage(),
                      const IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.center,
                              colors: [Color(0x99000000), Colors.transparent],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 16,
                        right: 16,
                        top: 14,
                        child: SafeArea(
                          bottom: false,
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.peerName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16,
                                      ),
                                    ),
                                    Text(
                                      _previewing
                                          ? 'Kamera ko‘rinishi'
                                          : 'Qo‘ng‘iroqqa tayyor',
                                      style: const TextStyle(
                                        color: Colors.white60,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              _RoundIconButton(
                                icon: LucideIcons.x,
                                tooltip: 'Bekor qilish',
                                onTap: _startingType == null
                                    ? () => Navigator.of(
                                          context,
                                          rootNavigator: true,
                                        ).pop()
                                    : null,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_previewError != null)
                        Positioned(
                          left: 24,
                          right: 24,
                          top: 72,
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEF4444)
                                    .withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: const Color(0xFFEF4444)
                                      .withValues(alpha: 0.25),
                                ),
                              ),
                              child: Text(
                                _previewError!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFFFFD5D5),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        left: 16,
                        bottom: 14,
                        child: _PreviewToggle(
                          previewing: _previewing,
                          busy: _previewBusy,
                          onTap: _startingType != null
                              ? null
                              : () {
                                  if (_previewing) {
                                    unawaited(_stopPreview());
                                  } else {
                                    unawaited(_startPreview());
                                  }
                                },
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.fromLTRB(
                    compact ? 8 : 24,
                    18,
                    compact ? 8 : 24,
                    20,
                  ),
                  decoration: const BoxDecoration(
                    border: Border(
                      top: BorderSide(color: Color(0x1FFFFFFF)),
                    ),
                  ),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.start,
                    spacing: compact ? 8 : 26,
                    runSpacing: 8,
                    children: [
                      _PreflightAction(
                        icon: LucideIcons.video,
                        label: _startingType == 'video'
                            ? 'Boshlanmoqda...'
                            : 'Video',
                        color: const Color(0xFF22C55E),
                        enabled: _startingType == null,
                        onTap: () => unawaited(_begin('video')),
                      ),
                      _PreflightAction(
                        icon: LucideIcons.x,
                        label: 'Bekor qilish',
                        color: Colors.white,
                        foreground: const Color(0xFF11161D),
                        enabled: _startingType == null,
                        onTap: () =>
                            Navigator.of(context, rootNavigator: true).pop(),
                      ),
                      _PreflightAction(
                        icon: LucideIcons.phone,
                        label: _startingType == 'audio'
                            ? 'Boshlanmoqda...'
                            : 'Audio',
                        color: const Color(0xFF22C55E),
                        enabled: _startingType == null,
                        onTap: () => unawaited(_begin('audio')),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewStage() {
    if (_previewing && _rendererReady) {
      return RTCVideoView(
        _renderer,
        mirror: true,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      );
    }

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.25),
          radius: 1.1,
          colors: [
            Color(0xFF21384A),
            Color(0xFF111820),
            Color(0xFF090C10),
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PeerAvatar(
              name: widget.peerName,
              avatarUrl: widget.peerAvatar,
              size: 116,
            ),
            const SizedBox(height: 18),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                widget.peerName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 5),
            const Text(
              'Qo‘ng‘iroqqa tayyor',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeerAvatar extends StatelessWidget {
  const _PeerAvatar({
    required this.name,
    required this.avatarUrl,
    required this.size,
  });

  final String name;
  final String? avatarUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = avatarUrl?.trim();
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.1),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14), width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black45, blurRadius: 24, offset: Offset(0, 10)),
        ],
      ),
      child: url != null && url.isNotEmpty
          ? Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _fallback(),
            )
          : _fallback(),
    );
  }

  Widget _fallback() => Center(
        child: Text(
          name.trim().isEmpty
              ? '?'
              : name
                  .trim()
                  .split(RegExp(r'\s+'))
                  .take(2)
                  .map((part) => part.isEmpty ? '' : part[0].toUpperCase())
                  .join(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onTap,
        style: IconButton.styleFrom(
          backgroundColor: Colors.black.withValues(alpha: 0.32),
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.black26,
        ),
        icon: Icon(icon, size: 18),
      ),
    );
  }
}

class _PreviewToggle extends StatelessWidget {
  const _PreviewToggle({
    required this.previewing,
    required this.busy,
    required this.onTap,
  });

  final bool previewing;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: previewing ? Colors.white : Colors.black.withValues(alpha: 0.42),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 1.8),
                )
              else
                Icon(
                  previewing ? LucideIcons.videoOff : LucideIcons.camera,
                  size: 16,
                  color: previewing ? const Color(0xFF11161D) : Colors.white,
                ),
              const SizedBox(width: 7),
              Text(
                previewing ? 'Kamerani o‘chirish' : 'Kamerani tekshirish',
                style: TextStyle(
                  color: previewing ? const Color(0xFF11161D) : Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreflightAction extends StatelessWidget {
  const _PreflightAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.enabled,
    required this.onTap,
    this.foreground = Colors.white,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color foreground;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          width: 98,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedOpacity(
                opacity: enabled ? 1 : 0.5,
                duration: const Duration(milliseconds: 160),
                child: Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.2),
                        blurRadius: 16,
                        offset: const Offset(0, 7),
                      ),
                    ],
                  ),
                  child: Icon(icon, color: foreground, size: 25),
                ),
              ),
              const SizedBox(height: 7),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
