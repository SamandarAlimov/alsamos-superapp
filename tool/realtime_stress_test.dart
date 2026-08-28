import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:supabase/supabase.dart';

const _defaultUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://mbhjganbihamoiqmankv.supabase.co',
);
const _defaultAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue:
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1iaGpnYW5iaWhhbW9pcW1hbmt2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjU0NjkwNDcsImV4cCI6MjA4MTA0NTA0N30.E080sOgNEw_7vU0c7_REt_uxwgE6fc4hIQhdUi4FCNw',
);

Future<void> main(List<String> args) async {
  final rates = _parseRates(args);
  final duration = _parseDuration(args);
  final url = Platform.environment['SUPABASE_URL'] ?? _defaultUrl;
  final anonKey = Platform.environment['SUPABASE_ANON_KEY'] ?? _defaultAnonKey;
  final email = Platform.environment['TEST_USER_A_EMAIL'];
  final password = Platform.environment['TEST_USER_A_PASSWORD'];

  final results = <Map<String, dynamic>>[];
  for (final rate in rates) {
    final result = await _runRate(
      url: url,
      anonKey: anonKey,
      email: email,
      password: password,
      rate: rate,
      duration: duration,
    );
    results.add(result);
    stdout.writeln(jsonEncode({'stress_result': result}));
  }

  stdout.writeln(
    'rate_per_second,closed,close_origin,close_code,close_reason,elapsed_ms,messages_sent,peak_per_second',
  );
  for (final row in results) {
    stdout.writeln([
      row['rate_per_second'],
      row['closed'],
      row['close_origin'],
      row['close_code'] ?? '',
      row['close_reason'] ?? '',
      row['elapsed_ms'],
      row['messages_sent'],
      row['messages_sent_peak_per_second'],
    ].join(','));
  }
}

List<int> _parseRates(List<String> args) {
  final value = _argValue(args, '--rates');
  if (value == null) return const [5, 10, 20, 50];
  return value.split(',').map((v) => int.parse(v.trim())).toList();
}

Duration _parseDuration(List<String> args) {
  final value = _argValue(args, '--duration-seconds');
  return Duration(seconds: value == null ? 60 : int.parse(value));
}

String? _argValue(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index == -1 || index == args.length - 1) return null;
  return args[index + 1];
}

Future<Map<String, dynamic>> _runRate({
  required String url,
  required String anonKey,
  required String? email,
  required String? password,
  required int rate,
  required Duration duration,
}) async {
  final client = SupabaseClient(url, anonKey);
  if (email != null && password != null) {
    await client.auth.signInWithPassword(email: email, password: password);
  }

  Object? closeEvent;
  Object? socketError;
  var messagesSent = 0;
  var sendErrors = 0;
  var sentThisSecond = 0;
  var peakPerSecond = 0;
  var channelClosed = false;
  var localClosing = false;
  var closeOrigin = 'none';
  Duration elapsed = Duration.zero;

  client.realtime.onClose((event) {
    closeEvent = event;
    channelClosed = true;
    closeOrigin = localClosing ? 'local' : 'remote';
  });
  client.realtime.onError((error) {
    socketError = error;
  });

  final topic = 'call-stress:${DateTime.now().microsecondsSinceEpoch}:$rate';
  final channel = client.channel(
    topic,
    opts: const RealtimeChannelConfig(ack: true),
  );

  final subscribed = Completer<void>();
  channel
      .onBroadcast(
    event: 'stress',
    callback: (_) {},
  )
      .subscribe((status, [error]) {
    if (status == RealtimeSubscribeStatus.subscribed &&
        !subscribed.isCompleted) {
      subscribed.complete();
    } else if ((status == RealtimeSubscribeStatus.closed ||
            status == RealtimeSubscribeStatus.channelError ||
            status == RealtimeSubscribeStatus.timedOut) &&
        !subscribed.isCompleted) {
      subscribed.completeError(error ?? status.name);
    }
    if (status == RealtimeSubscribeStatus.closed) {
      channelClosed = true;
      closeOrigin = localClosing ? 'local' : 'remote';
    }
  });

  await subscribed.future.timeout(const Duration(seconds: 15));

  final perMessageDelay = Duration(microseconds: 1000000 ~/ rate);
  final rateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
    if (sentThisSecond > peakPerSecond) peakPerSecond = sentThisSecond;
    sentThisSecond = 0;
  });

  final started = DateTime.now();
  final pendingSends = <Future<void>>[];
  while (DateTime.now().difference(started) < duration && !channelClosed) {
    elapsed = DateTime.now().difference(started);
    final seq = messagesSent++;
    sentThisSecond++;
    pendingSends.add(Future<void>(() async {
      try {
        await channel.sendBroadcastMessage(
          event: 'stress',
          payload: {
            'seq': seq,
            'sentAt': DateTime.now().toIso8601String(),
          },
        );
      } catch (_) {
        sendErrors++;
      }
    }));
    await Future<void>.delayed(perMessageDelay);
  }
  elapsed = DateTime.now().difference(started);
  await Future.wait(pendingSends);
  if (sentThisSecond > peakPerSecond) peakPerSecond = sentThisSecond;
  rateTimer.cancel();

  localClosing = true;
  await client.removeChannel(channel);
  await client.dispose();

  final closeText = closeEvent?.toString();
  return {
    'rate_per_second': rate,
    'duration_seconds': duration.inSeconds,
    'elapsed_ms': elapsed.inMilliseconds,
    'closed': channelClosed,
    'close_origin': closeOrigin,
    'close_code': _closeCode(closeText),
    'close_reason': _closeReason(closeText),
    'socket_error': socketError?.toString(),
    'messages_sent': messagesSent,
    'send_errors': sendErrors,
    'messages_sent_peak_per_second': peakPerSecond,
  };
}

String? _closeCode(String? closeText) {
  if (closeText == null) return null;
  return RegExp(r'code: ([0-9]+)').firstMatch(closeText)?.group(1);
}

String? _closeReason(String? closeText) {
  if (closeText == null) return null;
  return RegExp(r'reason: ([^)]*)').firstMatch(closeText)?.group(1);
}
