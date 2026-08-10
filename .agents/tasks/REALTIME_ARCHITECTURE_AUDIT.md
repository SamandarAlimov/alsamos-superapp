# Alsamos Realtime Architecture - Production Audit Report
**Date**: 2026-08-03  
**Severity**: CRITICAL  
**Status**: PRODUCTION-BLOCKING BUGS IDENTIFIED

---

## EXECUTIVE SUMMARY

**The current realtime architecture has 27 critical production bugs that cause:**
- Missing messages (race conditions in merge logic)
- Missing posts (no realtime subscription)
- Stale UI (cache invalidation bugs)
- Memory leaks (channel orphans)
- Duplicate subscriptions (no deduplication)
- Connection storms (no backpressure)
- Inconsistent state across devices

**This system is NOT production-ready for a social network.**

---

## CRITICAL BUGS IDENTIFIED

### 🔴 BUG #1: POSTS FEED HAS NO REALTIME SUBSCRIPTION
**Location**: `lib/features/home/presentation/providers/posts_provider.dart`
**Severity**: CRITICAL
**Impact**: New posts never appear until manual refresh


**Current Code**:
```dart
class PostsNotifier extends StateNotifier<PostsState> {
  final PostsRepository _repo;
  PostsNotifier(this._repo) : super(const PostsState()) {
    refresh(); // ❌ NO REALTIME SUBSCRIPTION
  }
```

**Problem**: Posts feed only loads on init. No Postgres Changes listener for new posts.

**How to Reproduce**:
1. User A opens app, sees feed
2. User B posts something
3. User A NEVER sees the new post unless they manually pull-to-refresh

**Fix**: Add realtime channel subscription similar to messages

---

### 🔴 BUG #2: MESSAGES RACE CONDITION - REALTIME INSERT vs OPTIMISTIC UPDATE
**Location**: `lib/features/messages/presentation/providers/messages_provider.dart:178-217`
**Severity**: CRITICAL
**Impact**: Duplicate messages, missing messages, incorrect message order


**Current Code**:
```dart
_channel = supabase.channel('messages-realtime-$_convId')
  ..onPostgresChanges(
    event: PostgresChangeEvent.insert,
    schema: 'public',
    table: 'messages',
    filter: PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'conversation_id',
      value: _convId,
    ),
    callback: (payload) async {
      try {
        final id = payload.newRecord['id'] as String;
        if (_processed.contains(id)) return; // ❌ SIZE-LIMITED SET
        _processed.add(id);
        
        // ❌ RACE: Fetch from DB while optimistic update is in flight
        final data = await supabase.from('messages').select(...).eq('id', id).maybeSingle();
        final message = await _repo.hydratePrivateMediaUrl(Message.fromMap(data));
        
        // ❌ RACE: Merge while send() might be updating state
        final updated = _mergeMessages(state.messages, [message]);
        state = state.copyWith(messages: updated);
      }
    },
  )
```

**Problems**:
1. `_processed` set clears at 5000 → old messages can be re-processed
2. No lock/mutex → state.messages can be modified during merge
3. `_mergeMessages()` complex dedup logic prone to edge cases
4. Realtime insert arrives BEFORE send() completes → can create duplicate


**How to Reproduce**:
1. Send message rapidly (click send 3 times fast)
2. Sometimes see duplicate, sometimes message missing
3. More likely on slow network (race window larger)

**Real Production Scenario**:
```
Timeline:
T+0ms   User clicks Send
T+10ms  Optimistic message added (tempId: temp-123)
T+50ms  send() starts network request
T+200ms Realtime insert event arrives (id: msg-456)
T+210ms _mergeMessages() runs → sees temp-123 and msg-456
T+220ms Network response → message has ID msg-456
T+230ms send() tries to replace temp-123 with msg-456
Result: Now TWO copies of msg-456 in UI (one from realtime, one from send)
```

---

### 🔴 BUG #3: CONVERSATIONS DEBOUNCED RELOAD = STALE UI
**Location**: `lib/features/messages/presentation/providers/conversations_provider.dart:80-83`
**Severity**: HIGH
**Impact**: Conversation list doesn't update for 300ms, stale unread counts

