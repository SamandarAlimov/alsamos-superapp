# 🐛 ROOT CAUSE FOUND: Provider Recreation Bug

**Date**: 2026-08-03  
**Status**: CONFIRMED BUG - NOT A REGRESSION, A DESIGN FLAW  
**Severity**: CRITICAL - Affects 100% of users on feed and messages

---

## THE BUG

### MessagesProvider (Confirmed Bug)
**Location**: `lib/features/messages/presentation/providers/messages_provider.dart:54-59`

```dart
final messagesProvider =
    StateNotifierProvider.family<MessagesNotifier, MessagesState, String>(
        (ref, convId) {
  final userId = ref.watch(authProvider).user?.id;  // ← BUG HERE!
  return MessagesNotifier(ref, ref.read(messagesRepositoryProvider), convId, userId);
});
```

**Problem**:
- `ref.watch(authProvider)` creates a dependency on authProvider
- When authProvider changes (auth loading → authenticated), messagesProvider is **invalidated and recreated**
- This causes:
  1. Current MessagesNotifier disposed
  2. All loaded messages LOST
  3. Realtime subscription torn down
  4. New MessagesNotifier created
  5. Messages reload from scratch
  6. UI shows loading again

**Timeline**:
```
T+0ms:    User opens chat
T+10ms:   ChatPage builds, messagesProvider created
T+20ms:   MessagesNotifier.load() starts fetching messages
T+50ms:   Auth finishes loading (isLoading: true → false)
T+51ms:   authProvider notifies listeners
T+52ms:   messagesProvider INVALIDATED (dependency changed!)
T+53ms:   MessagesNotifier.dispose() called
T+54ms:   Realtime subscription torn down
T+55ms:   All messages lost from state
T+56ms:   NEW MessagesNotifier created
T+57ms:   load() called AGAIN
T+100ms:  Messages re-fetched from Supabase
```

---

### PostsProvider (NOT Affected)
**Location**: `lib/features/home/presentation/providers/posts_provider.dart:95-97`

```dart
final postsProvider = StateNotifierProvider<PostsNotifier, PostsState>((ref) {
  return PostsNotifier(ref.watch(postsRepositoryProvider));
});
```

**Analysis**: PostsProvider does NOT watch authProvider, so it's NOT affected by auth state changes.

**BUT**: PostsNotifier constructor calls `refresh()` which depends on auth being ready. If posts load before auth completes, they load WITHOUT user-specific data (likes).

---

## WHY THIS BREAKS EVERYTHING

### Messages Scenario:
1. User authenticated and browsing normally
2. Opens a chat → messagesProvider created
3. Messages load successfully
4. User sees chat history
5. **Auth provider refreshes** (token refresh, presence update, any state change)
6. messagesProvider **recreated** → all messages lost
7. **UI goes blank** → loading spinner forever
8. Realtime stops working → new messages don't appear

### Posts Scenario:
1. App starts
2. Auth loading (isLoading==true)
3. Router allows navigation to /home (bug in router redirect)
4. HomePage builds → postsProvider created
5. PostsNotifier.refresh() called immediately
6. fetchPosts() queries Supabase with userId=null
7. Posts load BUT without like status
8. User sees posts but can't tell which they liked
9. **OR**: Posts load before user scrolls, then auth completes, but PostsProvider never re-loads to add like status

---

## THE FIX

### Option 1: Remove authProvider Dependency (RECOMMENDED)
```dart
// BEFORE (BROKEN):
final messagesProvider =
    StateNotifierProvider.family<MessagesNotifier, MessagesState, String>(
        (ref, convId) {
  final userId = ref.watch(authProvider).user?.id;  // ← Creates dependency!
  return MessagesNotifier(ref, ref.read(messagesRepositoryProvider), convId, userId);
});

// AFTER (FIXED):
final messagesProvider =
    StateNotifierProvider.family<MessagesNotifier, MessagesState, String>(
        (ref, convId) {
  final userId = ref.read(authProvider).user?.id;  // ← READ, not WATCH!
  return MessagesNotifier(ref, ref.read(messagesRepositoryProvider), convId, userId);
});
```

**Why This Works**:
- `ref.read()` gets current value WITHOUT creating dependency
- Provider won't be invalidated when authProvider changes
- MessagesNotifier stays alive across auth state changes
- Messages persist in UI
- Realtime subscription stays connected

---

### Option 2: Keep Dependency But Handle Disposal Gracefully
NOT RECOMMENDED - More complex, doesn't solve root cause

---

## VERIFICATION PLAN

1. Change `ref.watch(authProvider)` to `ref.read(authProvider)` in messagesProvider
2. Run `flutter analyze` to check for issues
3. Test scenario:
   - Open app
   - Navigate to chat
   - Wait for messages to load
   - Trigger auth state change (token refresh)
   - Verify messages DON'T disappear
4. Test scenario 2:
   - Open app while logged out
   - Log in
   - Navigate to chat
   - Verify messages load correctly with userId

---

## FILES TO MODIFY

1. `lib/features/messages/presentation/providers/messages_provider.dart`
   - Line 57: Change `ref.watch(authProvider)` → `ref.read(authProvider)`

---

## IMPACT

**Before Fix**:
- Messages randomly disappear
- Chat goes blank during use
- Loading states get stuck
- Realtime stops working
- User has to restart app

**After Fix**:
- Messages stay loaded
- Chat works reliably
- Realtime stays connected
- Smooth user experience

---

## SECONDARY BUG: Router Redirect Race Condition

**Location**: `lib/app/router/app_router.dart:69-71`

```dart
redirect: (context, state) {
  final auth = ref.read(authProvider);
  if (auth.isLoading) return null;  // ← Allows navigation while loading
  //...
}
```

**Problem**: Router allows navigation to authenticated routes while auth is still loading.

**Fix**:
```dart
redirect: (context, state) {
  final auth = ref.read(authProvider);
  if (auth.isLoading) {
    // Stay on current route or go to loading screen
    return state.matchedLocation == AppRoutes.auth ? null : AppRoutes.auth;
  }
  //...
}
```

---

## ROOT CAUSE ANALYSIS

**Why did this bug exist?**
- AI-generated code copied web patterns without understanding Riverpod lifecycle
- `ref.watch()` in provider factory creates implicit dependency
- No one tested auth state changes after initial load
- Code review didn't catch the dependency issue

**How to prevent?**
- Rule: Provider factories should use `ref.read()`, not `ref.watch()`
- Exception: Only use `ref.watch()` if you WANT provider invalidation
- Add tests for provider lifecycle across auth state changes
- Document Riverpod patterns in AGENTS.md

