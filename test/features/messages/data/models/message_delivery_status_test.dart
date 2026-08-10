import 'package:alsamos_flutter/features/messages/data/models/message_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('delivery status never regresses below read', () {
    final readAt = DateTime(2026);
    expect(
      resolveMessageDeliveryStatus(
        current: 'read',
        hasDeliveryReceipt: false,
        readAt: readAt,
      ),
      'read',
    );
  });

  test('server ack stays sent until recipient delivery receipt arrives', () {
    expect(
      resolveMessageDeliveryStatus(
        current: 'sent',
        hasDeliveryReceipt: false,
        readAt: null,
      ),
      'sent',
    );
    expect(
      resolveMessageDeliveryStatus(
        current: 'sent',
        hasDeliveryReceipt: true,
        readAt: null,
      ),
      'delivered',
    );
  });
}
