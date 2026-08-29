import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase/supabase.dart';

const _defaultSupabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://mbhjganbihamoiqmankv.supabase.co',
);
const _defaultSupabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue:
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1iaGpnYW5iaWhhbW9pcW1hbmt2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjU0NjkwNDcsImV4cCI6MjA4MTA0NTA0N30.E080sOgNEw_7vU0c7_REt_uxwgE6fc4hIQhdUi4FCNw',
);
const _envStun = String.fromEnvironment('ALSAMOS_STUN_URLS');
const _envTurn = String.fromEnvironment('ALSAMOS_TURN_URLS');
const _envTurnUser = String.fromEnvironment('ALSAMOS_TURN_USERNAME');
const _envTurnCredential = String.fromEnvironment('ALSAMOS_TURN_CREDENTIAL');

Future<void> main(List<String> args) async {
  stdout.writeln('TURN CHECK START');
  stdout.writeln('iceTransportPolicy=relay');
  stdout.writeln(
    'onIceCandidateError=UNAVAILABLE_IN_flutter_webrtc_1.6.0_DART_API',
  );

  final servers = await _loadIceServers();
  final turnServers = servers.where(_isTurnServer).toList();
  stdout.writeln('ice_servers_total=${servers.length}');
  stdout.writeln('turn_servers_total=${turnServers.length}');
  stdout.writeln('turn_servers_redacted=${jsonEncode(_redact(turnServers))}');

  if (turnServers.isEmpty) {
    stdout.writeln('TURN BROKEN: 0 relay candidates');
    stdout.writeln('reason=no TURN servers found in DB/env config');
    return;
  }

  final candidates = <RTCIceCandidate>[];
  RTCPeerConnection? pc;
  try {
    pc = await createPeerConnection({
      'iceServers': turnServers,
      'iceTransportPolicy': 'relay',
      'bundlePolicy': 'max-bundle',
      'rtcpMuxPolicy': 'require',
      'sdpSemantics': 'unified-plan',
      'iceCandidatePoolSize': 0,
    });
    pc.onIceCandidate = (candidate) {
      final raw = candidate.candidate;
      if (raw == null || raw.isEmpty) return;
      candidates.add(candidate);
      stdout.writeln(
        'candidate type=${_candidateType(raw)} sdpMid=${candidate.sdpMid} '
        'sdpMLineIndex=${candidate.sdpMLineIndex} raw=$raw',
      );
    };
    pc.onIceGatheringState = (state) {
      stdout.writeln('iceGatheringState=$state');
    };
    pc.onIceConnectionState = (state) {
      stdout.writeln('iceConnectionState=$state');
    };
    pc.onConnectionState = (state) {
      stdout.writeln('connectionState=$state');
    };

    await pc.createDataChannel(
      'turn-check',
      RTCDataChannelInit()..ordered = true,
    );
    final offer = await pc.createOffer({
      'offerToReceiveAudio': false,
      'offerToReceiveVideo': false,
    });
    await pc.setLocalDescription(offer);
    await Future<void>.delayed(const Duration(seconds: 15));
  } catch (e, stack) {
    stdout.writeln('turn_check_exception=$e');
    stdout.writeln('turn_check_stack=$stack');
  } finally {
    await pc?.close();
  }

  final relayCount = candidates
      .where((candidate) => _candidateType(candidate.candidate ?? '') == 'relay')
      .length;
  if (relayCount > 0) {
    stdout.writeln('TURN OK: $relayCount relay candidates');
  } else {
    stdout.writeln('TURN BROKEN: 0 relay candidates');
  }
}

Future<List<Map<String, dynamic>>> _loadIceServers() async {
  final servers = <Map<String, dynamic>>[];
  final url = Platform.environment['SUPABASE_URL'] ?? _defaultSupabaseUrl;
  final anonKey =
      Platform.environment['SUPABASE_ANON_KEY'] ?? _defaultSupabaseAnonKey;
  try {
    final client = SupabaseClient(url, anonKey);
    final row = await client
        .from('call_webrtc_config')
        .select('value')
        .eq('key', 'ice_servers')
        .maybeSingle()
        .timeout(const Duration(seconds: 5));
    servers.addAll(_iceServersFromValue(row?['value']));
    await client.dispose();
  } catch (e) {
    stdout.writeln('ice_config_db_error=$e');
  }
  servers.addAll(_iceServersFromEnv(
    stunUrls: Platform.environment['ALSAMOS_STUN_URLS'] ?? _envStun,
    turnUrls: Platform.environment['ALSAMOS_TURN_URLS'] ?? _envTurn,
    turnUsername:
        Platform.environment['ALSAMOS_TURN_USERNAME'] ?? _envTurnUser,
    turnCredential:
        Platform.environment['ALSAMOS_TURN_CREDENTIAL'] ?? _envTurnCredential,
  ));
  return _dedupeIceServers(servers);
}

List<Map<String, dynamic>> _iceServersFromValue(Object? value) {
  try {
    final decoded = value is String ? jsonDecode(value) : value;
    if (decoded is Map && decoded['iceServers'] is List) {
      return (decoded['iceServers'] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((e) => e['urls'] != null)
          .toList();
    }
    if (decoded is List) {
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((e) => e['urls'] != null)
          .toList();
    }
  } catch (e) {
    stdout.writeln('ice_config_parse_error=$e');
  }
  return const [];
}

List<Map<String, dynamic>> _iceServersFromEnv({
  required String stunUrls,
  required String turnUrls,
  required String turnUsername,
  required String turnCredential,
}) {
  final servers = <Map<String, dynamic>>[];
  final stun = _splitUrls(stunUrls);
  if (stun.isNotEmpty) servers.addAll(stun.map((url) => {'urls': url}));
  final turn = _splitUrls(turnUrls);
  if (turn.isNotEmpty) {
    servers.add({
      'urls': turn,
      if (turnUsername.isNotEmpty) 'username': turnUsername,
      if (turnCredential.isNotEmpty) 'credential': turnCredential,
    });
  }
  return servers;
}

List<String> _splitUrls(String raw) =>
    raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

bool _isTurnServer(Map<String, dynamic> server) =>
    _urlsOf(server['urls']).any((url) => url.startsWith('turn'));

List<String> _urlsOf(Object? urls) {
  if (urls is String) return [urls];
  if (urls is List) return urls.whereType<String>().toList();
  return const [];
}

List<Map<String, dynamic>> _dedupeIceServers(
  List<Map<String, dynamic>> servers,
) {
  final seen = <String>{};
  final out = <Map<String, dynamic>>[];
  for (final server in servers) {
    final urls = _urlsOf(server['urls']);
    if (urls.isEmpty) continue;
    final key = [
      ...urls,
      server['username'] ?? '',
      server['credentialType'] ?? '',
    ].join('|');
    if (seen.add(key)) out.add(server);
  }
  return out;
}

List<Map<String, dynamic>> _redact(List<Map<String, dynamic>> servers) {
  return servers
      .map((server) => {
            ...server,
            if (server.containsKey('credential')) 'credential': '***',
          })
      .toList();
}

String _candidateType(String candidate) {
  return RegExp(r' typ (host|srflx|relay|prflx)(?: |$)')
          .firstMatch(candidate)
          ?.group(1) ??
      'unknown';
}
