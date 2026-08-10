enum CallNetworkQuality { excellent, good, fair, poor, disconnected }

class CallQualitySnapshot {
  const CallQualitySnapshot({
    required this.quality,
    this.rttMs = 0,
    this.jitterMs = 0,
    this.packetLoss = 0,
    this.selectedCandidateType,
    this.audioBytesSent = 0,
    this.audioBytesReceived = 0,
    this.videoBytesSent = 0,
    this.videoBytesReceived = 0,
  });

  final CallNetworkQuality quality;
  final int rttMs;
  final int jitterMs;
  final double packetLoss;
  final String? selectedCandidateType;
  final int audioBytesSent;
  final int audioBytesReceived;
  final int videoBytesSent;
  final int videoBytesReceived;
}

CallNetworkQuality classifyCallQuality({
  required int rttMs,
  required int jitterMs,
  required double packetLoss,
  bool connected = true,
}) {
  if (!connected) return CallNetworkQuality.disconnected;
  if (packetLoss >= 8 || rttMs >= 700 || jitterMs >= 90) {
    return CallNetworkQuality.poor;
  }
  if (packetLoss >= 3 || rttMs >= 350 || jitterMs >= 45) {
    return CallNetworkQuality.fair;
  }
  if (packetLoss >= 1 || rttMs >= 180 || jitterMs >= 25) {
    return CallNetworkQuality.good;
  }
  return CallNetworkQuality.excellent;
}
