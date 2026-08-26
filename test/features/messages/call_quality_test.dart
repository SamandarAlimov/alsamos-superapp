import 'package:alsamos_flutter/features/messages/data/models/call_quality.dart';
import 'package:alsamos_flutter/shared/widgets/error_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('classifyCallQuality maps WebRTC stats to stable bars', () {
    expect(
      classifyCallQuality(rttMs: 60, jitterMs: 5, packetLoss: 0),
      CallNetworkQuality.excellent,
    );
    expect(
      classifyCallQuality(rttMs: 220, jitterMs: 20, packetLoss: 0.5),
      CallNetworkQuality.good,
    );
    expect(
      classifyCallQuality(rttMs: 420, jitterMs: 20, packetLoss: 1),
      CallNetworkQuality.fair,
    );
    expect(
      classifyCallQuality(rttMs: 100, jitterMs: 120, packetLoss: 1),
      CallNetworkQuality.poor,
    );
    expect(
      classifyCallQuality(
        rttMs: 0,
        jitterMs: 0,
        packetLoss: 0,
        connected: false,
      ),
      CallNetworkQuality.disconnected,
    );
  });

  test('friendlyCallError maps browser camera failures to actionable messages',
      () {
    expect(
      friendlyCallError(const CallFailure(CallFailureType.cameraPermission)),
      contains('ruxsat'),
    );
    expect(
      friendlyCallError(const CallFailure(CallFailureType.cameraNotFound)),
      contains('Kamera topilmadi'),
    );
    expect(
      friendlyCallError(const CallFailure(CallFailureType.cameraBusy)),
      contains('boshqa ilova yoki oynada band'),
    );
    expect(
      friendlyCallError(const CallFailure(CallFailureType.cameraConstraint)),
      contains('sozlamalarini'),
    );
  });
}