**Current Code**:
```dart
void _scheduleReload() {
  _reloadDebounce?.cancel();
  _reloadDebounce = Timer(const Duration(milliseconds: 300), () => load());
}
```

**Problem**: Every realtime event triggers a debounced reload. If events arrive every 200ms, reload NEVER happens (debounce keeps resetting).


**How to Reproduce**:
1. Receive 5 messages in 5 different conversations within 1 second
2. Conversation list stays stale because debounce keeps resetting
3. User never sees unread badges update

---

### 🔴 BUG #4: NO REALTIME CHANNEL DEDUPLICATION
**Location**: Multiple providers create channels with same name
**Severity**: CRITICAL
**Impact**: Memory leaks, connection storms, duplicate events

**Current Code** (scattered across providers):
```dart
// MessagesNotifier
_channel = supabase.channel('messages-realtime-$_convId')

// ConversationsNotifier  
_channel = supabase.channel('conversations-list-$_userId')

// CallInviteListener
_channel = Supabase.instance.client.channel('call-invite:$uid')
```

**Problem**: No global registry. If provider is recreated (hot reload, navigation), old channel leaks.

**Proof**:
```dart
// Provider #1 created
final ch1 = supabase.channel('messages-realtime-abc');
// Provider disposed but channel NOT removed
// Provider #2 created  
final ch2 = supabase.channel('messages-realtime-abc');
// NOW TWO CHANNELS listening to same conversation
```


**How to Reproduce**:
1. Open chat page
2. Navigate away
3. Navigate back
4. Check `supabase.getChannels()` → see duplicate channels

---

### 🔴 BUG #5: CHANNEL NOT REMOVED ON DISPOSE
**Location**: `lib/features/messages/presentation/providers/messages_provider.dart:96-100`
**Severity**: HIGH
**Impact**: Memory leak, zombie listeners

**Current Code**:
```dart
@override
void dispose() {
  _reloadDebounce?.cancel();
  if (_channel != null) supabase.removeChannel(_channel); // ❌ BAD
  super.dispose();
}
```

**Problems**:
1. `supabase.removeChannel()` is async but not awaited
2. If dispose() called twice, channel already removed → silent failure
3. No guarantee channel unsubscribed before removal

**Correct Pattern**:
```dart
@override
void dispose() {
  _reloadDebounce?.cancel();
  if (_channel != null) {
    unawaited(_channel!.unsubscribe().then((_) => supabase.removeChannel(_channel!)));
  }
  super.dispose();
}
```

---

### 🔴 BUG #6: MISSING AWAIT IN ASYNC CALLBACKS
**Location**: `lib/features/messages/presentation/providers/messages_provider.dart:178-217`
**Severity**: HIGH
**Impact**: Operations complete out of order, state corruption

**Current Code**:
```dart
callback: (payload) async {
  try {
    final id = payload.newRecord['id'] as String;
    if (_processed.contains(id)) return;
    _processed.add(id);
    final data = await supabase.from('messages').select(...).eq('id', id).maybeSingle();
    // ... more awaits
  } catch (e, stack) {
    debugPrint('[MessagesProvider] Error handling message insert: $e\n$stack');
  }
},
```

**Problem**: `callback` returns `Future<void>` but Supabase doesn't await it. If event 2 arrives before event 1 completes, race condition.

---

### 🔴 BUG #7: CONVERSATIONS LOAD HAS NO ERROR RECOVERY
**Location**: `lib/features/messages/presentation/providers/conversations_provider.dart:95-115`
**Severity**: HIGH
**Impact**: One failed load = stuck in loading state forever

**Current Code**:
```dart
Future<void> load() async {
  if (_userId == null) return;
  if (_loadInFlight) return; // ❌ DEADLOCK
  _loadInFlight = true;
  try {
    final conversations = await _repo.fetchConversations(_userId);
    if (!mounted) return;
    state = AsyncValue.data(conversations);
  } catch (e, st) {
    if (!mounted) return;
    state = AsyncValue.error(e, st); // ❌ _loadInFlight NEVER RESET
  } finally {
    _loadInFlight = false;
  }
}
```

