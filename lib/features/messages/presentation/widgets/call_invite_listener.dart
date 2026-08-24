import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import '../pages/webrtc_call_page.dart';
import '../providers_webrtc/call_provider.dart';
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
  Timer? _pushPoll;

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

  RealtimeChannel? _dbChannel;

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

    if (kDebugMode) {
      debugPrint('[CallInviteListener] Setting up channels for user: $uid');
    }

    // Channel 1: Broadcast-based invites (from Flutter callers)
    _channel = Supabase.instance.client.channel(
      'call-invite:$uid',
      opts: RealtimeChannelConfig(key: uid, enabled: true),
    )
      ..onBroadcast(
        event: 'incoming_call',
        callback: (payload) {
          try {
            _handleIncomingCall(payload);
          } catch (e, stack) {
            debugPrint(
                '[CallInviteListener] Error handling broadcast invite: $e\n$stack');
          }
        },
      )
      ..subscribe((status, error) {
        if (kDebugMode && status == RealtimeSubscribeStatus.subscribed) {
          debugPrint('[CallInviteListener] ✓ Subscribed to broadcast invites');
        }
      });

    // Channel 2: Postgres changes on video_calls (from Web callers)
    _dbChannel = Supabase.instance.client
        .channel('incoming-calls-db:$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'video_calls',
          callback: (payload) {
            unawaited(_handleDbCallInsert(payload.newRecord, uid));
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'call_invites',
          callback: (payload) {
            unawaited(_handleDbCallInvite(payload.newRecord, uid));
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'call_invites',
          callback: (payload) {
            unawaited(_handleDbCallInvite(payload.newRecord, uid));
          },
        )
        .subscribe((status, error) {
      if (kDebugMode && status == RealtimeSubscribeStatus.subscribed) {
        debugPrint('[CallInviteListener] ✓ Subscribed to DB call inserts');
      }
    });

    _pushPoll ??= Timer.periodic(
      const Duration(seconds: 2),
      (_) => _consumePendingCallPushes(),
    );
  }

  Future<void> _handleDbCallInsert(
      Map<String, dynamic> record, String uid) async {
    if (!mounted) return;
    final callId = record['id'] as String?;
    final hostId = record['host_id'] as String?;
    final conversationId = record['conversation_id'] as String?;
    final callType = record['call_type'] as String? ?? 'video';
    final status = record['status'] as String?;

    if (callId == null || conversationId == null) return;
    if (hostId == uid) return; // Our own call
    if (status == 'ended') return;
    if (_seenCallIds.contains(callId)) return; // Already seen

    // Verify we are a participant of this conversation
    try {
      final participant = await Supabase.instance.client
          .from('conversation_participants')
          .select('id')
          .eq('conversation_id', conversationId)
          .eq('user_id', uid)
          .maybeSingle()
          .timeout(const Duration(seconds: 5));
      if (participant == null) return;
    } catch (_) {
      return;
    }

    // Fetch caller profile
    String callerName = 'Alsamos';
    String? callerAvatar;
    try {
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('display_name, username, avatar_url')
          .eq('id', hostId!)
          .maybeSingle()
          .timeout(const Duration(seconds: 5));
      callerName = (profile?['display_name'] as String?) ??
          (profile?['username'] as String?) ??
          'Alsamos';
      callerAvatar = profile?['avatar_url'] as String?;
    } catch (_) {}

    await _handleIncomingCall({
      'call_id': callId,
      'conversation_id': conversationId,
      'caller_id': hostId,
      'caller_name': callerName,
      'caller_avatar': callerAvatar,
      'call_type': callType,
    });
  }

  Future<void> _handleDbCallInvite(
      Map<String, dynamic> record, String uid) async {
    if (!mounted) return;

    final inviteeId = record['invitee_id'] as String?;
    if (inviteeId != uid) return;

    final status = (record['status'] as String?) ?? 'pending';
    if (status == 'accepted' ||
        status == 'declined' ||
        status == 'cancelled' ||
        status == 'missed' ||
        status == 'ended') {
      return;
    }

    final callId = record['call_id'] as String?;
    if (callId == null) return;

    var conversationId = record['conversation_id'] as String?;
    var callerId = record['inviter_id'] as String?;
    var callType = (record['call_type'] as String?) ?? 'video';
    final rawMetadata = record['metadata'];
    final metadata = rawMetadata is Map ? rawMetadata : const {};
    var callerName = metadata['caller_name']?.toString() ?? 'Alsamos';
    var callerAvatar = metadata['caller_avatar']?.toString();

    if (conversationId == null || callerId == null) {
      try {
        final call = await Supabase.instance.client
            .from('video_calls')
            .select('conversation_id, host_id, call_type')
            .eq('id', callId)
            .maybeSingle()
            .timeout(const Duration(seconds: 5));
        conversationId ??= call?['conversation_id'] as String?;
        callerId ??= call?['host_id'] as String?;
        callType = (call?['call_type'] as String?) ?? callType;
      } catch (e) {
        debugPrint('[CallInviteListener] invite call lookup failed: $e');
      }
    }

    if (conversationId == null || callerId == null || callerId == uid) return;

    if (callerName == 'Alsamos' || callerAvatar == null) {
      try {
        final profile = await Supabase.instance.client
            .from('profiles')
            .select('display_name, username, avatar_url')
            .eq('id', callerId)
            .maybeSingle()
            .timeout(const Duration(seconds: 5));
        callerName = (profile?['display_name'] as String?) ??
            (profile?['username'] as String?) ??
            callerName;
        callerAvatar = profile?['avatar_url'] as String? ?? callerAvatar;
      } catch (_) {}
    }

    await _handleIncomingCall({
      'call_id': callId,
      'conversation_id': conversationId,
      'caller_id': callerId,
      'caller_name': callerName,
      'caller_avatar': callerAvatar,
      'call_type': callType,
    });
  }

  Future<void> _consumePendingCallPushes() async {
    if (!mounted || _listeningUserId == null) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('alsamos_pending_pushes') ?? const [];
    if (raw.isEmpty) return;
    final remaining = <String>[];
    for (final item in raw) {
      try {
        final payload = jsonDecode(item) as Map<String, dynamic>;
        final type = payload['type']?.toString();
        if (type != 'call' && type != 'incoming_call') {
          remaining.add(item);
          continue;
        }
        await _handleIncomingCall({
          'call_id': payload['call_id'] ?? payload['message_id'],
          'conversation_id': payload['conversation_id'],
          'caller_id': payload['sender_id'] ?? payload['caller_id'],
          'caller_name': payload['title'] ?? payload['caller_name'],
          'caller_avatar': payload['caller_avatar'],
          'call_type': payload['call_type'] ?? 'video',
        });
      } catch (_) {
        remaining.add(item);
      }
    }
    await prefs.setStringList('alsamos_pending_pushes', remaining);
  }

  Future<void> _handleIncomingCall(Map<String, dynamic> payload) async {
    if (!mounted) return;

    final callId = payload['call_id'] as String?;
    final conversationId = payload['conversation_id'] as String?;
    final callerId = payload['caller_id'] as String?;

    if (callId == null || conversationId == null) {
      if (kDebugMode) {
        debugPrint(
            '[CallInviteListener] Invalid payload: missing call_id or conversation_id');
      }
      return;
    }
    if (callerId == _listeningUserId) {
      return; // Ignore own calls silently
    }
    if (!_seenCallIds.add(callId)) {
      return; // Already processed this call
    }

    final type = payload['call_type'] as String? ?? 'video';
    final callerName = payload['caller_name'] as String? ?? 'Alsamos';
    final callerAvatar = payload['caller_avatar'] as String?;
    final currentUserId = _listeningUserId;

    if (currentUserId == null) return;

    await IncomingCallDialog.show(
      context,
      callerName: callerName,
      callerAvatar: callerAvatar,
      callType:
          type == 'audio' ? IncomingCallType.audio : IncomingCallType.video,
      onDecline: () async {
        try {
          await _declineCall(callId: callId, currentUserId: currentUserId);
        } catch (e, stack) {
          debugPrint('[CallInviteListener] Error declining call: $e\n$stack');
        } finally {
          _forgetCall(callId);
        }
      },
      onAccept: () async {
        try {
          await _joinCall(
            callId: callId,
            currentUserId: currentUserId,
            isVideo: type == 'video',
          );

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
        } catch (e, stack) {
          debugPrint('[CallInviteListener] Error accepting call: $e\n$stack');
          _forgetCall(callId);
        } finally {
          _forgetCall(callId);
        }
      },
    );
  }

  void _forgetCall(String callId) {
    _seenCallIds.removeWhere(
      (seen) => seen == callId || seen.startsWith('$callId:'),
    );
  }

  Future<void> _joinCall({
    required String callId,
    required String currentUserId,
    required bool isVideo,
  }) async {
    final sb = Supabase.instance.client;

    try {
      final result = await sb.rpc('join_video_call_guarded', params: {
        'p_call_id': callId,
        'p_is_video_on': isVideo,
      }).timeout(const Duration(seconds: 8));

      if (result is Map && result['joined'] == false) {
        throw StateError(result['reason']?.toString() ?? 'call_join_failed');
      }

      await _markCallInviteAccepted(callId);
      return;
    } catch (e) {
      if (!_isMissingRpc(e)) rethrow;
      debugPrint(
          '[CallInviteListener] join_video_call_guarded unavailable, using fallback: $e');
    }

    // Fallback for older Lovable DBs: same lifecycle, without capacity guard.
    final callData = await sb
        .from('video_calls')
        .select('id,status')
        .eq('id', callId)
        .maybeSingle()
        .timeout(const Duration(seconds: 5));
    if (callData == null || callData['status'] == 'ended') {
      throw StateError('call_ended');
    }

    final now = DateTime.now().toUtc().toIso8601String();
    final existing = await sb
        .from('call_participants')
        .select('id')
        .eq('call_id', callId)
        .eq('user_id', currentUserId)
        .maybeSingle()
        .timeout(const Duration(seconds: 5));

    if (existing != null && existing['id'] != null) {
      await sb
          .from('call_participants')
          .update({
            'joined_at': now,
            'left_at': null,
            'is_muted': false,
            'is_video_on': isVideo,
            'is_screen_sharing': false,
            'is_hand_raised': false,
          })
          .eq('id', existing['id'])
          .timeout(const Duration(seconds: 5));
      await _markCallInviteAccepted(callId);
      return;
    }

    final participant = {
      'call_id': callId,
      'user_id': currentUserId,
      'is_muted': false,
      'is_video_on': isVideo,
      'is_screen_sharing': false,
      'is_hand_raised': false,
    };

    try {
      await sb
          .from('call_participants')
          .insert(participant)
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      if (!_isDuplicateConflict(e)) rethrow;
      await sb
          .from('call_participants')
          .update({
            ...participant,
            'joined_at': now,
            'left_at': null,
          })
          .eq('call_id', callId)
          .eq('user_id', currentUserId)
          .timeout(const Duration(seconds: 5));
    }
    await _markCallInviteAccepted(callId);
  }

  Future<void> _markCallInviteAccepted(String callId) async {
    final uid = _listeningUserId;
    if (uid == null) return;
    try {
      await Supabase.instance.client
          .from('call_invites')
          .update({'status': 'accepted'})
          .eq('call_id', callId)
          .eq('invitee_id', uid)
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('[CallInviteListener] invite accept update failed: $e');
    }
  }

  Future<void> _declineCall({
    required String callId,
    required String currentUserId,
  }) async {
    final sb = Supabase.instance.client;
    final now = DateTime.now().toUtc().toIso8601String();

    try {
      await sb
          .from('video_calls')
          .update({
            'status': 'ended',
            'ended_at': now,
          })
          .eq('id', callId)
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('[CallInviteListener] decline update failed: $e');
    }

    try {
      await sb.from('call_participants').upsert({
        'call_id': callId,
        'user_id': currentUserId,
        'joined_at': null,
        'left_at': now,
        'is_muted': false,
        'is_video_on': false,
        'is_screen_sharing': false,
        'is_hand_raised': false,
        'connection_state': 'declined',
        'last_seen_at': now,
      }, onConflict: 'call_id,user_id').timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('[CallInviteListener] decline participant update failed: $e');
    }

    try {
      await sb
          .from('call_invites')
          .update({'status': 'declined'})
          .eq('call_id', callId)
          .eq('invitee_id', currentUserId)
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('[CallInviteListener] decline invite update failed: $e');
    }
  }

  bool _isMissingRpc(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('pgrst202') ||
        message.contains('42883') ||
        (message.contains('function') && message.contains('does not exist')) ||
        message.contains('could not find the function');
  }

  bool _isDuplicateConflict(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('23505') ||
        message.contains('duplicate key') ||
        message.contains('already exists') ||
        message.contains('allaqachon');
  }

  Future<void> _disposeChannel() async {
    final channel = _channel;
    _channel = null;
    if (channel != null) await Supabase.instance.client.removeChannel(channel);
    final dbCh = _dbChannel;
    _dbChannel = null;
    if (dbCh != null) await Supabase.instance.client.removeChannel(dbCh);
  }

  @override
  void dispose() {
    _pushPoll?.cancel();
    unawaited(_disposeChannel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authProvider, (_, __) => _ensureSubscription());
    final mini = ref.watch(callMiniOverlayProvider);
    return Stack(
      children: [
        widget.child,
        if (mini != null) _MiniCallOverlay(session: mini),
      ],
    );
  }
}

