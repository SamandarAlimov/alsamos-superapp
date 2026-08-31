// Mini app ochish oqimi — kontrakt bo'yicha (embed -> direct -> proxy -> external).
//
// Qoidalar `docs/contracts/mini-apps/open-strategy.md` da; hisoblash
// `domain/mini_app_open_strategy.dart` da (web bilan bir xil).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../data/mini_app_feed_item.dart';
import '../../domain/mini_app_open_strategy.dart';
import '../providers/mini_apps_feed_provider.dart';

class MiniAppWebViewPage extends ConsumerStatefulWidget {
  const MiniAppWebViewPage({super.key, required this.app});

  final MiniAppFeedItem app;

  @override
  ConsumerState<MiniAppWebViewPage> createState() => _MiniAppWebViewPageState();
}

class _MiniAppWebViewPageState extends ConsumerState<MiniAppWebViewPage> {
  late final MiniAppOpenPlan _plan;
  WebViewController? _controller;
  Timer? _timeoutTimer;
  int _stepIndex = 0;
  bool _loaded = false;
  bool _failed = false;
  DateTime _openedAt = DateTime.now();
  final String _sessionId = DateTime.now().microsecondsSinceEpoch.toString();

  @override
  void initState() {
    super.initState();
    final repository = ref.read(miniAppsFeedRepositoryProvider);
    _plan = buildMiniAppOpenPlan(
      url: widget.app.url,
      displayMode: widget.app.displayMode,
      appType: widget.app.appType,
      deepLink: widget.app.deepLink,
      apiBase: repository.apiBase,
    );
    _openedAt = DateTime.now();
    repository.trackEvent(widget.app.id, 'open', sessionId: _sessionId);
    WidgetsBinding.instance.addPostFrameCallback((_) => _runStep());
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    ref.read(miniAppsFeedRepositoryProvider).trackEvent(
          widget.app.id,
          'close',
          durationMs: DateTime.now().difference(_openedAt).inMilliseconds,
          sessionId: _sessionId,
        );
    super.dispose();
  }

  MiniAppOpenStep? get _step =>
      _stepIndex < _plan.steps.length ? _plan.steps[_stepIndex] : null;

  Future<void> _runStep() async {
    final step = _step;
    if (step == null) {
      _fail('unknown');
      return;
    }

    if (step.kind == MiniAppOpenStepKind.external ||
        step.kind == MiniAppOpenStepKind.native) {
      await _openExternal(step.src);
      if (mounted) Navigator.of(context).maybePop();
      return;
    }

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            _timeoutTimer?.cancel();
            if (mounted) setState(() => _loaded = true);
          },
          onWebResourceError: (_) => _nextStepOrFail('blocked'),
        ),
      )
      ..loadRequest(Uri.parse(step.src));

    setState(() {
      _controller = controller;
      _loaded = false;
      _failed = false;
    });

    _timeoutTimer?.cancel();
    if (step.timeout > Duration.zero) {
      _timeoutTimer = Timer(step.timeout, () {
        if (!_loaded) _nextStepOrFail('timeout');
      });
    }
  }

  void _nextStepOrFail(String errorCode) {
    if (_stepIndex + 1 < _plan.steps.length) {
      setState(() => _stepIndex += 1);
      _runStep();
    } else {
      _fail(errorCode);
    }
  }

  void _fail(String errorCode) {
    ref.read(miniAppsFeedRepositoryProvider).trackEvent(
          widget.app.id,
          'error',
          errorCode: errorCode,
          sessionId: _sessionId,
        );
    if (mounted) setState(() => _failed = true);
  }

  Future<void> _openExternal(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _reload() {
    setState(() {
      _stepIndex = 0;
      _failed = false;
      _loaded = false;
    });
    _runStep();
  }

  @override
  Widget build(BuildContext context) {
    final canonical = _plan.canonicalUrl;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(widget.app.name, style: const TextStyle(fontSize: 16)),
            if (canonical != null)
              Text(
                Uri.parse(canonical).host,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
              ),
          ],
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Qayta yuklash',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Shikoyat',
            onPressed: () async {
              await ref
                  .read(miniAppsFeedRepositoryProvider)
                  .report(widget.app.id, 'user_report');
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Shikoyat yuborildi')),
              );
            },
            icon: const Icon(Icons.flag_outlined),
          ),
          if (canonical != null)
            IconButton(
              tooltip: 'Brauzerda ochish',
              onPressed: () => _openExternal(canonical),
              icon: const Icon(Icons.open_in_new),
            ),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (_plan.punycodeWarning)
            Container(
              width: double.infinity,
              color: Colors.amber.withValues(alpha: 0.2),
              padding: const EdgeInsets.all(8),
              child: const Text(
                'Bu domen xalqaro belgilardan foydalanadi \u2014 manzilni tekshiring.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          Expanded(child: _buildBody(canonical)),
        ],
      ),
    );
  }

  Widget _buildBody(String? canonical) {
    if (_plan.error != null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Ilova manzili qabul qilinmadi.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_failed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.warning_amber_rounded, size: 40),
              const SizedBox(height: 12),
              const Text(
                'Bu ilova Alsamos ichida yuklanmadi. Sayt o\u2019zini boshqa ilova ichida '
                'ko\u2019rsatishga ruxsat bermayotgan bo\u2019lishi mumkin.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  OutlinedButton(onPressed: _reload, child: const Text('Qayta urinish')),
                  const SizedBox(width: 12),
                  if (canonical != null)
                    FilledButton(
                      onPressed: () => _openExternal(canonical),
                      child: const Text('Brauzerda ochish'),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    final controller = _controller;
    if (controller == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Stack(
      children: <Widget>[
        WebViewWidget(controller: controller),
        if (!_loaded) const Center(child: CircularProgressIndicator()),
      ],
    );
  }
}
