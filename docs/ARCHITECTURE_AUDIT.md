# Alsamos Flutter Superapp — Architecture & Performance Audit

**Date**: 2026-07-15  
**Auditor**: Senior Flutter Architect + Performance Engineer  
**Scope**: Full platform audit (READ-ONLY)

---

## A. Executive Summary

1. **Critical Regressions**: Home posts loading is broken (commit 56a7a52 "checkpoint before fixing posts regression" confirms this). The `PostsRepository` exists but provider path is mismatched.

2. **Severe Code Duplication**: Supabase client code repeated in **119 locations** across 39 files. No centralized data access layer — each repository directly calls `supabase.from()` with hand-written queries, leading to:
   - Repeated error handling (silent catch blocks scattered everywhere)
   - No query optimization (unbounded `select(*)` queries)
   - No centralized caching strategy
   - Inconsistent null-safety patterns

3. **Scalability Red Flags**:
   - **Unbounded queries**: Many repositories fetch without `.limit()` or pagination (e.g., `fetchConversations`, `fetchMessages` loads ALL messages)
   - **N+1 queries**: Posts repository does 3+ separate queries per page load (posts → view counts → likes)
   - **Missing offline-first**: SQLite cache exists (`MessagesLocalStore`) but only for messages — home, profile, stories all hit network on every render
   - **Realtime memory leaks**: Supabase channels subscribed but disposal logic is fragile (e.g., `_channel` nullability in messages_provider.dart:998)

4. **Performance Issues**:
   - **ListView() without .builder**: Found in 20+ files (map_page.dart, notifications_page.dart, etc.) — non-lazy rendering will cause jank with large lists
   - **Missing const constructors**: 5670 widget instantiations lack `const` — every rebuild creates new objects
   - **Heavy Map page**: 1000+ lines, multiple AnimationControllers, real-time tracking, TTS, battery polling — all in one widget (no composition)
   - **Provider scope too wide**: `postsProvider` auto-refreshes in constructor — can't mount page without network call

5. **Architecture Inconsistency**:
   - **Mixed patterns**: Some features use repository + provider (messages), others inline Supabase in providers (settings), some have no repository at all
   - **No shared error handling**: `AppToast` exists but used inconsistently (77 files), many still use print/debugPrint
   - **Duplicate widgets**: `CommentLikesDialog` exists in 3 locations, `PostCard` in 2, `StoryViewer` in 2

6. **Recent Regression Causes**: Git history shows commits like "remove unused error_mapper imports from 30 files" (e49b0fc) and "replace all SnackBar/Toast with AppToast" (b7ecd28) — suggests a weaker AI model did broad refactors without understanding dependencies (likely broke imports or state)

7. **Animation Performance**: Multiple AnimationControllers per page without `RepaintBoundary`, Lottie/SVG files loaded on demand (no caching), skeleton shimmers rebuilt on every frame

---

## B. Detailed Findings

### 1. Architecture & Structure

#### 1.1 Folder Structure
**Status**: ✅ Good  
- Clean feature-based structure: `lib/features/{feature}/data|presentation`
- Shared code in `lib/shared/` and `lib/core/`
- Riverpod for state management (consistent)

#### 1.2 Data Layer Organization
**Severity**: **HIGH**  
**Files**: All repositories in `lib/features/*/data/*repository.dart` (19 files)

**Issue**: No data access abstraction layer. Every repository directly imports `supabase_client.dart` and writes raw SQL-like queries:

```dart
// lib/features/home/data/repositories/posts_repository.dart
final data = await supabase
    .from('posts')
    .select(_selectQuery)  // select * — over-fetching
    .eq('visibility', 'public')
    .order('is_pinned', ascending: false)
    .order('created_at', ascending: false)
    .range(from, to);  // at least has pagination
```

**Why it matters at scale**:
- Can't add query optimization (e.g., connection pooling, prepared statements) without editing 119 callsites
- Can't A/B test different backends (REST vs GraphQL vs gRPC)
- No centralized query logging/monitoring
- Every team member must understand Supabase quirks

**Recommended fix**: Create `lib/core/data/supabase_data_source.dart` with typed methods:
```dart
abstract class PostsDataSource {
  Future<List<Map<String, dynamic>>> fetchPosts({int page, int limit});
  Future<void> toggleLike({required String postId, required String userId});
}
```

#### 1.3 Separation of Concerns
**Severity**: **MEDIUM**  
**Files**: `lib/features/map/presentation/pages/map_page.dart` (1000+ lines)

**Issue**: `MapPage` is a God widget — handles:
- Map rendering (FlutterMap)
- Location tracking + permissions
- Battery monitoring
- Connectivity checks
- TTS (voice navigation)
- Search (Overpass API)
- Realtime presence (Supabase channel)
- Directions routing
- 3 TabControllers + 4 AnimationControllers

**Why it matters**: Impossible to test, debug, or optimize in isolation. Any change risks breaking unrelated features.