class _MiniCallOverlay extends ConsumerStatefulWidget {
  const _MiniCallOverlay({required this.session});
  final MiniCallSession session;

  @override
  ConsumerState<_MiniCallOverlay> createState() => _MiniCallOverlayState();
}

class _MiniCallOverlayState extends ConsumerState<_MiniCallOverlay> {
  Offset _offset = const Offset(18, 96);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(callProvider(widget.session.roomId));
    return Positioned(
      right: _offset.dx,
      top: _offset.dy,
      child: GestureDetector(
        onPanUpdate: (d) {
          setState(() {
            _offset = Offset(
              (_offset.dx - d.delta.dx).clamp(8, 280),
              (_offset.dy + d.delta.dy).clamp(48, 560),
            );
          });
        },
        onTap: () {
          Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) => WebRTCCallPage(
                roomId: widget.session.roomId,
                remoteName: widget.session.remoteName,
                remoteAvatar: widget.session.remoteAvatar,
                isVideo: widget.session.isVideo,
              ),
            ),
          );
        },
        child: Material(
          elevation: 14,
          borderRadius: BorderRadius.circular(20),
          color: Colors.black.withValues(alpha: 0.82),
          child: Container(
            width: 172,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                  color: Color(0xFF16A34A),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  widget.session.isVideo
                      ? LucideIcons.video
                      : LucideIcons.phone,
                  color: Colors.white,
                  size: 19,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.session.remoteName ?? 'Qo\'ng\'iroq',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      state.isReconnecting
                          ? 'Qayta ulanmoqda'
                          : state.elapsed.inSeconds > 0
                              ? '${state.elapsed.inMinutes.toString().padLeft(2, '0')}:${(state.elapsed.inSeconds % 60).toString().padLeft(2, '0')}'
                              : 'Active',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
