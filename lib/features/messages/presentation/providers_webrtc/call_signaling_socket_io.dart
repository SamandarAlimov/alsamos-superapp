import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

  WebSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  bool _connected = false;

  bool get isConnected => _connected;

  Future<void> connect() async {
    final socket = await WebSocket.connect(uri.toString(), headers: headers)
        .timeout(const Duration(seconds: 8));
    _socket = socket;
    _connected = true;
    _subscription = socket.listen(
      (event) {
        try {
          final text = event is String
              ? event
              : event is List<int>
                  ? utf8.decode(event)
                  : event.toString();
          final decoded = jsonDecode(text);
          if (decoded is Map) {
            onMessage(Map<String, dynamic>.from(decoded));
          }
        } catch (error) {
          onError?.call(error);
        }
      },
      onError: (Object error) {
        _connected = false;
        onError?.call(error);
      },
      onDone: () {
        _connected = false;
        onDone?.call();
      },
    );
  }

  void send(Map<String, dynamic> data) {
    if (!_connected) return;
    _socket?.add(jsonEncode(data));
  }

  Future<void> close() async {
    _connected = false;
    await _subscription?.cancel();
    _subscription = null;
    await _socket?.close(WebSocketStatus.normalClosure);
    _socket = null;
  }
}
