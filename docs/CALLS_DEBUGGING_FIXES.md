# Video/Audio Calls Realtime Debugging & Fixes

## Issues Found & Fixed

### 1. Missing Foreign Key in `call_room_members`
**Problem:** The `call_room_members` table was not properly linked to `video_calls` table with a foreign key constraint.

**Symptoms:**
- Calls could be created but room members weren't properly tracked
- Orphaned rows in call_room_members after call deletion
- No CASCADE delete behavior

**Fix:** Added foreign key constraint in migration
```sql
ALTER TABLE public.call_room_members
  ADD CONSTRAINT call_room_members_call_id_fkey
  FOREIGN KEY (call_id)
  REFERENCES public.video_calls(id)
  ON DELETE CASCADE;
```

**File:** `supabase/migrations/20260716100000_fix_calls_realtime.sql`

---

### 2. Insufficient Error Handling in Realtime Callbacks
**Problem:** Errors in realtime broadcast callbacks (offer, answer, ICE, media, etc.) were not caught, causing silent failures.

**Symptoms:**
- Call connection failures with no error messages
- Silent drops when handling WebRTC signaling
- No diagnostic information in console

**Fix:** Wrapped all realtime callbacks in try-catch blocks with debug logging

**File:** `lib/features/messages/presentation/providers_webrtc/call_provider.dart`

**Before:**
```dart
.onBroadcast(event: 'offer', callback: (payload) => _handleOffer(payload, localStream))
```

**After:**
```dart
.onBroadcast(
  event: 'offer',
  callback: (payload) {
    try {
      _handleOffer(payload, localStream);
    } catch (e, stack) {
      debugPrint('[WebRTC] Error handling offer: $e\n$stack');
    }
  },
)
```

**Applied to:** offer, answer, ice, media, resync, leave events

---

### 3. Missing Debug Logging in Critical Paths
**Problem:** No visibility into call flow, making debugging nearly impossible.

**Symptoms:**
- Can't diagnose where call setup fails
- No way to see if invites are sent/received
- No visibility into connection state changes

**Fix:** Added comprehensive debug logging throughout call flow

**Locations:**
- Channel subscription status
- Presence tracking
- Participant state updates
- Invite sending/receiving
- Call accept/decline

**Example:**
```dart
debugPrint('[WebRTC] Channel subscribe status: $status, error: $error');
debugPrint('[WebRTC] Presence tracked successfully');
debugPrint('[WebRTC] Updating participant state: ${row['connection_state']}');
```

---

### 4. Missing Timeouts on Database Operations
**Problem:** Supabase operations could hang indefinitely, blocking the call flow.

**Symptoms:**
- App freezes during call setup
- "Loading" dialog never closes
- Connection state stuck in "connecting"

**Fix:** Added 5-second timeouts to all critical database operations

**Example:**
```dart
await _sb
    .from('call_participants')
    .upsert(row, onConflict: 'call_id,user_id')
    .timeout(const Duration(seconds: 5));
```

**File:** `call_provider.dart`, `call_invite_listener.dart`

---

### 5. Incomplete RLS Policies
**Problem:** Row-level security policies didn't cover all access patterns for calls.

**Symptoms:**
- Permission denied errors when viewing call state
- Participants can't see each other's states
- Host can't update call status

**Fix:** Added/improved RLS policies in migration:
- `call_participants viewable` - See own state or conversation participants
- `call host can update call` - Host can end/update call
- `call participants read room members` - See all participants in call

**File:** `supabase/migrations/20260716100000_fix_calls_realtime.sql`

---

### 6. Missing Sync Between `call_participants` and `call_room_members`
**Problem:** Two tables tracked similar data but weren't synced, causing inconsistency.

**Symptoms:**
- Room members state out of sync with participants
- Media state not reflected in UI
- Connection state mismatches

**Fix:** Added database trigger to auto-sync tables

```sql
CREATE TRIGGER sync_call_participant_trigger
  AFTER INSERT OR UPDATE ON public.call_participants
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_call_participant_to_room_member();
```

**Result:** Any update to `call_participants` automatically updates `call_room_members`

---

### 7. Improved `create_video_call` Function
**Problem:** Function lacked validation and error messages.

**Symptoms:**
- Generic errors with no context
- Silent failures on invalid input
- No role tracking for host

**Fix:** Enhanced function with:
- Better error messages with HINT
- Automatic host role assignment in `call_room_members`
- Proper connection state initialization

**File:** `supabase/migrations/20260716100000_fix_calls_realtime.sql`

---

### 8. Call Invite Broadcast Not Waiting for Subscription
**Problem:** Broadcast messages sent before channel subscription completed.

**Symptoms:**
- Invites never received by recipients
- Call rings on caller side but not on receiver
- Silent failure with no error

**Fix:** Added subscription callback and 500ms delay

**Before:**
```dart
final channel = sb.channel('call-invite:$recipientId');
channel.subscribe();
await channel.sendBroadcastMessage(...); // Too early!
```

**After:**
```dart
channel.subscribe((status, [error]) async {
  if (status == RealtimeSubscribeStatus.subscribed) {
    await channel.sendBroadcastMessage(...);
  }
});
// Plus 500ms delay after loop
await Future.delayed(const Duration(milliseconds: 500));
```

**File:** `chat_page.dart` in `_startCall()` method

---

### 9. Missing Realtime Publication
**Problem:** `call_room_members` wasn't added to realtime publication.

**Symptoms:**
- Room member updates don't propagate in realtime
- UI doesn't update when participants join/leave
- Connection state changes not reflected

