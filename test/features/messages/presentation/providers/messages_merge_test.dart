import 'package:alsamos_flutter/features/messages/data/models/message_model.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Tests for the O(n+m) message merge/dedup algorithm used by MessagesNotifier.
//
// Since _mergeMessages is private, we replicate the exact algorithm here as a
// standalone function. This is intentional: we test the LOGIC in isolation
// without needing to instantiate the full provider + Supabase + realtime stack.
// ---------------------------------------------------------------------------

/// Exact reproduction of MessagesNotifier._mergeMessages from
/// lib/features/messages/presentation/providers/messages_provider.dart
List<Message> mergeMessages(List<Message> current, List<Message> incoming) {
  final byId = <String, Message>{};
  final keyIndex = <String, String>{};

  void indexMessage(Message m) {
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
      if (_isLocalMessage(message) && !_isLocalMessage(existing)) continue;
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

Iterable<String> _messageDedupKeys(Message message) sync* {
  yield message.id;
  if (message.tempId != null) yield message.tempId!;
  if (message.clientMessageId != null) yield message.clientMessageId!;
  final clientMsgId = message.metadata['client_message_id'];
  if (clientMsgId is String) yield clientMsgId;
}

bool _isLocalMessage(Message message) =>
    message.id.startsWith('temp-') ||
    message.tempId != null ||
    message.status == 'sending' ||
    message.status == 'failed';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

Message _msg(
  String id, {
  DateTime? createdAt,
  String? tempId,
  String? clientMessageId,
  Map<String, dynamic> metadata = const {},
  String status = 'sent',
  String conversationId = 'conv-1',
}) =>
    Message(
      id: id,
      conversationId: conversationId,
      createdAt: createdAt ?? DateTime(2026, 1, 1, 0, 0, 0),
      tempId: tempId,
      clientMessageId: clientMessageId,
      metadata: metadata,
      status: status,
    );

void main() {
  group('Message merge algorithm', () {
    test('merges non-overlapping message lists in chronological order', () {
      final current = [
        _msg('a', createdAt: DateTime(2026, 1, 1, 10, 0)),
        _msg('b', createdAt: DateTime(2026, 1, 1, 10, 1)),
      ];
      final incoming = [
        _msg('c', createdAt: DateTime(2026, 1, 1, 10, 2)),
        _msg('d', createdAt: DateTime(2026, 1, 1, 10, 3)),
      ];

      final result = mergeMessages(current, incoming);

      expect(result.length, 4);
      expect(result.map((m) => m.id).toList(), ['a', 'b', 'c', 'd']);
    });

    test('deduplicates by exact ID match', () {
      final current = [
        _msg('msg-1', createdAt: DateTime(2026, 1, 1, 10, 0)),
        _msg('msg-2', createdAt: DateTime(2026, 1, 1, 10, 1)),
      ];
      final incoming = [
        _msg('msg-2', createdAt: DateTime(2026, 1, 1, 10, 1)),
        _msg('msg-3', createdAt: DateTime(2026, 1, 1, 10, 2)),
      ];

      final result = mergeMessages(current, incoming);

      expect(result.length, 3);
      expect(result.map((m) => m.id).toList(), ['msg-1', 'msg-2', 'msg-3']);
    });

    test('replaces temp message with server message via tempId linkage', () {
      final current = [
        _msg('temp-12345',
            createdAt: DateTime(2026, 1, 1, 10, 0),
            tempId: 'temp-12345',
            status: 'sending'),
      ];
      // Server returns real ID but carries the tempId so we can match
      final incoming = [
        _msg('real-uuid-1',
            createdAt: DateTime(2026, 1, 1, 10, 0),
            tempId: 'temp-12345',
            status: 'sent'),
      ];

      final result = mergeMessages(current, incoming);

      expect(result.length, 1);
      expect(result.first.id, 'real-uuid-1');
      expect(result.first.status, 'sent');
    });

    test('replaces temp message via clientMessageId linkage', () {
      final current = [
        _msg('temp-99',
            createdAt: DateTime(2026, 1, 1, 10, 0),
            clientMessageId: 'temp-99',
            status: 'sending'),
      ];
      final incoming = [
        _msg('server-id-42',
            createdAt: DateTime(2026, 1, 1, 10, 0),
            clientMessageId: 'temp-99',
            status: 'sent'),
      ];

      final result = mergeMessages(current, incoming);

      expect(result.length, 1);
      expect(result.first.id, 'server-id-42');
    });

    test('replaces temp message via metadata client_message_id', () {
      final current = [
        _msg('temp-77',
            createdAt: DateTime(2026, 1, 1, 10, 0),
            clientMessageId: 'temp-77',
            status: 'sending'),
      ];
      final incoming = [
        _msg('server-id-77',
            createdAt: DateTime(2026, 1, 1, 10, 0),
            metadata: {'client_message_id': 'temp-77'},
            status: 'sent'),
      ];

      final result = mergeMessages(current, incoming);

      expect(result.length, 1);
      expect(result.first.id, 'server-id-77');
    });

    test('does NOT replace server message with local message', () {
      // If incoming is local (temp-*) but existing is already a real server msg,
      // the local message should be discarded (continue in the algorithm).
      final current = [
        _msg('server-id-1',
            createdAt: DateTime(2026, 1, 1, 10, 0),
            clientMessageId: 'temp-abc',
            status: 'sent'),
      ];
      final incoming = [
        _msg('temp-abc',
            createdAt: DateTime(2026, 1, 1, 10, 0),
            tempId: 'temp-abc',
            status: 'sending'),
      ];

      final result = mergeMessages(current, incoming);

      expect(result.length, 1);
      expect(result.first.id, 'server-id-1');
    });

    test('handles empty current list', () {
      final incoming = [
        _msg('a', createdAt: DateTime(2026, 1, 1, 10, 0)),
        _msg('b', createdAt: DateTime(2026, 1, 1, 10, 1)),
      ];

      final result = mergeMessages([], incoming);

      expect(result.length, 2);
      expect(result.map((m) => m.id).toList(), ['a', 'b']);
    });

    test('handles empty incoming list', () {
      final current = [
        _msg('a', createdAt: DateTime(2026, 1, 1, 10, 0)),
      ];

      final result = mergeMessages(current, []);

      expect(result.length, 1);
      expect(result.first.id, 'a');
    });

    test('handles both lists empty', () {
      final result = mergeMessages([], []);
      expect(result, isEmpty);
    });

    test('result is sorted by createdAt', () {
      final current = [
        _msg('c', createdAt: DateTime(2026, 1, 1, 10, 5)),
        _msg('a', createdAt: DateTime(2026, 1, 1, 10, 0)),
      ];
      final incoming = [
        _msg('b', createdAt: DateTime(2026, 1, 1, 10, 2)),
      ];

      final result = mergeMessages(current, incoming);

      expect(result.map((m) => m.id).toList(), ['a', 'b', 'c']);
    });

    test('large merge with many overlapping IDs performs correctly', () {
      final current = List.generate(
        100,
        (i) => _msg('msg-$i',
            createdAt: DateTime(2026, 1, 1, 0, i), status: 'sent'),
      );
      // Incoming has 50 overlapping + 50 new
      final incoming = List.generate(
        100,
        (i) => _msg('msg-${i + 50}',
            createdAt: DateTime(2026, 1, 1, 0, i + 50), status: 'sent'),
      );

      final result = mergeMessages(current, incoming);

      // Should have 150 unique messages (0-149)
      expect(result.length, 150);
      // Should be in chronological order
      for (var i = 1; i < result.length; i++) {
        expect(
          result[i].createdAt.isAtSameMomentAs(result[i - 1].createdAt) ||
              result[i].createdAt.isAfter(result[i - 1].createdAt),
          isTrue,
          reason: 'Messages must be sorted chronologically',
        );
      }
    });

    test('multiple temp messages replaced in single merge', () {
      final current = [
        _msg('temp-1',
            createdAt: DateTime(2026, 1, 1, 10, 0),
            tempId: 'temp-1',
            status: 'sending'),
        _msg('temp-2',
            createdAt: DateTime(2026, 1, 1, 10, 1),
            tempId: 'temp-2',
            status: 'sending'),
        _msg('real-existing',
            createdAt: DateTime(2026, 1, 1, 10, 2), status: 'sent'),
      ];
      final incoming = [
        _msg('server-1',
            createdAt: DateTime(2026, 1, 1, 10, 0),
            tempId: 'temp-1',
            status: 'sent'),
        _msg('server-2',
            createdAt: DateTime(2026, 1, 1, 10, 1),
            tempId: 'temp-2',
            status: 'sent'),
      ];

      final result = mergeMessages(current, incoming);

      expect(result.length, 3);
      final ids = result.map((m) => m.id).toSet();
      expect(ids.contains('server-1'), isTrue);
      expect(ids.contains('server-2'), isTrue);
      expect(ids.contains('real-existing'), isTrue);
      expect(ids.contains('temp-1'), isFalse);
      expect(ids.contains('temp-2'), isFalse);
    });
  });
}
