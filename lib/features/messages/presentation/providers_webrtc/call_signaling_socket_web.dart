// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

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

  html.WebSocket? _socket;
  StreamSubscription<html.MessageEvent>? _messageSubscription;
  StreamSubscription<html.Event>? _openSubscription;
  StreamSubscription<html.Event>? _errorSubscription;
  StreamSubscription<html.CloseEvent>? _closeSubscription;
  bool _connected = false;

  bool get isConnected => _connected;

  Future<void> connect() async {
    final completer = Completer<void>();
    final socket = html.WebSocket(uri.toString());
    _socket = socket;

    _openSubscription = socket.onOpen.listen((_) {
      _connected = true;
      if (!completer.isCompleted) completer.complete();
    });

    _messageSubscription = socket.onMessage.listen((event) {
      try {
        final data = event.data;
        final text = data is String ? data : data.toString();
        final decoded = jsonDecode(text);
        if (decoded is Map) {
          onMessage(Map<String, dynamic>.from(decoded));
        }
      } catch (error) {
        onError?.call(error);
      }
    });

    _errorSubscription = socket.onError.listen((event) {
      _connected = false;
      final error = StateError('WebSocket error: ${event.type}');
      onError?.call(error);
      if (!completer.isCompleted) completer.completeError(error);
    });

    _closeSubscription = socket.onClose.listen((_) {
      _connected = false;
      onDone?.call();
    });

    return completer.future.timeout(const Duration(seconds: 8));
  }

  void send(Map<String, dynamic> data) {
    if (!_connected) return;
    _socket?.send(jsonEncode(data));
  }

  Future<void> close() async {
    _connected = false;
    await _messageSubscription?.cancel();
    await _openSubscription?.cancel();
    await _errorSubscription?.cancel();
    await _closeSubscription?.cancel();
    _messageSubscription = null;
    _openSubscription = null;
    _errorSubscription = null;
    _closeSubscription = null;
    _socket?.close();
    _socket = null;
  }
}
