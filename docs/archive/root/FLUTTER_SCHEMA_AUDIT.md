# Flutter Supabase Schema Audit

**Purpose**: Document all Supabase queries in Flutter app to compare against REAL schema  
**Project**: mbhjganbihamoiqmankv.supabase.co  
**Status**: AWAITING SCHEMA INTROSPECTION OUTPUT

---

## Tables Referenced in Flutter

### Core Tables
- `profiles` - User profiles with avatar, display_name, username, is_verified, is_admin, role, cover_url
- `posts` - Main content posts
- `post_likes` - Post like tracking
- `post_views` - Post view tracking
- `bookmarks` - User bookmarks
- `notifications` - User notifications
- `user_roles` - Admin role tracking
- `verification_requests` - Verification request system

### Messaging
- `conversations` - Message conversations
- `messages` - Individual messages
- `conversation_participants` - Participants in conversations
- `message_reactions` - Reactions to messages
- `message_deliveries` - Message delivery tracking
- `message_attachments` - Media attachments (storage bucket)

### Community & Social
- `channels` - Community channels
- `channel_members` - Channel membership
- `channel_invite_links` - Channel invite system
- `comments` - Post comments
- `hashtags` - Hashtag system
- `user_settings` - User preferences

### Commerce
- `products` - Marketplace products
- `product_images` - Product media
- `orders` - Order tracking
- `order_items` - Order line items
- `shipping_addresses` - User shipping addresses
- `ads` - Advertisement system

### AI & Content
- `ai_conversations` - AI chat history
- `ai_messages` - Individual AI messages

### Location & Discovery
- (Map/location tables to be identified)

---

## Known 42703 Errors (Column Does Not Exist)

### High Priority (Blocking Features)
1. **`user_settings.search_safe_mode`** - Search feature broken
2. **`posts.source_type`** - Post rendering incomplete
3. **`posts.poll_data`** - Poll feature broken
4. **`posts.tags`** - Tag search not working
5. **`posts.location`** - Location features broken
6. **`posts.mentioned_users`** - Mention system broken
7. **`posts.thumbnail_url`** - Video thumbnails missing
8. **`posts.video_duration`** - Video metadata missing
9. **`conversation_participants.mute_until`** - Mute feature broken
10. **`products.description`** - Product detail pages broken
11. **`products.title`** - Product listings broken
12. **`products.price`** - Pricing display broken

---

## RPC Functions Called from Flutter

### Authentication & User Management
- `get_email_for_identifier(_identifier)` - Email lookup for login
- `can_dm_user(p_sender_id, p_recipient_id)` - DM permission check
- `get_visible_presence(target_user_id)` - Online status check

### Messaging
- `search_visible_messages(p_user_id, p_query, ...)` - Message search
- `can_send_message_to_conversation(p_conversation_id, p_sender_id)` - Send permission
- `create_video_call(p_conversation_id, p_call_type)` - Video call creation
- `get_unread_conversation_count(p_user_id)` - Unread badge count
- `mark_conversation_read(p_conversation_id, p_user_id)` - Mark read

### Discovery & Feed
- `get_personalized_feed(...)` - Main feed algorithm
- `increment_post_shares(post_id)` - Share tracking

### Search
- `search_tags(search_term)` - Hashtag search (NEW, may not exist yet)

---

## Select Queries by Feature

### Posts Repository
```dart
// lib/features/home/data/repositories/posts_repository.dart
.from('posts')
.select('''
  *, 
  profile:profiles!posts_user_id_fkey(
    id, username, avatar_url, display_name, is_verified
  )
''')
```

**Columns assumed to exist in `posts`**:
- Standard: id, user_id, content, media_urls, media_type, created_at, updated_at
- Visibility: visibility, is_pinned
- Engagement: like_count, comment_count, share_count, view_count
- **MISSING (42703)**: source_type, poll_data, tags, location, mentioned_users, thumbnail_url, video_duration

