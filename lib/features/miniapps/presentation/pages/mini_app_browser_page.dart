import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/constants/api_constants.dart';
import '../../data/mini_app_model.dart';

enum _LoadMode { direct, embed, proxy }

/// Pixel-perfect Flutter port of the web fullscreen in-app browser.
/// Mirrors `MiniAppsPage.tsx` openedApp + iframe load-mode pipeline:
/// direct → embed (YouTube/Instagram/Telegram) → proxy via mini-app-proxy.
class MiniAppBrowserPage extends StatefulWidget {
  const MiniAppBrowserPage({super.key, required this.app});
  final MiniApp app;

  @override
  State<MiniAppBrowserPage> createState() => _MiniAppBrowserPageState();
}

class _MiniAppBrowserPageState extends State<MiniAppBrowserPage> {
  late final WebViewController _controller;
  _LoadMode _mode = _LoadMode.direct;
  bool _loaded = false;
  bool _error = false;
  Timer? _timeout;
  String _currentSrc = '';

  String get _normalizedUrl => widget.app.normalizedUrl;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() {
            _loaded = false;
          }),
          onPageFinished: (_) {
            _timeout?.cancel();
            setState(() {
              _loaded = true;
              _error = false;
            });
          },
          onWebResourceError: (e) {
            // Only treat top-level/main-frame errors as failures.
            if (e.isForMainFrame == false) return;
            _handleLoadFailure();
          },
        ),
      );
    _resolveAndLoad();
  }

  @override
  void dispose() {
    _timeout?.cancel();
    super.dispose();
  }

  // ------------------------- URL resolution -------------------------

  /// Mirrors web `getEmbedUrl(url)`.
  String? _getEmbedUrl(String url) {
    try {
      final u = Uri.parse(url);
      final host = u.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');

      // YouTube
      if (host == 'youtube.com' || host == 'm.youtube.com') {
        final v = u.queryParameters['v'];
        if (v != null && v.isNotEmpty) {
          return 'https://www.youtube.com/embed/$v?autoplay=0';
        }
        if (u.path.startsWith('/shorts/')) {
          final id = u.path.split('/shorts/').last.split(RegExp(r'[?#]')).first;
          if (id.isNotEmpty) return 'https://www.youtube.com/embed/$id';
        }
        return 'https://www.youtube.com/embed?listType=search&list=';
      }
      if (host == 'youtu.be') {
        final id = u.path.replaceFirst('/', '').split(RegExp(r'[?#]')).first;
        if (id.isNotEmpty) {
          return 'https://www.youtube.com/embed/$id?autoplay=0';
        }
      }

      // Instagram
      if (host == 'instagram.com' || host == 'm.instagram.com') {
        if (RegExp(r'^/(p|reel|tv)/').hasMatch(u.path)) {
          return 'https://www.instagram.com${u.path}embed/';
        }
      }

      // Telegram
      if (host == 't.me' || host == 'telegram.me') {
        final path = u.path.replaceFirst('/', '');
        if (path.isNotEmpty && !path.contains('/')) {
          return 'https://t.me/s/$path';
        }
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  String _proxyUrlFor(String url) {
    final base = ApiConstants.supabaseUrl.replaceFirst(RegExp(r'^http://'), 'https://');
    final ts = DateTime.now().millisecondsSinceEpoch;
    return '$base/functions/v1/mini-app-proxy?url=${Uri.encodeComponent(url)}&_ts=$ts';
  }

  void _resolveAndLoad() {
    final url = _normalizedUrl;
    final embed = _getEmbedUrl(url);

    String src;
    if (_mode == _LoadMode.direct) {
      if (embed != null) {
        _mode = _LoadMode.embed;
        src = embed;
      } else {
        src = url;
      }
    } else if (_mode == _LoadMode.embed) {
      src = embed ?? url;
    } else {
      src = _proxyUrlFor(url);
    }

    _currentSrc = src;
    setState(() {
      _loaded = false;
      _error = false;
    });
    _controller.loadRequest(Uri.parse(src));
    _armTimeout();
  }

  void _armTimeout() {
    _timeout?.cancel();
    final ms = _mode == _LoadMode.proxy ? 15000 : 8000;
    _timeout = Timer(Duration(milliseconds: ms), () {
      if (_loaded || _error) return;
      _handleLoadFailure();
    });
  }

  void _handleLoadFailure() {
    if (_mode == _LoadMode.direct || _mode == _LoadMode.embed) {
      setState(() {
        _mode = _LoadMode.proxy;
      });
      _resolveAndLoad();
    } else {
      _timeout?.cancel();
      setState(() {
        _error = true;
        _loaded = false;
      });
    }
  }

  void _reload() {
    HapticFeedback.selectionClick();
    _timeout?.cancel();
    setState(() {
      _loaded = false;
      _error = false;
    });
    if (_currentSrc.isNotEmpty) {
      _controller.loadRequest(Uri.parse(_currentSrc));
      _armTimeout();
    } else {
      _resolveAndLoad();
    }
  }

  void _retry() {
    HapticFeedback.lightImpact();
    if (_mode != _LoadMode.proxy) {
      setState(() => _mode = _LoadMode.proxy);
    }
    _resolveAndLoad();
  }

  Future<void> _openExternal() async {
    HapticFeedback.lightImpact();
    final uri = Uri.parse(_normalizedUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ------------------------------ build ------------------------------

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              app: widget.app,
              c: c,
              primary: primary,
              isProxy: _mode == _LoadMode.proxy,
              onClose: () => Navigator.pop(context),
              onReload: _reload,
              onOpenExternal: _openExternal,
            ),
            Expanded(
              child: Stack(
                children: [
                  if (!_error) WebViewWidget(controller: _controller),
                  if (!_loaded && !_error)
                    _LoadingOverlay(
                      c: c,
                      primary: primary,
                      isProxy: _mode == _LoadMode.proxy,
                    ),
                  if (_error)
                    _ErrorState(
                      c: c,
                      primary: primary,
                      onRetry: _retry,
                      onOpenExternal: _openExternal,
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

// ============================== HEADER ==============================

class _Header extends StatelessWidget {
  const _Header({
    required this.app,
    required this.c,
    required this.primary,
    required this.isProxy,
    required this.onClose,
    required this.onReload,
    required this.onOpenExternal,
  });
  final MiniApp app;
  final AlsamosColors c;
  final Color primary;
  final bool isProxy;
  final VoidCallback onClose;
  final VoidCallback onReload;
  final VoidCallback onOpenExternal;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: c.card.withValues(alpha: 0.8),
        border: Border(
          bottom: BorderSide(color: c.border.withValues(alpha: 0.5)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          _RoundIconButton(
            icon: LucideIcons.x,
            onTap: onClose,
            c: c,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: c.muted.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: app.iconUrl != null && app.iconUrl!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: app.iconUrl!,
                            width: 20,
                            height: 20,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Icon(
                              LucideIcons.globe,
                              size: 14,
                              color: primary,
                            ),
                          )
                        : Icon(LucideIcons.globe,
                            size: 14, color: primary),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    app.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: c.foreground,
                    ),
                  ),
                ),
                if (isProxy)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: c.muted.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'proksi',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: c.mutedForeground,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          _RoundIconButton(
            icon: LucideIcons.rotateCcw,
            onTap: onReload,
            c: c,
            tooltip: 'Qayta yuklash',
          ),
          const SizedBox(width: 4),
          _RoundIconButton(
            icon: LucideIcons.externalLink,
            onTap: onOpenExternal,
            c: c,
            tooltip: 'Brauzerda ochish',
          ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.onTap,
    required this.c,
    this.tooltip,
  });
  final IconData icon;
  final VoidCallback onTap;
  final AlsamosColors c;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final btn = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          child: Icon(icon, size: 16, color: c.foreground),
        ),
      ),
    );
    if (tooltip == null) return btn;
    return Tooltip(message: tooltip!, child: btn);
  }
}

// ============================== LOADING ==============================

class _LoadingOverlay extends StatelessWidget {
  const _LoadingOverlay({
    required this.c,
    required this.primary,
    required this.isProxy,
  });
  final AlsamosColors c;
  final Color primary;
  final bool isProxy;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: c.background,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(primary),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                isProxy
                    ? 'Proksi orqali yuklanmoqda...'
                    : 'Yuklanmoqda...',
                style: TextStyle(
                    fontSize: 13, color: c.mutedForeground),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================== ERROR ==============================

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.c,
    required this.primary,
    required this.onRetry,
    required this.onOpenExternal,
  });
  final AlsamosColors c;
  final Color primary;
  final VoidCallback onRetry;
  final VoidCallback onOpenExternal;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: c.background,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.globe,
                    size: 48,
                    color: c.mutedForeground.withValues(alpha: 0.4)),
                const SizedBox(height: 12),
                Text(
                  'Yuklanmadi',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: c.foreground,
                  ),
                ),
                const SizedBox(height: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Text(
                    "Bu sayt ichki ko'rinishda yuklanishi mumkin emas. Brauzerda ochib ko'ring.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13, color: c.mutedForeground),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(LucideIcons.rotateCcw, size: 14),
                      label: const Text('Qayta urinish'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: c.foreground,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        side: BorderSide(
                            color: c.border.withValues(alpha: 0.6)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: onOpenExternal,
                      icon: const Icon(LucideIcons.externalLink, size: 14),
                      label: const Text('Brauzerda ochish'),
                      style: FilledButton.styleFrom(
                        backgroundColor: primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
