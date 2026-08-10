import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../supabase/supabase_client.dart';
import '../../shared/services/connectivity_service.dart';

const _maxQueued = 200;
const _flushInterval = Duration(seconds: 30);
const _maxPerFlush = 25;

class CrashReportingService {
  final _queue = Queue<Map<String, dynamic>>();
  final _seen = <String>{};
  Timer? _flushTimer;
  bool _flushing = false;
  int _dropCount = 0;

  CrashReportingService() {
    _flushTimer = Timer.periodic(_flushInterval, (_) => _flush());
  }

  void record(Object error, StackTrace? stack, {String? context}) {
    final errorStr = error.toString();
    final dedupKey = '${errorStr.hashCode}:${stack.hashCode}';
    if (_seen.contains(dedupKey)) return;
    if (_seen.length > 500) _seen.clear();
    _seen.add(dedupKey);

    if (_queue.length >= _maxQueued) {
      _queue.removeFirst();
      _dropCount++;
    }
    _queue.add({
      'user_id': supabase.auth.currentUser?.id,
      'context': context ?? 'tile',
      'error': errorStr.length > 500 ? '${errorStr.substring(0, 500)}…' : errorStr,
      'stack': stack == null
          ? null
          : (stack.toString().length > 2000
              ? '${stack.toString().substring(0, 2000)}…'
              : stack.toString()),
      'platform': defaultTargetPlatform.name,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
    if (_queue.length >= _maxPerFlush) {
      unawaited(_flush());
    }
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
      if (batch.isEmpty) return;
      if (_dropCount > 0) {
        batch.last['_meta_dropped'] = _dropCount;
        _dropCount = 0;
      }
      await supabase.from('crash_logs').insert(batch);
    } catch (e) {
      debugPrint('[CrashReporting] flush failed: $e');
    } finally {
      _flushing = false;
    }
  }

  void dispose() {
    _flushTimer?.cancel();
  }
}

final crashReporting = CrashReportingService();
