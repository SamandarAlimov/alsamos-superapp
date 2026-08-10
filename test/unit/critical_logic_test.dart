import 'package:test/test.dart';

void main() {
  group('Message merge O(n+m) deduplication', () {
    test('removes exact duplicates by id', () {
      final current = [
        _TestMessage(id: 'msg1', createdAt: DateTime(2026, 1, 1, 10, 0)),
        _TestMessage(id: 'msg2', createdAt: DateTime(2026, 1, 1, 11, 0)),
      ];
      final incoming = [
        _TestMessage(id: 'msg2', createdAt: DateTime(2026, 1, 1, 11, 0)),
        _TestMessage(id: 'msg3', createdAt: DateTime(2026, 1, 1, 12, 0)),
      ];

      final merged = _mergeMessages(current, incoming);

      expect(merged.length, 3);
      expect(merged.map((m) => m.id), ['msg1', 'msg2', 'msg3']);
    });

    test('replaces tempId with real id (optimistic → server)', () {
      final optimistic =
          _TestMessage(id: 'temp-123', tempId: 'temp-123', status: 'sending');
      final serverMessage =
          _TestMessage(id: 'real-456', tempId: 'temp-123', status: 'sent');

      final current = [optimistic];
      final incoming = [serverMessage];

      final merged = _mergeMessages(current, incoming);

      expect(merged.length, 1, reason: 'Should replace, not duplicate');
      expect(merged.first.id, 'real-456',
          reason: 'Server message should win');
      expect(merged.first.status, 'sent');
    });

    test('replaces clientMessageId match', () {
      final local = _TestMessage(
        id: 'temp-999',
        clientMessageId: 'client-abc',
        status: 'sending',
      );
      final server = _TestMessage(
        id: 'real-111',
        clientMessageId: 'client-abc',
        status: 'delivered',
      );

      final merged = _mergeMessages([local], [server]);

      expect(merged.length, 1);
      expect(merged.first.id, 'real-111');
      expect(merged.first.status, 'delivered');
    });

    test('sorts by createdAt after merge', () {
      final current = [
        _TestMessage(id: 'msg3', createdAt: DateTime(2026, 1, 1, 12, 0)),
        _TestMessage(id: 'msg1', createdAt: DateTime(2026, 1, 1, 10, 0)),
      ];
      final incoming = [
        _TestMessage(id: 'msg2', createdAt: DateTime(2026, 1, 1, 11, 0)),
      ];

      final merged = _mergeMessages(current, incoming);

      expect(merged.map((m) => m.id), ['msg1', 'msg2', 'msg3']);
      expect(merged[0].createdAt.isBefore(merged[1].createdAt), true);
      expect(merged[1].createdAt.isBefore(merged[2].createdAt), true);
    });

    test('handles empty current list', () {
      final incoming = [
        _TestMessage(id: 'msg1', createdAt: DateTime(2026, 1, 1)),
      ];

      final merged = _mergeMessages([], incoming);

      expect(merged.length, 1);
      expect(merged.first.id, 'msg1');
    });

    test('handles empty incoming list', () {
      final current = [
        _TestMessage(id: 'msg1', createdAt: DateTime(2026, 1, 1)),
      ];

      final merged = _mergeMessages(current, []);

      expect(merged.length, 1);
      expect(merged.first.id, 'msg1');
    });

    test('handles both empty lists', () {
      final merged = _mergeMessages([], []);

      expect(merged.isEmpty, true);
    });

    test('preserves local message when server message arrives', () {
      final local = _TestMessage(
        id: 'temp-001',
        tempId: 'temp-001',
        status: 'sending',
        content: 'Hello',
      );
      final server = _TestMessage(
        id: 'real-001',
        tempId: 'temp-001',
        status: 'sent',
        content: 'Hello',
      );

      final merged = _mergeMessages([local], [server]);

      expect(merged.length, 1);
      expect(merged.first.id, 'real-001',
          reason: 'Server id wins when local → server transition');
    });

    test('deduplicates by metadata client_message_id', () {
      final msg1 = _TestMessage(
        id: 'temp-1',
        metadata: {'client_message_id': 'unique-client-123'},
      );
      final msg2 = _TestMessage(
        id: 'real-2',
        metadata: {'client_message_id': 'unique-client-123'},
      );

      final merged = _mergeMessages([msg1], [msg2]);

      expect(merged.length, 1);
      expect(merged.first.id, 'real-2');
    });
  });

  group('ICE candidate queue cap at 50', () {
    test('accepts candidates up to 50', () {
      final queue = <String>[];

      for (var i = 0; i < 50; i++) {
        _addCandidateIfUnderCap(queue, 'candidate-$i');
      }

      expect(queue.length, 50);
    });

    test('drops 51st candidate', () {
      final queue = <String>[];

      for (var i = 0; i < 51; i++) {
        _addCandidateIfUnderCap(queue, 'candidate-$i');
      }

      expect(queue.length, 50, reason: '51st item should be dropped');
      expect(queue.contains('candidate-50'), false,
          reason: 'Candidate 51 should not be added');
      expect(queue.last, 'candidate-49');
    });

    test('drops all candidates beyond 50', () {
      final queue = <String>[];

      for (var i = 0; i < 100; i++) {
        _addCandidateIfUnderCap(queue, 'candidate-$i');
      }

      expect(queue.length, 50);
    });
  });

  group('Wallet payment idempotency guard', () {
    test('allows first payment', () {
      final guard = _PaymentIdempotencyGuard();

      final allowed = guard.tryBeginPayment('order-123');

      expect(allowed, true);
    });

    test('blocks duplicate payment attempt', () {
      final guard = _PaymentIdempotencyGuard();

      guard.tryBeginPayment('order-123');
      final secondAttempt = guard.tryBeginPayment('order-123');

      expect(secondAttempt, false,
          reason: 'Second attempt should be blocked');
    });

    test('allows retry after completion', () {
      final guard = _PaymentIdempotencyGuard();

      guard.tryBeginPayment('order-123');
      guard.completePayment('order-123');
      final retry = guard.tryBeginPayment('order-123');

      expect(retry, true, reason: 'Should allow retry after completion');
    });

    test('tracks multiple concurrent payments', () {
      final guard = _PaymentIdempotencyGuard();

      final order1 = guard.tryBeginPayment('order-1');
      final order2 = guard.tryBeginPayment('order-2');
      final order1Dup = guard.tryBeginPayment('order-1');

      expect(order1, true);
      expect(order2, true);
      expect(order1Dup, false);
    });

    test('cleanup releases guard', () {
      final guard = _PaymentIdempotencyGuard();

      guard.tryBeginPayment('order-999');
      expect(guard.isInFlight('order-999'), true);

      guard.completePayment('order-999');
      expect(guard.isInFlight('order-999'), false);
    });
  });

  group('Payment amount validation', () {
    test('rejects zero amount', () {
      final result = _validatePaymentAmount(0);

      expect(result.isValid, false);
      expect(result.error, 'invalid_amount');
    });

    test('rejects negative amount', () {
      final result = _validatePaymentAmount(-1);

      expect(result.isValid, false);
      expect(result.error, 'invalid_amount');
    });

    test('rejects large negative amount', () {
      final result = _validatePaymentAmount(-1000000);

      expect(result.isValid, false);
    });

    test('accepts positive amount', () {
      final result = _validatePaymentAmount(100);

      expect(result.isValid, true);
      expect(result.error, null);
    });

    test('accepts minimum valid amount', () {
      final result = _validatePaymentAmount(1);

      expect(result.isValid, true);
    });

    test('accepts large valid amount', () {
      final result = _validatePaymentAmount(999999999);

      expect(result.isValid, true);
    });
  });

  group('Crash reporting deduplication', () {
    test('allows first crash report', () {
      final deduper = _CrashDeduper();

      final allowed = deduper.shouldRecord('Error: null check', 'line 42');

      expect(allowed, true);
    });

    test('blocks duplicate crash report', () {
      final deduper = _CrashDeduper();

      deduper.shouldRecord('Error: null check', 'line 42');
      final duplicate = deduper.shouldRecord('Error: null check', 'line 42');

      expect(duplicate, false, reason: 'Duplicate should be blocked');
    });

    test('allows different error messages', () {
      final deduper = _CrashDeduper();

      deduper.shouldRecord('Error: null check', 'line 42');
      final different = deduper.shouldRecord('Error: index out of range', 'line 42');

      expect(different, true);
    });

    test('allows same error with different stack', () {
      final deduper = _CrashDeduper();

      deduper.shouldRecord('Error: timeout', 'stack A');
      final differentStack = deduper.shouldRecord('Error: timeout', 'stack B');

      expect(differentStack, true,
          reason: 'Different stack traces should be logged');
    });

    test('clears seen set after limit', () {
      final deduper = _CrashDeduper(maxSeen: 3);

      deduper.shouldRecord('Error A', 'stack A');
      deduper.shouldRecord('Error B', 'stack B');
      deduper.shouldRecord('Error C', 'stack C');
      deduper.shouldRecord('Error D', 'stack D'); // Triggers clear

      // After clear, previous errors should be allowed again
      final retryA = deduper.shouldRecord('Error A', 'stack A');
      expect(retryA, true, reason: 'Should allow after set clear');
    });

    test('dedup key uses both error and stack', () {
      final deduper = _CrashDeduper();

      final report1 = deduper.shouldRecord('Error', 'stack1');
      final report2 = deduper.shouldRecord('Error', 'stack2');
      final report3 = deduper.shouldRecord('Error', 'stack1'); // duplicate

      expect(report1, true);
      expect(report2, true);
      expect(report3, false);
    });
  });
}

