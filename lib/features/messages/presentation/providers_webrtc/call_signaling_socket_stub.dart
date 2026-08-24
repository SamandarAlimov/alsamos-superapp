typedef CallSignalingMessageHandler = void Function(Map<String, dynamic> data);

class CallSignalingSocket {
  CallSignalingSocket({
    required this.uri,
    required this.onMessage,
    this.headers = const {},
    this.onError,
    this.onDone,
  });

  final Uri uri;
  final Map<String, dynamic> headers;
  final CallSignalingMessageHandler onMessage;
  final void Function(Object error)? onError;
  final void Function()? onDone;

  bool get isConnected => false;

  Future<void> connect() async {}

  void send(Map<String, dynamic> data) {}

  Future<void> close() async {}
}
