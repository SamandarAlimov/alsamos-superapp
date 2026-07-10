import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import '../pages/webrtc_call_page.dart';
import 'incoming_call_dialog.dart';

class CallInviteListener extends ConsumerStatefulWidget {
  final Widget child;
  const CallInviteListener({super.key, required this.child});

  @override
  ConsumerState<CallInviteListener> createState() => _CallInviteListenerState();
}

class _CallInviteListenerState extends ConsumerState<CallInviteListener> {
  RealtimeChannel? _channel;
  String? _listeningUserId;
  final Set<String> _seenCallIds = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureSubscription();
  }

  @override
  void didUpdateWidget(covariant CallInviteListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ensureSubscription();
  }

  void _ensureSubscription() {
    final uid = ref.read(authProvider).user?.id;
    if (uid == null) {
      if (_channel != null || _listeningUserId != null) {
        unawaited(_disposeChannel());
        _listeningUserId = null;
        _seenCallIds.clear();
      }
      return;
    }
    if (uid == _listeningUserId) return;
    unawaited(_disposeChannel());
    _listeningUserId = uid;
    _seenCallIds.clear();
    _channel = Supabase.instance.client.channel(
      'call-invite:$uid',
      opts: RealtimeChannelConfig(key: uid, enabled: true),
    )
      ..onBroadcast(event: 'incoming_call', callback: _handleIncomingCall)
      ..subscribe();
  }

  Future<void> _handleIncomingCall(Map<String, dynamic> payload) async {
    if (!mounted) return;
    final callId = payload['call_id'] as String?;
    final conversationId = payload['conversation_id'] as String?;
    final callerId = payload['caller_id'] as String?;
    if (callId == null || conversationId == null || callerId == _listeningUserId) {
      return;
    }
    if (!_seenCallIds.add(callId)) return;

    final type = payload['call_type'] as String? ?? 'video';
    final callerName = payload['caller_name'] as String? ?? 'Alsamos';
    final callerAvatar = payload['caller_avatar'] as String?;
    final currentUserId = _listeningUserId;
    if (currentUserId == null) return;

    await IncomingCallDialog.show(
      context,
      callerName: callerName,
      callerAvatar: callerAvatar,
      callType: type == 'audio' ? IncomingCallType.audio : IncomingCallType.video,
      onDecline: () async {
        await Supabase.instance.client.from('call_participants').update({
          'left_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('call_id', callId).eq('user_id', currentUserId);
      },
      onAccept: () async {
        await Supabase.instance.client.from('call_participants').upsert({
          'call_id': callId,
          'user_id': currentUserId,
          'joined_at': DateTime.now().toUtc().toIso8601String(),
          'is_muted': false,
          'is_video_on': type == 'video',
          'is_screen_sharing': false,
          'is_hand_raised': false,
        }, onConflict: 'call_id,user_id');
        if (!mounted) return;
        await Navigator.of(context, rootNavigator: true).push<Duration>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => WebRTCCallPage(
              roomId: callId,
              remoteName: callerName,
              remoteAvatar: callerAvatar,
              isVideo: type == 'video',
            ),
          ),
        );
      },
    );
  }

  Future<void> _disposeChannel() async {
    final channel = _channel;
    _channel = null;
    if (channel != null) await Supabase.instance.client.removeChannel(channel);
  }

  @override
  void dispose() {
    unawaited(_disposeChannel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authProvider, (_, __) => _ensureSubscription());
    return widget.child;
  }
}
