import 'package:flutter/widgets.dart';

import '../supabase/supabase_client.dart';

class AppLifecycleService {
  static final AppLifecycleService instance = AppLifecycleService._();
  AppLifecycleService._();

  AppLifecycleState _lastState = AppLifecycleState.resumed;
  AppLifecycleState get lastState => _lastState;
  bool get isInForeground =>
      _lastState == AppLifecycleState.resumed;

  void init() {
    final binding = WidgetsBinding.instance;
    binding.addObserver(_Observer(this));
  }

  void _onStateChange(AppLifecycleState state) {
    final previous = _lastState;
    _lastState = state;

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _onBackground();
    } else if (state == AppLifecycleState.resumed &&
        (previous == AppLifecycleState.paused ||
            previous == AppLifecycleState.inactive)) {
      _onForeground();
    }
  }

  void _onBackground() {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    try {
      supabase.from('profiles').update({
        'is_online': false,
        'last_seen': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', uid).then((_) {}, onError: (_) {});
    } catch (_) {}
  }

  void _onForeground() {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    try {
      supabase.from('profiles').update({
        'is_online': true,
        'last_seen': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', uid).then((_) {}, onError: (_) {});
    } catch (_) {}
  }
}

class _Observer extends WidgetsBindingObserver {
  final AppLifecycleService _service;
  _Observer(this._service);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _service._onStateChange(state);
  }
}

final appLifecycle = AppLifecycleService.instance;