**Fix:** Added to realtime publication
```sql
ALTER PUBLICATION supabase_realtime ADD TABLE public.call_room_members;
```

**File:** `supabase/migrations/20260716100000_fix_calls_realtime.sql`

---

## Testing Checklist

### Before Testing
- [ ] Run migration: `supabase db push`
- [ ] Verify migration applied: Check `call_room_members` foreign key exists
- [ ] Clear app cache/reinstall to ensure fresh state

### Test Scenarios

#### 1. One-to-One Call
- [ ] User A calls User B (video)
- [ ] User B receives call notification
- [ ] User B accepts call
- [ ] Both see each other's video
- [ ] Audio works both directions
- [ ] Mute/unmute works
- [ ] Video on/off works
- [ ] Call ends cleanly

#### 2. One-to-One Audio Call
- [ ] User A calls User B (audio only)
- [ ] No video tracks
- [ ] Audio works both directions

#### 3. Group Call (3+ participants)
- [ ] Host starts call in group chat
- [ ] All members receive invite
- [ ] Multiple users can join
- [ ] All see each other's video/audio
- [ ] Host can end call

#### 4. Call Decline
- [ ] User A calls User B
- [ ] User B declines
- [ ] Call ends on User A side
- [ ] No error messages
- [ ] Both states cleaned up

#### 5. Connection Recovery
- [ ] Start call
- [ ] Turn off WiFi for 5 seconds
- [ ] Turn WiFi back on
- [ ] Call should reconnect (check "reconnecting" state)
- [ ] Media should resume

#### 6. Permissions
- [ ] Deny camera permission → audio-only call works
- [ ] Deny microphone → error message shown
- [ ] Grant permissions mid-call → devices switch

#### 7. Background/Foreground
- [ ] Start call
- [ ] Put app in background
- [ ] Return to foreground
- [ ] Call still active

### Debug Console Checks
While testing, watch console for:
- `[WebRTC]` logs showing connection flow
- `[CallInviteListener]` logs showing invite flow
- `[ChatPage]` logs showing call creation
- No errors in logs
- Connection state transitions: connecting → connected
- ICE candidates being exchanged

### Database Verification
After test calls, check:
```sql
-- All calls should have ended_at
SELECT id, status, started_at, ended_at FROM video_calls ORDER BY started_at DESC LIMIT 5;

-- Participants should have left_at
SELECT call_id, user_id, connection_state, joined_at, left_at FROM call_participants ORDER BY joined_at DESC LIMIT 10;

-- Room members synced with participants
SELECT call_id, user_id, connection_state, media_state FROM call_room_members ORDER BY updated_at DESC LIMIT 10;

-- Quality reports captured
SELECT call_id, user_id, quality, rtt_ms, packet_loss FROM call_quality_reports ORDER BY created_at DESC LIMIT 10;
```

---

## Known Limitations (Not Fixed)
1. **TURN server required for NAT traversal** - Calls between different networks may fail without TURN server
2. **No call recording** - Not implemented
3. **No screen sharing on iOS** - Platform limitation
4. **No background call support** - Requires CallKit/ConnectionService
5. **Video quality not adaptive** - Fixed 720p, no dynamic bitrate adjustment

---

## Debugging Tips

### Enable Verbose Logging
All critical paths now have `debugPrint()` statements. Look for:
- `[WebRTC]` - WebRTC connection, ICE, media
- `[CallInviteListener]` - Invite receiving
- `[ChatPage]` - Invite sending, call creation

### Check Realtime Connection
```dart
// In call_provider.dart, channel subscribe callback
debugPrint('[WebRTC] Channel subscribe status: $status, error: $error');
```
If status is NOT `subscribed`, realtime is broken.

### Check Database State
If calls don't work, check database directly:
```sql
-- Is call created?
SELECT * FROM video_calls WHERE id = 'call-id-here';

-- Are participants added?
SELECT * FROM call_participants WHERE call_id = 'call-id-here';

-- Is foreign key working?
SELECT * FROM call_room_members WHERE call_id = 'call-id-here';
```

### Common Errors & Solutions
| Error | Cause | Solution |
|-------|-------|----------|
| "Realtime channel error" | Realtime disabled or wrong config | Check Supabase dashboard → Realtime enabled |
| "Permission denied" | RLS policy blocking | Run migration with updated policies |
| "Timeout" | Database slow or network issue | Check internet, Supabase status |
| "Not authenticated" | User not logged in | Verify `auth.uid()` not null |
| "ICE failed" | No TURN server, NAT blocking | Configure TURN server in `call_webrtc_config` |

---

## Files Changed
1. `supabase/migrations/20260716100000_fix_calls_realtime.sql` - Database fixes
2. `lib/features/messages/presentation/providers_webrtc/call_provider.dart` - Error handling
3. `lib/features/messages/presentation/widgets/call_invite_listener.dart` - Logging & error handling
4. `lib/features/messages/presentation/pages/chat_page.dart` - Invite broadcast fix

---

## Next Steps (Future Improvements)
1. Add CallKit integration (iOS background calls)
2. Add ConnectionService (Android background calls)
3. Implement adaptive bitrate for video
4. Add call recording
5. Add call analytics dashboard
6. Implement call transfer
7. Add virtual backgrounds
8. Add noise cancellation

---

**Status:** 🔧 **All Critical Bugs Fixed**  
**Testing Required:** Manual testing of all scenarios above  
**Migration Required:** Yes - Run `20260716100000_fix_calls_realtime.sql`
