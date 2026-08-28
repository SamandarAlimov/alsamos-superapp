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
  final duration = Duration(
    seconds: int.tryParse(_argValue(args, '--duration-seconds') ?? '') ?? 180,
  );
  final url = Platform.environment['SUPABASE_URL'] ?? _defaultUrl;
  final anonKey = Platform.environment['SUPABASE_ANON_KEY'] ?? _defaultAnonKey;

  final emailA = Platform.environment['TEST_USER_A_EMAIL'];
  final passwordA = Platform.environment['TEST_USER_A_PASSWORD'];
  final emailB = Platform.environment['TEST_USER_B_EMAIL'];
  final passwordB = Platform.environment['TEST_USER_B_PASSWORD'];

  final missing = <String>[
    if (emailA == null) 'TEST_USER_A_EMAIL',
    if (passwordA == null) 'TEST_USER_A_PASSWORD',
    if (emailB == null) 'TEST_USER_B_EMAIL',
    if (passwordB == null) 'TEST_USER_B_PASSWORD',
  ];
  if (missing.isNotEmpty) {
    stderr.writeln(
        'Missing required environment variables: ${missing.join(', ')}');
    exitCode = 64;
    return;
  }

  final roomId = _argValue(args, '--room-id') ??
      'loopback-${DateTime.now().microsecondsSinceEpoch}';
  final a = _RealtimeLoopbackPeer(
    name: 'a',
    url: url,
    anonKey: anonKey,
    email: emailA!,
    password: passwordA!,
    roomId: roomId,
  );
  final b = _RealtimeLoopbackPeer(
    name: 'b',
    url: url,
    anonKey: anonKey,
    email: emailB!,
    password: passwordB!,
    roomId: roomId,
  );

  await a.start();
  await b.start();
  await a.send('offer', {'sdp': 'loopback-offer', 'type': 'offer'});
  await b.send('answer', {'sdp': 'loopback-answer', 'type': 'answer'});
  for (var i = 0; i < 6; i++) {
    await a.send('ice', {'candidate': 'candidate-a-$i'});
    await b.send('ice', {'candidate': 'candidate-b-$i'});
  }

  await Future<void>.delayed(duration);
  final summary = {
    'duration_seconds': duration.inSeconds,
    'room_id': roomId,
    'media_webrtc': 'not_run_headless_dart_cli',
    'channel_closes': a.channelCloses + b.channelCloses,
    'close_codes': [...a.closeCodes, ...b.closeCodes],
    'messages_sent': a.messagesSent + b.messagesSent,
    'messages_sent_peak_per_second':
        a.messagesSentPeakPerSecond + b.messagesSentPeakPerSecond,
    'ice_candidates_sent': a.iceCandidatesSent + b.iceCandidatesSent,
    'resubscribes': 0,
    'jwt_refreshes': a.jwtRefreshes + b.jwtRefreshes,
    'heartbeats_sent': 'not_exposed_by_realtime_client',
    'heartbeats_missed': 'not_exposed_by_realtime_client',
    'messages_received': a.messagesReceived + b.messagesReceived,
  };
  stdout.writeln(jsonEncode({'loopback_summary': summary}));
  await a.stop();
  await b.stop();
}

String? _argValue(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index == -1 || index == args.length - 1) return null;
  return args[index + 1];
}

class _RealtimeLoopbackPeer {
  _RealtimeLoopbackPeer({
    required this.name,
    required this.url,
    required this.anonKey,
    required this.email,
    required this.password,
    required this.roomId,
  });

  final String name;
  final String url;
  final String anonKey;
  final String email;
  final String password;
  final String roomId;

  late final SupabaseClient client;
  late final RealtimeChannel channel;
  final closeCodes = <String>[];
  var channelCloses = 0;
  var messagesSent = 0;
  var messagesReceived = 0;
  var iceCandidatesSent = 0;
  var jwtRefreshes = 0;
  var _sentThisSecond = 0;
  var messagesSentPeakPerSecond = 0;
  Timer? _rateTimer;

  Future<void> start() async {
    client = SupabaseClient(url, anonKey);
    client.auth.onAuthStateChange.listen((event) {
      if (event.event == AuthChangeEvent.tokenRefreshed) jwtRefreshes++;
    });
    await client.auth.signInWithPassword(email: email, password: password);
    client.realtime.onClose((event) {
      channelCloses++;
      final text = event?.toString();
      final code = text == null
          ? null
          : RegExp(r'code: ([0-9]+)').firstMatch(text)?.group(1);
      if (code != null) closeCodes.add(code);
    });

    channel = client.channel(
      'webrtc:$roomId',
      opts: RealtimeChannelConfig(ack: true, key: name, enabled: true),
    );
    final subscribed = Completer<void>();
    for (final event in const ['offer', 'answer', 'ice']) {
      channel.onBroadcast(
        event: event,
        callback: (_) => messagesReceived++,
      );
    }
    channel.subscribe((status, [error]) {
      if (status == RealtimeSubscribeStatus.subscribed &&
          !subscribed.isCompleted) {
        subscribed.complete();
      } else if ((status == RealtimeSubscribeStatus.closed ||
              status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.timedOut) &&
          !subscribed.isCompleted) {
        subscribed.completeError(error ?? status.name);
      }
    });
    await subscribed.future.timeout(const Duration(seconds: 15));
    _rateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_sentThisSecond > messagesSentPeakPerSecond) {
        messagesSentPeakPerSecond = _sentThisSecond;
      }
      _sentThisSecond = 0;
    });
  }

  Future<void> send(String event, Map<String, dynamic> payload) async {
    await channel.sendBroadcastMessage(
      event: event,
      payload: {
        ...payload,
        'from': name,
        'messageId': '$roomId:$name:$messagesSent',
        'sentAt': DateTime.now().toIso8601String(),
      },
    );
    messagesSent++;
    _sentThisSecond++;
    if (event == 'ice') iceCandidatesSent++;
  }

  Future<void> stop() async {
    _rateTimer?.cancel();
    if (_sentThisSecond > messagesSentPeakPerSecond) {
      messagesSentPeakPerSecond = _sentThisSecond;
    }
    await client.removeChannel(channel);
    await client.dispose();
  }
}
