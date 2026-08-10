import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../supabase/supabase_client.dart';
import '../../shared/services/connectivity_service.dart';

const _maxQueued = 500;
const _flushInterval = Duration(seconds: 20);
const _maxPerFlush = 50;

class AppAnalyticsService {
  AppAnalyticsService._();
  static final instance = AppAnalyticsService._();

  final _queue = Queue<Map<String, dynamic>>();
  Timer? _flushTimer;
  bool _flushing = false;

  void init() {
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(_flushInterval, (_) => _flush());
  }

  void track(String name, {Map<String, dynamic> properties = const {}}) {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    if (_queue.length >= _maxQueued) _queue.removeFirst();
    _queue.add({
      'user_id': userId,
      'event_name': name,
      'properties': properties,
      'platform': defaultTargetPlatform.name,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> _flush() async {
    if (_flushing || _queue.isEmpty) return;
    if (!ConnectivityService.instance.isOnlineNow) return;
    _flushing = true;
    try {
      final batch = <Map<String, dynamic>>[];
      final count = _queue.length.clamp(0, _maxPerFlush);
      for (var i = 0; i < count; i++) {
        if (_queue.isEmpty) break;
        batch.add(_queue.removeFirst());
      }
      if (batch.isNotEmpty) {
        await supabase.from('app_analytics_events').insert(batch);
      }
    } catch (e) {
      debugPrint('[Analytics] flush failed: $e');
    } finally {
      _flushing = false;
    }
  }

  Future<void> flush() => _flush();

  void dispose() {
    _flushTimer?.cancel();
  }
}

final appAnalytics = AppAnalyticsService.instance;