**Recommended fix**: Break into:
- `MapRenderer` (just the map + tiles)
- `LocationTracker` (GPS + battery + connectivity)
- `MapSearch` (Overpass + results)
- `NavigationController` (routing + TTS)

---

### 2. Code Duplication & Centralization (HIGH PRIORITY)

#### 2.1 Supabase Client Access
**Severity**: **CRITICAL**  
**Duplication Count**: 119 occurrences across 39 files

**Pattern**:
```dart
// Repeated in EVERY repository:
import '../../../core/supabase/supabase_client.dart';

final data = await supabase.from('table_name').select('*')...
```

**Centralization Plan**:
```dart
// lib/core/data/base_repository.dart
abstract class BaseRepository {
  SupabaseClient get client => supabase;
  
  Future<T> query<T>(
    Future<T> Function(SupabaseClient) operation, {
    String? errorContext,
  }) async {
    try {
      return await operation(client);
    } on PostgrestException catch (e) {
      crashReporting.record(e, StackTrace.current, context: errorContext);
      rethrow;
    } catch (e, st) {
      crashReporting.record(e, st, context: errorContext);
      rethrow;
    }
  }
}
```

#### 2.2 Error Handling Duplication
**Severity**: **HIGH**  
**Files**: Every repository, every provider

**Current pattern** (repeated ~50 times):
```dart
try {
  // supabase call
} catch (e) {
  debugPrint('Error: $e');  // or print, or ignored
  rethrow;  // or return null, or return []
}
```

