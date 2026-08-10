import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// We test the CrashReportingService queue logic in isolation by extracting the
// pure algorithms (dedup + queue eviction) without needing Supabase or timers.
// This mirrors the production code in crash_reporting_service.dart.
// ---------------------------------------------------------------------------

const _maxQueued = 200;

/// Minimal reproduction of the queue + dedup logic from CrashReportingService.
class _CrashQueue {
  final queue = Queue<Map<String, dynamic>>();
  final seen = <String>{};
  bool flushing = false;
  int dropCount = 0;

  /// Returns true if the error was enqueued, false if deduplicated.
  bool record(Object error, StackTrace? stack, {String? context}) {
    final errorStr = error.toString();
    final dedupKey = '${errorStr.hashCode}:${stack.hashCode}';
    if (seen.contains(dedupKey)) return false;
    if (seen.length > 500) seen.clear();
    seen.add(dedupKey);

    if (queue.length >= _maxQueued) {
      queue.removeFirst();
      dropCount++;
    }
    queue.add({
      'context': context ?? 'tile',
      'error': errorStr.length > 500
          ? '${errorStr.substring(0, 500)}...'
          : errorStr,
      'stack': stack?.toString(),
    });
    return true;
  }

  /// Simulates flush behavior to test the _flushing guard.
  Future<void> flush({bool shouldThrow = false}) async {
    if (flushing || queue.isEmpty) return;
    flushing = true;
    try {
      final count = queue.length.clamp(0, 25);
      for (var i = 0; i < count; i++) {
        if (queue.isEmpty) break;
        queue.removeFirst();
      }
      if (shouldThrow) throw Exception('network error');
    } finally {
      flushing = false;
    }
  }
}

void main() {
  group('CrashReportingService queue logic', () {
    late _CrashQueue sut;

    setUp(() {
      sut = _CrashQueue();
    });

    test('record() deduplicates identical errors', () {
      final stack = StackTrace.current;
      final error = Exception('something broke');

      final first = sut.record(error, stack);
      final second = sut.record(error, stack);
      final third = sut.record(error, stack);

      expect(first, isTrue);
      expect(second, isFalse);
      expect(third, isFalse);
      expect(sut.queue.length, 1);
    });

    test('record() allows different errors through', () {
      sut.record(Exception('error A'), StackTrace.current);
      sut.record(Exception('error B'), StackTrace.current);
      sut.record(Exception('error C'), StackTrace.current);

      expect(sut.queue.length, 3);
    });

    test('record() allows same error with different stack traces', () {
      final error = Exception('same error');
      // Different stack traces produce different dedup keys
      sut.record(error, StackTrace.fromString('frame1'));
      sut.record(error, StackTrace.fromString('frame2'));

      expect(sut.queue.length, 2);
    });

    test('queue respects max size (200) with FIFO eviction', () {
      // Fill the queue to max capacity
      for (var i = 0; i < _maxQueued; i++) {
        sut.record('error-$i', StackTrace.fromString('stack-$i'));
      }
      expect(sut.queue.length, _maxQueued);
      expect(sut.dropCount, 0);

      // One more should evict the oldest
      sut.record('overflow-error', StackTrace.fromString('overflow-stack'));
      expect(sut.queue.length, _maxQueued);
      expect(sut.dropCount, 1);

      // The oldest entry (error-0) should be gone, newest should be present
      final errors = sut.queue.map((e) => e['error'] as String).toList();
      expect(errors.first, 'error-1');
      expect(errors.last, 'overflow-error');
    });

    test('queue evicts multiple entries under sustained overflow', () {
      for (var i = 0; i < _maxQueued + 10; i++) {
        sut.record('error-$i', StackTrace.fromString('stack-$i'));
      }
      expect(sut.queue.length, _maxQueued);
      expect(sut.dropCount, 10);

      final errors = sut.queue.map((e) => e['error'] as String).toList();
      expect(errors.first, 'error-10');
      expect(errors.last, 'error-${_maxQueued + 9}');
    });

    test('_flushing flag is properly reset after successful flush', () async {
      sut.record('error-1', StackTrace.fromString('stack'));
      expect(sut.flushing, isFalse);

      await sut.flush();

      expect(sut.flushing, isFalse);
      expect(sut.queue, isEmpty);
    });

    test('_flushing flag is properly reset after failed flush', () async {
      sut.record('error-1', StackTrace.fromString('stack'));
      expect(sut.flushing, isFalse);

      await sut.flush(shouldThrow: true);

      // The bug fix: _flushing must be reset even when flush throws
      expect(sut.flushing, isFalse);
    });

    test('concurrent flush calls are blocked by _flushing guard', () async {
      for (var i = 0; i < 10; i++) {
        sut.record('error-$i', StackTrace.fromString('stack-$i'));
      }

      // Manually set flushing to simulate an in-progress flush
      sut.flushing = true;
      final queueBefore = sut.queue.length;

      await sut.flush(); // Should be a no-op because flushing is true

      expect(sut.queue.length, queueBefore);
    });

    test('seen set clears after 500 entries to prevent unbounded growth', () {
      // Fill seen set past the threshold
      for (var i = 0; i < 501; i++) {
        sut.seen.add('key-$i');
      }

      // Next record call should trigger the clear (seen.length > 500)
      final result = sut.record('new-error', StackTrace.fromString('stack'));
      expect(result, isTrue);
      // After clear, seen only has the new entry
      expect(sut.seen.length, 1);
    });
  });
}