// ============================================================================
// TEST HELPERS - Message Merge Logic
// ============================================================================

class _TestMessage {
  final String id;
  final String? tempId;
  final String? clientMessageId;
  final DateTime createdAt;
  final String status;
  final String content;
  final Map<String, dynamic> metadata;

  _TestMessage({
    required this.id,
    this.tempId,
    this.clientMessageId,
    DateTime? createdAt,
    this.status = 'sent',
    this.content = '',
    this.metadata = const {},
  }) : createdAt = createdAt ?? DateTime(2026, 1, 1);

  bool get isLocal =>
      id.startsWith('temp-') ||
      tempId != null ||
      status == 'sending' ||
      status == 'failed';
}

List<_TestMessage> _mergeMessages(
    List<_TestMessage> current, List<_TestMessage> incoming) {
  final byId = <String, _TestMessage>{};
  final keyIndex = <String, String>{};

  void indexMessage(_TestMessage m) {
    final keys = _messageDedupKeys(m);
    for (final key in keys) {
      keyIndex[key] = m.id;
    }
    byId[m.id] = m;
  }

  for (final m in current) {
    indexMessage(m);
  }

  for (final message in incoming) {
    final incomingKeys = _messageDedupKeys(message);
    String? existingId;
    for (final key in incomingKeys) {
      final mapped = keyIndex[key];
      if (mapped != null && mapped != message.id) {
        existingId = mapped;
        break;
      }
    }

    if (existingId != null) {
      final existing = byId[existingId]!;
      // Keep server message, drop local optimistic
      if (message.isLocal && !existing.isLocal) continue;
      byId.remove(existingId);
      for (final key in _messageDedupKeys(existing)) {
        if (keyIndex[key] == existingId) keyIndex.remove(key);
      }
    }

    indexMessage(message);
  }

  final result = byId.values.toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  return result;
}