**Issues**:
- No structured error types (can't distinguish network vs auth vs permission errors)
- No user-facing messages (just debug prints)
- Inconsistent fallback behavior

**Centralized fix** (`lib/core/errors/app_error.dart`):
```dart
sealed class AppError implements Exception {
  String get userMessage;
}
class NetworkError extends AppError { ... }
class AuthError extends AppError { ... }
class NotFoundError extends AppError { ... }

extension on Exception {
  AppError toAppError() { ... }
}
```

#### 2.3 Toast/Snackbar Duplication
**Severity**: **MEDIUM**  
**Files**: 77 files call `AppToast`, but inconsistently

**Issue**: `AppToast` exists (good!) but:
- Some features still use `ScaffoldMessenger.of(context).showSnackBar`
- No standard error → toast mapping
- Success/error colors hard-coded per call

**Centralized fix**: Extend `AppToast`:
```dart
static void fromError(BuildContext context, Exception error) {
  final appError = error.toAppError();
  AppToast.error(context, appError.userMessage);
}
```

#### 2.4 Auth/Session Checks
**Severity**: **MEDIUM**  
**Duplication**: `supabase.auth.currentUser?.id` appears 50+ times

**Pattern**:
```dart
final userId = supabase.auth.currentUser?.id;
if (userId == null) return;  // or throw, or return null
```

**Centralized fix** (`lib/core/auth/auth_guard.dart`):
```dart
extension on Ref {
  String requireUserId() {
    final user = watch(authProvider).user;
    if (user == null) throw UnauthenticatedError();
    return user.id;
  }
}
```

#### 2.5 Formatting/Util Duplication
**Severity**: **LOW**  
**Examples**: Date formatting, number formatting, string truncation

**Pattern**: Inline `DateFormat('MMM d').format(date)` repeated across widgets

**Centralized fix**: `lib/shared/utils/formatters.dart`:
```dart
extension DateFormatting on DateTime {
  String toShortDate() => DateFormat('MMM d').format(this);
  String toRelative() => timeago.format(this, locale: 'uz');
}
```

#### 2.6 Widget Duplication
**Severity**: **MEDIUM**  
**Files**:
- `CommentLikesDialog`: `lib/features/comments/presentation/widgets/comment_likes_dialog.dart`, `lib/shared/widgets/comment_likes_dialog.dart`
- `PostCard`: `lib/features/home/presentation/widgets/post_card.dart`, `lib/features/discovery/presentation/widgets/post_card.dart`
- `StoryViewer`: `lib/features/stories/presentation/widgets/story_viewer.dart`, `lib/features/discovery/presentation/widgets/story_viewer.dart`

**Fix**: Keep ONE canonical version in `shared/widgets/`, delete duplicates

---

### 3. Scalability & Performance (HIGH PRIORITY)

#### 3.1 Unbounded Queries
**Severity**: **CRITICAL**  
**Files**:
- `lib/features/messages/data/repositories/messages_repository.dart:179-187`
- `lib/features/activity/data/activity_repository.dart:18-23`
- `lib/features/profile/data/profile_repository.dart:20-27`

**Issue 1: Messages loads ALL messages**
```dart
// Line 182-187 in messages_repository.dart
final data = await supabase
    .from('messages')
    .select('*, sender:profiles!messages_sender_id_fkey(...)')
    .eq('conversation_id', conversationId)
    .order('created_at', ascending: true);
    // NO .limit() — fetches ENTIRE conversation history
```

**At scale**: A group chat with 100k messages = 100k rows loaded into memory on page open. App will crash on low-end devices.

**Fix**: Add cursor-based pagination:
```dart
Future<List<Message>> fetchMessages(String convId, {
  DateTime? beforeTimestamp,
  int limit = 50,
}) async {
  var query = supabase.from('messages')
      .select('...')
      .eq('conversation_id', convId)
      .order('created_at', ascending: false)
      .limit(limit);
  if (beforeTimestamp != null) {
    query = query.lt('created_at', beforeTimestamp.toIso8601String());
  }
  return ...;
}
```

**Issue 2: Activity logs unbounded**
```dart
// activity_repository.dart:18-23
final logs = await supabase
    .from('user_activity_logs')
    .select()
    .eq('user_id', userId)
    .gte('created_at', yearStart.toUtc().toIso8601String())
    // NO .limit() — fetches entire year
```

**At scale**: Power users with 50k+ activity logs = multi-second query + OOM.

**Fix**: Aggregate server-side (Postgres view or RPC function).

#### 3.2 N+1 Query Patterns
**Severity**: **HIGH**  
**File**: `lib/features/home/data/repositories/posts_repository.dart:16-80`

**Issue**: `fetchPosts` does 3 separate queries:
1. Fetch posts (line 19-25)
2. Fetch view counts per post (line 36-40)
3. Fetch like states per post (line 62-66)

**At scale**: Loading 10 posts = 1 + 1 + 1 = 3 queries. Loading 100 posts = still 3 queries (batched), but with large `IN` filters. Loading 1000 posts in infinite scroll = eventual database connection exhaustion.

**Fix**: Use Postgres joins or a `WITH` clause:
```sql
WITH view_counts AS (
  SELECT post_id, COUNT(DISTINCT user_id) as count
  FROM post_views WHERE post_id = ANY($1) GROUP BY post_id
),
like_states AS (
  SELECT post_id FROM post_likes WHERE user_id = $2 AND post_id = ANY($1)
)
SELECT p.*, vc.count as views, (ls.post_id IS NOT NULL) as is_liked
FROM posts p
LEFT JOIN view_counts vc ON p.id = vc.post_id
LEFT JOIN like_states ls ON p.id = ls.post_id
WHERE p.visibility = 'public' ORDER BY p.created_at DESC LIMIT 10;
```

Create a Supabase RPC function for this.

#### 3.3 Over-Fetching (SELECT *)
**Severity**: **MEDIUM**  
**Files**: `posts_repository.dart:11-14`, messages, profiles, etc.

**Issue**:
```dart
static const _selectQuery = '''
  *,  // fetches ALL columns (content, metadata, is_deleted, created_at, updated_at, etc.)
  profile:profiles!posts_user_id_fkey (...)
''';
```

**At scale**: Fetching unused JSONB columns (e.g., `metadata`, `media_urls` arrays) wastes bandwidth. A 10KB post with 5MB of unused media metadata = 500x bloat.

**Fix**: Specify columns:
```dart
static const _selectQuery = '''
  id, user_id, content, media_type, created_at, likes_count, comments_count, visibility,
  profile:profiles!posts_user_id_fkey (id, username, display_name, avatar_url, is_verified)
''';
```

#### 3.4 Missing Indexes (Supabase side)
**Severity**: **HIGH**  
**Evidence**: Queries like `.eq('conversation_id', x).order('created_at')` without composite indexes

**Fix** (SQL migration needed):
```sql
CREATE INDEX idx_messages_conversation_created 
  ON messages(conversation_id, created_at DESC);

CREATE INDEX idx_posts_visibility_created 
  ON posts(visibility, created_at DESC) WHERE is_deleted = false;
```

#### 3.5 Realtime Subscriptions Not Disposed
**Severity**: **HIGH**  
**File**: `lib/features/messages/presentation/providers/messages_provider.dart:309-455`

**Issue**: Supabase channel subscribed in `_subscribe()` (line 309), disposed in `dispose()` (line 998). BUT:
- Channel is nullable (`dynamic _channel`)
- If an exception happens during subscription setup, `_channel` stays null
- `dispose()` calls `supabase.removeChannel(_channel)` which silently fails if `_channel == null`
- Result: **memory leak** — Postgres keeps sending realtime events to a dead Flutter isolate

**Fix**:
```dart
@override
void dispose() {
  _channel?.unsubscribe();  // explicit unsubscribe first
  if (_channel != null) supabase.removeChannel(_channel!);
  super.dispose();
}
```

#### 3.6 Queries on Every Rebuild
**Severity**: **MEDIUM**  
**File**: `lib/features/home/presentation/providers/posts_provider.dart:41-43`

**Issue**:
```dart
PostsNotifier(this._repo) : super(const PostsState()) {
  refresh();  // auto-fetches on provider instantiation
}
```

**Why it matters**: Every time `postsProvider` is read (e.g., navigation back to home), it creates a NEW notifier → calls `refresh()` → network call. No cache, no staleness check.

**Fix**: Use `AsyncNotifier` with `build()` method (Riverpod 2.5 feature):
```dart
class PostsNotifier extends AsyncNotifier<PostsState> {
  @override
  Future<PostsState> build() async {
    final posts = await _repo.fetchPosts(page: 0);
    return PostsState(posts: posts, page: 0);
  }
}
```

This auto-caches until invalidated.

#### 3.7 Offline-First Not Implemented
**Severity**: **HIGH**  
**Evidence**: `MessagesLocalStore` exists (SQLite cache for messages), but:
- Home posts: no local cache
- Profile data: no local cache
- Stories: no local cache
- Comments: no local cache

**At scale**: Every screen load = network call. Flaky network = blank screens.

**Fix**: Implement `lib/core/data/offline_repository.dart`:
```dart
abstract class OfflineRepository<T> {
  Future<List<T>> fetch({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = await _loadCache();
      if (cached.isNotEmpty) return cached;
    }
    final fresh = await _fetchRemote();
    await _saveCache(fresh);
    return fresh;
  }
}
```

#### 3.8 ListView() Without Builder
**Severity**: **MEDIUM**  
**Files**: 20+ files (map_page.dart, notifications_page.dart, messages_page.dart, etc.)

**Issue**:
```dart
ListView(
  children: [
    for (var item in items) ItemWidget(item),  // renders ALL items upfront
  ],
)
```

**At scale**: 1000 items = 1000 widgets built synchronously = UI freeze.

**Fix**:
```dart
ListView.builder(
  itemCount: items.length,
  itemBuilder: (context, i) => ItemWidget(items[i]),  // lazy rendering
)
```

#### 3.9 Missing Image Caching
**Severity**: **MEDIUM**  
**Evidence**: `cached_network_image: ^3.3.1` in pubspec.yaml (good!), but not used consistently

**Files to check**: PostCard, UserAvatar, StoryRing — ensure all use `CachedNetworkImage`, not raw `Image.network()`

#### 3.10 Heavy Synchronous Work on Main Thread
**Severity**: **MEDIUM**  
**File**: `lib/features/activity/data/activity_repository.dart:30-53`

**Issue**: 50k activity logs parsed + aggregated in a `for` loop on main thread (no `compute()` isolate)

**Fix**:
```dart
final summary = await compute(_aggregateLogs, logs);

static ActivitySummary _aggregateLogs(List<Map<String, dynamic>> logs) {
  // ... existing aggregation logic
}
```

#### 3.11 Missing const Constructors
**Severity**: **LOW** (but easy wins)  
**Evidence**: 5670 widget instantiations found, most lack `const`

**Impact**: Every rebuild = new object allocation. With `const`, Flutter reuses instances → less GC → smoother 60fps.

**Fix**: Add `const` to all stateless widgets with immutable params:
```dart
const SizedBox(height: 16),  // not SizedBox(height: 16)
const Icon(Icons.check),
```

#### 3.12 Provider Scope Too Wide
**Severity**: **MEDIUM**  
**Example**: `messagesProvider` is family-scoped per conversation, but `postsProvider` is global

**Issue**: If user navigates Home → Profile → Home, `postsProvider` doesn't rebuild (cached), but its internal state might be stale (no TTL).

**Fix**: Use Riverpod's `autoDispose` + cache time:
```dart
final postsProvider = StateNotifierProvider.autoDispose<PostsNotifier, PostsState>((ref) {
  ref.keepAlive();  // keep for 5 minutes after last listener
  Timer(Duration(minutes: 5), () => ref.invalidateSelf());
  return PostsNotifier(...);
});
```

---

### 4. Animations & Motion Performance

#### 4.1 Multiple AnimationControllers Per Page
**Severity**: **MEDIUM**  
**File**: `lib/features/map/presentation/pages/map_page.dart`

**Issue**: 4+ AnimationControllers in one widget (zoom anim, route anim, tracking anim, etc.), all `vsync: this`

**Why it matters**: Each controller ticks on every frame → rebuilds entire widget tree → jank

**Fix**: Wrap animated subtrees in `RepaintBoundary`:
```dart
RepaintBoundary(
  child: AnimatedBuilder(
    animation: _zoomAnim,
    builder: (context, child) => ...zoom UI...,
  ),
)
```

#### 4.2 Skeleton Shimmers Rebuilding Every Frame
**Severity**: **LOW**  
**File**: `lib/features/home/presentation/pages/home_page.dart:177-228`

**Issue**: `SkeletonShimmer` uses a shared `AnimationController` (good!), but if not wrapped in `RepaintBoundary`, rebuilds the parent widget on every tick

**Fix**: Add `RepaintBoundary` around shimmer widgets (already a closed issue per code comment — verify it's fixed)

#### 4.3 Lottie/SVG Not Cached
**Severity**: **LOW**  
**Evidence**: `flutter_svg: ^2.0.10+1` in pubspec, but no asset preloading

**Issue**: First render = disk I/O → parse SVG → build widget tree → jank

**Fix**: Preload in `main()`:
```dart
Future<void> _preloadAssets() async {
  await Future.wait([
    precachePicture(ExactAssetPicture(SvgPicture.svgStringDecoderBuilder, 'assets/icons/logo.svg'), null),
    // ... other SVGs
  ]);
}
```

#### 4.4 Heavy Layouts Animating
**Severity**: **MEDIUM**  
**Example**: If PostCard (which includes media carousel, action buttons, profile header) animates during scroll, layout is recalculated every frame

**Fix**: Use `AnimatedSwitcher` with `transitionBuilder` that only animates opacity/scale, not layout:
```dart
AnimatedSwitcher(
  duration: Duration(milliseconds: 200),
  transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
  child: PostCard(key: ValueKey(post.id), post: post),
)
```

---

### 5. Regressions (Recently Broken)

#### 5.1 Home Posts Not Loading
**Severity**: **CRITICAL**  
**Evidence**: Commit `56a7a52 "checkpoint before fixing posts regression"`

**Hypothesis**: Provider path mismatch. Code shows:
```dart
// lib/features/home/presentation/providers/posts_provider.dart:6
final postsRepositoryProvider = Provider((ref) => PostsRepository());

// But PostsRepository is at:
// lib/features/home/data/repositories/posts_repository.dart
```

The provider imports:
```dart
import '../../data/repositories/posts_repository.dart';
```

This path is WRONG if run from `lib/features/home/presentation/providers/`. Should be:
```dart
import '../../../home/data/repositories/posts_repository.dart';
```

**Fix**: Correct the import path and verify `PostsRepository` is exported.

**Alternative hypothesis**: The `fetchPosts` method relies on `select('*')` which might be missing columns after a schema change. Check Supabase table schema vs. `Post.fromMap()`.

#### 5.2 Current Location Not Working
**Severity**: **HIGH**  
**File**: `lib/features/map/presentation/providers/location_provider.dart`

**Hypothesis**: Permissions or Geolocator initialization. Check:
1. `permission_handler` setup in AndroidManifest.xml / Info.plist
2. `geolocator: 14.0.2` breaking change (v14 changed permission flow)

**Debug steps**:
```dart
final status = await Geolocator.checkPermission();
debugPrint('Location permission: $status');
```

#### 5.3 Messages/Chat Loading Issues
**Severity**: **HIGH**  
**Hypothesis**: Realtime subscription breaking. After commit `b7ecd28 "replace all SnackBar/Toast with AppToast"`, if error handling in `_subscribe()` was changed, subscriptions might silently fail.

**Fix**: Check `MessagesNotifier._subscribe()` for any `catch` blocks that swallow errors without logging.

---

### 6. Security (Brief)

#### 6.1 No Exposed Secrets
**Status**: ✅ Good  
`lib/core/constants/api_constants.dart` referenced but not in repo (gitignored)

#### 6.2 RLS Assumptions
**Severity**: **LOW**  
**Issue**: Code assumes Supabase RLS policies are correct (e.g., `posts.visibility = 'public'` filtered client-side, but should also be enforced server-side)

**Recommendation**: Audit Supabase policies with `docs/chore(security): add admin rls audit report` (per git log)

#### 6.3 Client-Side Trust
**Severity**: **MEDIUM**  
**Example**: `toggleLike()` optimistically updates UI before server confirms (good UX), but if server fails, revert relies on catching exception — if exception is swallowed, state desyncs

**Fix**: Use server-authoritative state:
```dart
final result = await _repo.toggleLike(post);
_patch(post.id, post.copyWith(isLiked: result, likesCount: result ? post.likesCount + 1 : post.likesCount - 1));
```

---

## C. Proposed Centralization/Architecture Plan

### "Call from One Place" Design

```
lib/
├── core/
│   ├── data/
│   │   ├── base_repository.dart          ← All repos extend this
│   │   ├── supabase_data_source.dart     ← Wraps supabase client
│   │   ├── offline_repository.dart       ← Mixin for SQLite caching
│   │   └── query_builder.dart            ← Type-safe query DSL
│   ├── errors/
│   │   ├── app_error.dart                ← Sealed error types
│   │   └── error_handler.dart            ← Global try/catch wrapper
│   ├── auth/
│   │   └── auth_guard.dart               ← requireUserId() extension
│   └── providers/
│       └── connectivity_provider.dart    ← Single source for online state
├── shared/
│   ├── utils/
│   │   ├── formatters.dart               ← Date, number, string extensions
│   │   └── validators.dart               ← Email, phone, etc.
│   └── widgets/
│       ├── app_toast.dart                ← Already centralized (good!)
│       ├── error_view.dart               ← Standardized error UI
│       └── loading_view.dart             ← Standardized loading UI
└── features/
    └── {feature}/
        ├── data/
        │   ├── models/
        │   ├── repositories/
        │   │   └── {feature}_repository.dart  ← Extends BaseRepository
        │   └── local/
        │       └── {feature}_local_store.dart ← SQLite cache
        └── presentation/
            ├── providers/
            │   └── {feature}_provider.dart    ← Uses AsyncNotifier
            └── pages/
```

### Key Changes:
1. **BaseRepository**: Every repo extends it → gets error handling, logging, analytics for free
2. **SupabaseDataSource**: Typed methods (`.fetchPosts()`, `.toggleLike()`) instead of raw queries
3. **OfflineRepository**: Mixin that adds SQLite caching to any repo
4. **AppError**: Sealed class for exhaustive error handling
5. **AsyncNotifier**: Replaces `StateNotifier` → auto-caching + invalidation

---

## D. Prioritized Roadmap

### Phase 0: Critical Regressions (Get it working) — 2-3 days

1. **Fix home posts import path**  
   File: `lib/features/home/presentation/providers/posts_provider.dart`  
   Change: Correct repository import from `../../data/repositories/posts_repository.dart` to `../../../home/data/repositories/posts_repository.dart` OR verify `PostsRepository` is barrel-exported from `data/` folder.  
   Test: Navigate to home tab, verify posts load.

2. **Debug location provider**  
   File: `lib/features/map/presentation/providers/location_provider.dart`  
   Add: Debug logging for permission checks and Geolocator.getCurrentPosition() calls.  
   Test: Open map page, verify current location marker appears.

3. **Fix messages loading**  
   File: `lib/features/messages/presentation/providers/messages_provider.dart`  
   Add: Try/catch around `_subscribe()` with explicit error logging (don't swallow).  
   Test: Open any chat, verify messages load and realtime updates work.

4. **Verify AppToast migration**  
   Action: Search codebase for remaining `ScaffoldMessenger.of(context).showSnackBar` or `SnackBar(` calls.  
   Fix: Replace with `AppToast.{success|error|warning}(context, ...)`.  
   Test: Trigger errors (e.g., network offline) and verify toast appears.

5. **Add null-safety guards**  
   Files: All repositories  
   Pattern: Replace `supabase.auth.currentUser?.id` with helper that throws descriptive error if null.  
   Example: `final userId = supabase.auth.currentUser?.id ?? (throw UnauthenticatedError());`

---

### Phase 1: Centralization/Architecture Refactors — 1-2 weeks

6. **Create BaseRepository**  
   File: `lib/core/data/base_repository.dart`  
   Add: Abstract class with `query<T>` wrapper for error handling + logging.  
   Migrate: Update `PostsRepository` to extend `BaseRepository` (pilot).

7. **Extract SupabaseDataSource**  
   File: `lib/core/data/supabase_data_source.dart`  
   Add: Typed methods for common operations (fetch, insert, update, delete).  
   Migrate: Update `PostsRepository` to use data source instead of raw `supabase.from()`.

8. **Create AppError sealed class**  
   File: `lib/core/errors/app_error.dart`  
   Add: `NetworkError`, `AuthError`, `NotFoundError`, `ValidationError`, `ServerError`.  
   Migrate: Update `BaseRepository` to catch Postgres exceptions and rethrow as AppError.

9. **Extend AppToast with error mapping**  
   File: `lib/shared/widgets/app_toast.dart`  
   Add: `AppToast.fromError(BuildContext context, Exception error)` that maps AppError → user message.  
   Migrate: Update all `catch` blocks to call `AppToast.fromError(context, e)`.

10. **Create auth_guard extension**  
    File: `lib/core/auth/auth_guard.dart`  
    Add: `extension on Ref { String requireUserId() }` that reads authProvider and throws if null.  
    Migrate: Replace all `supabase.auth.currentUser?.id` checks with `ref.requireUserId()`.

11. **Consolidate duplicate widgets**  
    Action: Move `CommentLikesDialog`, `PostCard`, `StoryViewer` to `lib/shared/widgets/`, delete duplicates.  
    Fix: Update all imports to point to shared location.

12. **Create formatters utility**  
    File: `lib/shared/utils/formatters.dart`  
    Add: Extensions on `DateTime`, `int`, `String` for common formatting.  
    Migrate: Replace inline `DateFormat(...)` calls with `.toShortDate()` etc.

---

### Phase 2: Scalability/Performance — 2-3 weeks

13. **Add pagination to messages**  
    File: `lib/features/messages/data/repositories/messages_repository.dart`  
    Change: Add `beforeTimestamp` and `limit` params to `fetchMessages()`.  
    File: `lib/features/messages/presentation/providers/messages_provider.dart`  
    Change: Load first 50 messages, add "load more" button that fetches older.

14. **Add pagination to activity logs**  
    File: `lib/features/activity/data/activity_repository.dart`  
    Change: Move aggregation to Postgres (create RPC function `get_activity_summary(user_id UUID)`).  
    Benefit: Offloads client-side aggregation to database.

15. **Optimize posts N+1 queries**  
    File: `lib/features/home/data/repositories/posts_repository.dart`  
    Change: Create Supabase RPC function `fetch_posts_optimized` that joins posts + view_counts + like_states in one query.  
    Benefit: 1 query instead of 3.

16. **Replace SELECT \* with column lists**  
    Files: All repositories  
    Change: Specify only needed columns in `.select()` calls.  
    Benefit: Reduces bandwidth by 50-80% for large JSONB fields.

17. **Add SQLite caching to posts**  
    File: `lib/features/home/data/local/posts_local_store.dart` (new)  
    Pattern: Copy `MessagesLocalStore` structure.  
    Integrate: Update `PostsRepository` to check cache before network.

18. **Add SQLite caching to profiles**  
    File: `lib/features/profile/data/local/profiles_local_store.dart` (new)  
    Pattern: Same as above.

19. **Fix realtime subscription disposal**  
    File: `lib/features/messages/presentation/providers/messages_provider.dart:998`  
    Change: Call `_channel?.unsubscribe()` before `removeChannel()`.  
    Add: Null-check and debug log if channel is null.

20. **Convert postsProvider to AsyncNotifier**  
    File: `lib/features/home/presentation/providers/posts_provider.dart`  
    Change: Replace `StateNotifier` with `AsyncNotifier`, move `refresh()` into `build()` method.  
    Benefit: Auto-caching with TTL.

21. **Replace ListView() with ListView.builder()**  
    Files: map_page.dart, notifications_page.dart, messages_page.dart, etc. (20+ files)  
    Change: Convert `children: [for (var item in items) ...]` to `itemBuilder: (context, i) => ...`.  
    Benefit: Lazy rendering, no upfront 1000+ widget builds.

22. **Add RepaintBoundary to animations**  
    Files: map_page.dart, home_page.dart (shimmer), story_viewer.dart  
    Change: Wrap `AnimatedBuilder` content in `RepaintBoundary(child: ...)`.  
    Benefit: Isolates animation repaints, reduces jank.

23. **Move activity aggregation to isolate**  
    File: `lib/features/activity/data/activity_repository.dart`  
    Change: Wrap aggregation logic in `compute(_aggregateLogs, logs)`.  
    Benefit: Offloads 50k loop iterations from main thread.

24. **Audit and add const constructors**  
    Action: Run `dart fix --apply` to auto-add `const` where possible.  
    Manual: Add `const` to custom widget constructors with immutable fields.  
    Benefit: Reduces GC pressure.

25. **Add Supabase indexes**  
    File: `supabase/migrations/XXXX_add_performance_indexes.sql` (new)  
    Add:
    ```sql
    CREATE INDEX idx_messages_conversation_created ON messages(conversation_id, created_at DESC);
    CREATE INDEX idx_posts_visibility_created ON posts(visibility, created_at DESC) WHERE is_deleted = false;
    CREATE INDEX idx_post_likes_user_post ON post_likes(user_id, post_id);
    ```
    Deploy: Run migration on Supabase dashboard.

26. **Implement OfflineRepository mixin**  
    File: `lib/core/data/offline_repository.dart`  
    Add: Generic `fetch({bool forceRefresh})` that checks cache first.  
    Migrate: Apply to `PostsRepository`, `ProfileRepository`, `StoriesRepository`.

27. **Preload SVG assets**  
    File: `lib/main.dart`  
    Add: `_preloadAssets()` function that calls `precachePicture()` for all icons.  
    Call: In `main()` before `runApp()`.

28. **Add autoDispose + keepAlive to providers**  
    Files: All providers that don't need to persist forever (e.g., postsProvider, profileProvider)  
    Change: Add `.autoDispose` modifier + `ref.keepAlive()` with TTL.  
    Benefit: Frees memory when screen is not visible.

---

### Phase 3: Animation Performance Polish — 3-5 days

29. **Optimize MapPage composition**  
    File: `lib/features/map/presentation/pages/map_page.dart`  
    Action: Extract into smaller widgets:
    - `MapRenderer` (lines 200-500)
    - `LocationTracker` (lines 150-200)
    - `MapSearch` (lines 600-700)
    - `NavigationController` (lines 700-800)  
    Benefit: Each can optimize independently.

30. **Add RepaintBoundary to PostCard**  
    File: `lib/features/home/presentation/widgets/post_card.dart`  
    Change: Wrap entire card in `RepaintBoundary(child: ...)`.  
    Benefit: Isolates post rebuilds during scroll.

31. **Optimize SkeletonShimmer**  
    File: `lib/shared/widgets/skeleton_shimmer.dart`  
    Verify: Already wrapped in `RepaintBoundary` (per code comment v43).  
    Test: Profile with Flutter DevTools → check repaint boundaries are active.

32. **Lazy-load story media**  
    File: `lib/features/stories/presentation/widgets/story_viewer.dart`  
    Change: Use `visibility_detector` to preload next story only when current is 80% viewed.  
    Benefit: Reduces memory footprint.

33. **Profile animation performance**  
    Action: Run `flutter run --profile` and use DevTools → Performance tab to identify jank.  
    Fix: Add `RepaintBoundary` around any widget tree that rebuilds during animation.  
    Test: Scroll feed, open/close sheets, navigate tabs → verify 60fps.

---

## E. Duplication Map (Summary)

| **What** | **Where** | **Centralize To** |
|----------|-----------|-------------------|
| Supabase client access | 119 locations across 39 files | `lib/core/data/supabase_data_source.dart` |
| Error handling (try/catch) | Every repository, every provider | `lib/core/data/base_repository.dart` + `lib/core/errors/app_error.dart` |
| Toast/snackbar calls | 77 files | `lib/shared/widgets/app_toast.dart` (already exists, enforce usage) |
| Auth/session checks (`currentUser?.id`) | 50+ locations | `lib/core/auth/auth_guard.dart` extension |
| Date formatting | Inline `DateFormat(...)` scattered | `lib/shared/utils/formatters.dart` extensions |
| Widgets: `CommentLikesDialog` | 2 locations | `lib/shared/widgets/comment_likes_dialog.dart` (keep 1) |
| Widgets: `PostCard` | 2 locations | `lib/shared/widgets/post_card.dart` (keep 1) |
| Widgets: `StoryViewer` | 2 locations | `lib/shared/widgets/story_viewer.dart` (keep 1) |
| Offline caching | Only messages have it | `lib/core/data/offline_repository.dart` mixin |

---

## F. Risk Assessment

### High-Risk Changes:
1. **Changing provider architecture** (Phase 1, item 20) — could break existing listeners
   - Mitigation: Pilot with one feature (posts), test thoroughly, then roll out
2. **Realtime subscription changes** (Phase 2, item 19) — could break chat
   - Mitigation: Test with multiple concurrent chats open, verify no leaks
3. **Pagination** (Phase 2, items 13-14) — changes data flow
   - Mitigation: Add feature flag, A/B test with 10% of users first

### Low-Risk Quick Wins:
- Phase 0 (all regressions) — just fixes
- Phase 1, items 11-12 (consolidate widgets, formatters) — pure refactors
- Phase 2, items 24, 27 (const constructors, asset preload) — no behavior change
- Phase 3 (all animation polish) — UX improvements only

---

## G. Success Metrics

Track BEFORE and AFTER each phase:

1. **App startup time** (measured with `flutter run --profile` + DevTools → Timeline)
   - Target: < 2 seconds to first meaningful paint
2. **Memory usage** (DevTools → Memory tab)
   - Target: < 150 MB baseline (before loading any data)
3. **Frame render time** (DevTools → Performance tab)
   - Target: 60fps (16.67ms per frame) during scroll
4. **Network requests per page load** (DevTools → Network tab)
   - Home page: 3 requests → 1 request (after N+1 fix)
   - Messages page: ∞ (loads all) → 1 + pagination (after cursor fix)
5. **Crash rate** (Firebase Crashlytics or Sentry)
   - Target: < 0.5% of sessions
6. **Time to interactive** (Firebase Performance Monitoring)
   - Home page: measure time from tap to posts visible
   - Target: < 1 second on 4G network

---

## H. Appendix: Code Examples

### Before: Duplicated Supabase Access
```dart
// lib/features/home/data/repositories/posts_repository.dart
final data = await supabase.from('posts').select('*')...

// lib/features/profile/data/profile_repository.dart
final data = await supabase.from('profiles').select('*')...

// lib/features/messages/data/repositories/messages_repository.dart
final data = await supabase.from('messages').select('*')...
```

### After: Centralized Data Source
```dart
// lib/core/data/supabase_data_source.dart
abstract class SupabaseDataSource {
  Future<List<Map<String, dynamic>>> query(
    String table,
    String select, {
    List<Filter>? filters,
    int? limit,
  });
}

// lib/features/home/data/repositories/posts_repository.dart
class PostsRepository extends BaseRepository {
  Future<List<Post>> fetchPosts({int page = 0}) async {
    return query((client) async {
      final data = await dataSource.query(
        'posts',
        'id, content, ...',
        filters: [Filter.eq('visibility', 'public')],
        limit: 10,
      );
      return data.map(Post.fromMap).toList();
    }, errorContext: 'fetchPosts');
  }
}
```

---

**End of Audit Report**