### Admin Repository
```dart
// lib/features/admin/data/admin_repository.dart
.from('user_roles')
.select('role')
.eq('user_id', userId)
.eq('role', 'admin')

.from('verification_requests')
.select('*, profile:profiles!verification_requests_user_id_fkey(username, display_name, avatar_url, is_verified)')
```

**Tables**: user_roles, verification_requests  
**Status**: Unknown if these tables exist or if admin is checked via `profiles.is_admin` instead

### Search Repository
```dart
// lib/features/search/data/search_repository.dart
.from('posts')
.select('*, profile:profiles!posts_user_id_fkey(...)')
.textSearch('content', query)

.from('products')
.select('*')
.ilike('title', '%$term%')

.rpc('search_tags', params: {'search_term': term})
```

**Issues**:
- Posts query may fail if missing columns
- Products query references `title` - verify exists
- `search_tags` RPC may not exist yet (from new migration)

### Messages Repository
```dart
// lib/features/messages/data/repositories/messages_repository.dart
.from('conversations')
.select('*, participants:conversation_participants(...)')

.from('messages')
.select('*, sender:profiles!messages_sender_id_fkey(...)')

.from('conversation_participants')
.select('*, profile:profiles!conversation_participants_user_id_fkey(...)')

.rpc('search_visible_messages', params: {...})
.rpc('can_send_message_to_conversation', params: {...})
.rpc('can_dm_user', params: {...})
```

**Known Issue**: `conversation_participants.mute_until` missing (42703)

### Channels Repository
```dart
// lib/features/channels/data/channels_repository.dart
.from('channels')
.select()

.from('channel_members')
.select('channel_id, role')

.from('channel_invite_links')
.select('*')
```

**Status**: Unknown column structure

### User Settings
```dart
// Likely queries user_settings table
// Known issue: search_safe_mode column missing
```

---

## Storage Buckets Used

1. **`message-attachments`** - Used for:
   - Message media
   - Profile avatars
   - Profile cover photos
   - Ad images
   - (Appears to be a catch-all bucket)

**Note**: This naming suggests web app used this bucket for messages; Flutter reuses it for all media.

---

## Foreign Key Relationships Assumed

### Posts
- `posts.user_id` → `profiles.id` (as `posts_user_id_fkey`)

### Messages
- `messages.sender_id` → `profiles.id` (as `messages_sender_id_fkey`)
- `messages.conversation_id` → `conversations.id`
- `conversation_participants.user_id` → `profiles.id`
- `conversation_participants.conversation_id` → `conversations.id`

### Verification
- `verification_requests.user_id` → `profiles.id` (as `verification_requests_user_id_fkey`)

### Admin
- `user_roles.user_id` → `profiles.id` (as `user_roles_user_id_fkey`)

---

## Next Steps

1. **Run INTROSPECT_SCHEMA_NOW.sql** in Supabase SQL Editor
2. **Capture output** and save as `SCHEMA_INTROSPECTION_OUTPUT.txt`
3. **Create SUPABASE_SCHEMA_REFERENCE.md** from output
4. **Compare** this audit against real schema
5. **Fix mismatches**:
   - Rename columns Flutter uses incorrectly
   - Remove selects for non-existent columns
   - Add null-tolerance to models
   - Identify truly missing columns (if web has them)
6. **Remove conflicting migrations** that assume wrong schema
7. **Verify** no 42703 errors remain

---

## Questions to Answer from Schema

- Does `user_roles` table exist, or is admin tracked via `profiles.is_admin`?
- Does `posts` table have: source_type, poll_data, tags, location, mentioned_users, thumbnail_url, video_duration?
- Does `conversation_participants` have `mute_until`?
- Does `products` table have: title, description, price (and what are the real names)?
- What is the real structure of `user_settings`?
- Which RPC functions actually exist in the database?
- Are there tables/columns the web uses that Flutter doesn't know about?

---

**Status**: ⏸️ BLOCKED - Awaiting schema introspection output from user