Iterable<String> _messageDedupKeys(_TestMessage message) sync* {
  yield message.id;
  if (message.tempId != null) yield message.tempId!;
  if (message.clientMessageId != null) yield message.clientMessageId!;
  final clientMsgId = message.metadata['client_message_id'];
  if (clientMsgId is String) yield clientMsgId;
}

// ============================================================================
// TEST HELPERS - ICE Candidate Queue Cap
// ============================================================================

void _addCandidateIfUnderCap(List<String> queue, String candidate) {
  if (queue.length < 50) {
    queue.add(candidate);
  }
}

// ============================================================================
// TEST HELPERS - Payment Idempotency Guard
// ============================================================================

class _PaymentIdempotencyGuard {
  final _inflightPayments = <String>{};

  bool tryBeginPayment(String orderId) {
    if (_inflightPayments.contains(orderId)) {
      return false;
    }
    _inflightPayments.add(orderId);
    return true;
  }

  void completePayment(String orderId) {
    _inflightPayments.remove(orderId);
  }

  bool isInFlight(String orderId) => _inflightPayments.contains(orderId);
}

// ============================================================================
// TEST HELPERS - Payment Amount Validation
// ============================================================================

class _PaymentValidationResult {
  final bool isValid;
  final String? error;

  _PaymentValidationResult({required this.isValid, this.error});
}

_PaymentValidationResult _validatePaymentAmount(int amountTiyin) {
  if (amountTiyin <= 0) {
    return _PaymentValidationResult(isValid: false, error: 'invalid_amount');
  }
  return _PaymentValidationResult(isValid: true);
}

// ============================================================================
// TEST HELPERS - Crash Report Deduplication
// ============================================================================

class _CrashDeduper {
  final _recentHashes = <String>{};
  final int maxSeen;

  _CrashDeduper({this.maxSeen = 500});

  bool shouldRecord(String errorStr, String stackStr) {
    final dedupKey = '${errorStr.hashCode}:${stackStr.hashCode}';
    if (_recentHashes.contains(dedupKey)) {
      return false;
    }
    if (_recentHashes.length >= maxSeen) {
      _recentHashes.clear();
    }
    _recentHashes.add(dedupKey);
    return true;
  }
}
