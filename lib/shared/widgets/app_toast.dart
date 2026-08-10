import 'dart:async';
import 'package:flutter/material.dart';

import 'error_mapper.dart';

enum ToastType { success, info, warning, error }

class AppToast {
  AppToast._();

  static final _activeEntries = <OverlayEntry>[];
  static const _maxVisible = 3;

  static void _show(
    BuildContext context,
    String message, {
    ToastType type = ToastType.info,
    Duration? duration,
    String? actionLabel,
    VoidCallback? action,
    Object? error,
  }) {
    if (error != null) {
      debugPrint('[AppToast] $message\n$error');
    }
    final displayMessage = _displayMessage(message, type: type, error: error);
    final d = duration ??
        (type == ToastType.error
            ? const Duration(seconds: 5)
            : const Duration(seconds: 3));
    final overlay = Overlay.of(context, rootOverlay: true);
    while (_activeEntries.length >= _maxVisible) {
      _activeEntries.removeAt(0).remove();
    }
    late OverlayEntry entry;
    final stackIndex = _activeEntries.length;
    entry = OverlayEntry(
      builder: (ctx) => _ToastWidget(
        message: displayMessage,
        type: type,
        duration: d,
        stackIndex: stackIndex,
        actionLabel: actionLabel,
        action: action,
        onDismiss: () {
          entry.remove();
          _activeEntries.remove(entry);
        },
      ),
    );
    _activeEntries.add(entry);
    overlay.insert(entry);
  }

  static String _displayMessage(
    String message, {
    required ToastType type,
    Object? error,
  }) {
    final value = message.trim();
    if (type != ToastType.error) {
      return value.isEmpty ? 'Tayyor' : value;
    }
    if (error != null) {
      return friendlyError(error, value.isEmpty ? 'Nimadir xato ketdi.' : value);
    }
    if (value.isEmpty || _looksTechnical(value)) {
      return 'Nimadir xato ketdi.';
    }
    return value;
  }

  static bool _looksTechnical(String value) {
    final lower = value.toLowerCase();
    return lower.contains('exception') ||
        lower.contains('stack trace') ||
        lower.contains('postgrest') ||
        lower.contains('storageexception') ||
        lower.contains('statuscode') ||
        lower.contains('null check operator') ||
        value.length > 120;
  }

  static void success(BuildContext context, String message,
          {Duration? duration}) =>
      _show(context, message, type: ToastType.success, duration: duration);

  static void info(BuildContext context, String message,
          {Duration? duration}) =>
      _show(context, message, type: ToastType.info, duration: duration);

  static void warning(BuildContext context, String message,
          {Duration? duration, Object? error}) =>
      _show(context, message,
          type: ToastType.warning, duration: duration, error: error);

  static void error(
    BuildContext context,
    String message, {
    Duration? duration,
    Object? error,
    String? actionLabel,
    VoidCallback? action,
  }) =>
      _show(context, message,
          type: ToastType.error,
          duration: duration,
          error: error,
          actionLabel: actionLabel,
          action: action);
}

class _ToastWidget extends StatefulWidget {
  final String message;
  final ToastType type;
  final Duration duration;
  final int stackIndex;
  final String? actionLabel;
  final VoidCallback? action;
  final VoidCallback onDismiss;
  const _ToastWidget({
    required this.message,
    required this.type,
    required this.duration,
    required this.stackIndex,
    this.actionLabel,
    this.action,
    required this.onDismiss,
  });

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;
  Timer? _timer;
  DateTime? _dismissAt;
  Duration _remaining = Duration.zero;
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    final reducedMotion = WidgetsBinding
        .instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    _slide = Tween<Offset>(
            begin: reducedMotion ? Offset.zero : const Offset(0, 0.35),
            end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fade = Tween<double>(begin: 0, end: 1).animate(_ctrl);
    if (reducedMotion) {
      _ctrl.value = 1;
    } else {
      _ctrl.forward();
    }
    _startTimer(widget.duration);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _dismiss() {
    if (_dismissing) return;
    _dismissing = true;
    _timer?.cancel();
    _ctrl.reverse().then((_) => widget.onDismiss());
  }

  void _startTimer(Duration duration) {
    _remaining = duration;
    _dismissAt = DateTime.now().add(duration);
    _timer?.cancel();
    _timer = Timer(duration, _dismiss);
  }

  void _pauseTimer() {
    final dismissAt = _dismissAt;
    if (dismissAt == null || _dismissing) return;
    _remaining = dismissAt.difference(DateTime.now());
    if (_remaining.isNegative) _remaining = Duration.zero;
    _timer?.cancel();
  }

  void _resumeTimer() {
    if (_dismissing) return;
    _startTimer(_remaining == Duration.zero
        ? const Duration(milliseconds: 600)
        : _remaining);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isDesktop = media.size.width >= 768;
    final maxW =
        isDesktop ? 420.0 : (media.size.width * 0.9).clamp(280.0, 420.0);
    final baseBottom = media.padding.bottom + (isDesktop ? 24.0 : 86.0);
    final bottomPad = baseBottom + widget.stackIndex * 74.0;
    final colorScheme = Theme.of(context).colorScheme;

    final (Color accent, IconData icon) = switch (widget.type) {
      ToastType.success => (const Color(0xFF22C55E), Icons.check_circle),
      ToastType.info => (const Color(0xFF3B82F6), Icons.info_outline),
      ToastType.warning => (
          const Color(0xFFF59E0B),
          Icons.warning_amber_rounded
        ),
      ToastType.error => (const Color(0xFFEF4444), Icons.error_outline),
    };

    return Stack(
      children: [
        Positioned(
          bottom: bottomPad,
          left: 0,
          right: 0,
          child: Align(
            child: FadeTransition(
              opacity: _fade,
              child: SlideTransition(
                position: _slide,
                child: MouseRegion(
                  onEnter: (_) => _pauseTimer(),
                  onExit: (_) => _resumeTimer(),
                  child: GestureDetector(
                    onTap: widget.actionLabel == null ? _dismiss : null,
                    onVerticalDragEnd: (details) {
                      final velocity = details.primaryVelocity ?? 0;
                      if (velocity.abs() > 120) _dismiss();
                    },
                    child: Container(
                      width: maxW,
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.3),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon, size: 20, color: accent),
                          const SizedBox(width: 8),
                          Container(
                            width: 3,
                            height: 28,
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              widget.message,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colorScheme.onSurface,
                                fontSize: 14,
                                height: 1.3,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          if (widget.actionLabel != null &&
                              widget.action != null) ...[
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: () {
                                widget.action?.call();
                                _dismiss();
                              },
                              style: TextButton.styleFrom(
                                foregroundColor: accent,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(widget.actionLabel!,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ] else ...[
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: _dismiss,
                              child: Icon(Icons.close,
                                  size: 16,
                                  color: colorScheme.onSurface
                                      .withValues(alpha: 0.5)),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
