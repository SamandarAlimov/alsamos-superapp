# Supabase Schema Reference - Project mbhjganbihamoiqmankv

**Generated:** 2026-07-12  
**Source:** Live schema introspection  
**Purpose:** Single source of truth for Flutter app alignment

---

## Critical Tables for Flutter

### posts
| Column | Type | Nullable | Default |
|--------|------|----------|---------|
| id | uuid | NO | gen_random_uuid() |
| user_id | uuid | NO | - |
| content | text | YES | - |
| media_urls | text[] | YES | '{}' |
| media_type | text | YES | 'text' |
| likes_count | integer | YES | 0 |
| comments_count | integer | YES | 0 |
| shares_count | integer | YES | 0 |
| bookmarks_count | integer | YES | 0 |
| is_pinned | boolean | YES | false |
| visibility | text | YES | 'public' |
| created_at | timestamptz | YES | now() |
| updated_at | timestamptz | YES | now() |
| reposts_count | integer | NO | 0 |
| channel_id | uuid | YES | - |
| views_count | integer | NO | 0 |

**MISSING COLUMNS (Flutter assumed these exist but they DON'T):**
- ❌ source_type
- ❌ poll_data
- ❌ tags
- ❌ location
- ❌ mentioned_users
- ❌ thumbnail_url
- ❌ video_duration

### conversation_participants
| Column | Type | Nullable | Default |
|--------|------|----------|---------|
| id | uuid | NO | gen_random_uuid() |
| conversation_id | uuid | NO | - |
| user_id | uuid | NO | - |
| role | text | YES | 'member' |
| is_muted | boolean | YES | false |
| last_read_at | timestamptz | YES | now() |
| joined_at | timestamptz | YES | now() |
| is_pinned | boolean | YES | false |
| is_archived | boolean | YES | false |
| is_request | boolean | NO | false |

**MISSING COLUMNS:**
- ❌ mute_until (Flutter assumed this exists)

### user_settings
| Column | Type | Nullable | Default |
|--------|------|----------|---------|
| id | uuid | NO | gen_random_uuid() |
| user_id | uuid | NO | - |
| last_seen_visibility | text | YES | 'everyone' |
| read_receipts_enabled | boolean | YES | true |
| call_permissions | text | YES | 'everyone' |
| group_invite_permissions | text | YES | 'everyone' |
| two_factor_enabled | boolean | YES | false |
| notification_sounds | boolean | YES | true |
| notification_preview | boolean | YES | true |
| theme | text | YES | 'system' |
| language | text | YES | 'en' |
| created_at | timestamptz | NO | now() |
| updated_at | timestamptz | NO | now() |
| notify_likes | boolean | YES | true |
| notify_comments | boolean | YES | true |
| notify_follows | boolean | YES | true |
| notify_mentions | boolean | YES | true |
| autoplay_voice_messages | boolean | YES | true |
| autoplay_video_messages | boolean | YES | true |

**MISSING COLUMNS:**
- ❌ search_safe_mode (Flutter assumed this exists)

### profiles
| Column | Type | Nullable | Default |
|--------|------|----------|---------|
| id | uuid | NO | - |
| username | text | YES | - |
| display_name | text | YES | - |
| avatar_url | text | YES | - |
| cover_url | text | YES | - |
| bio | text | YES | - |
| website | text | YES | - |
| is_verified | boolean | YES | false |
| is_online | boolean | YES | false |
| last_seen | timestamptz | YES | now() |
| followers_count | integer | YES | 0 |
| following_count | integer | YES | 0 |
| posts_count | integer | YES | 0 |
| created_at | timestamptz | YES | now() |
| updated_at | timestamptz | YES | now() |
| country | text | YES | - |
| birth_date | date | YES | - |
| location | text | YES | - |
| user_id | uuid | YES | - |
| preferences | jsonb | YES | default obj |
| signatures | jsonb | YES | '[]' |
| email_filters | jsonb | YES | '[]' |
| notification_preferences | jsonb | YES | default obj |
| **is_admin** | **boolean** | **NO** | **false** |

**KEY:** profiles.is_admin EXISTS ✅

### products
| Column | Type | Nullable | Default |
|--------|------|----------|---------|
| id | uuid | NO | gen_random_uuid() |
| seller_id | uuid | NO | - |
| category_id | uuid | YES | - |
| **title** | **text** | **NO** | - |
| **description** | **text** | YES | - |
| **price** | **numeric** | **NO** | - |
| compare_at_price | numeric | YES | - |
| currency | text | YES | 'USD' |
| quantity | integer | YES | 1 |
| sku | text | YES | - |
| condition | text | YES | 'new' |
| location | text | YES | - |
| shipping_available | boolean | YES | true |
| shipping_price | numeric | YES | 0 |
| is_negotiable | boolean | YES | false |
| is_featured | boolean | YES | false |
| status | text | YES | 'active' |
| views_count | integer | YES | 0 |
| likes_count | integer | YES | 0 |
| created_at | timestamptz | NO | now() |
| updated_at | timestamptz | NO | now() |

**KEY:** title, description, price all exist ✅

### user_roles
| Column | Type | Nullable | Default |
|--------|------|----------|---------|
| id | uuid | NO | gen_random_uuid() |
| user_id | uuid | NO | - |
| role | app_role (enum) | NO | - |
| created_at | timestamptz | YES | now() |
| granted_by | uuid | YES | - |

**ENUM:** app_role = 'admin' | 'moderator' | 'user'  
**KEY:** Table EXISTS ✅

---

## All Tables (Alphabetical)

1. ad_clicks
2. ad_impressions
3. ad_reach
4. admin_actions
5. ads
6. ai_conversations
7. ai_preferences
8. blocked_users
9. call_history
10. call_participants
11. cart_items
12. channel_invite_links
13. channel_join_requests
14. channel_members
15. channels
16. comment_likes
17. comments
18. conversation_participants
19. conversations
20. daily_routes
21. download_events
22. drafts
23. emails
24. follows
25. frequent_places
26. labels
27. link_previews
28. live_stream_comments
29. live_stream_reactions
30. live_stream_viewers
31. live_streams
32. location_history
33. mailbox_aliases
34. message_deletions
35. message_delivery_receipts
36. message_drafts
37. message_edit_history
38. message_reactions
39. message_reads
40. message_reports
41. messages
42. mini_apps
43. notifications
44. order_items
45. orders
46. pinned_messages
47. post_collaborators
48. post_likes
49. post_views
50. posts
51. product_categories
52. product_images
53. product_likes
54. product_messages
55. product_reviews
56. products
57. profiles
58. reposts
59. scheduled_emails
60. scheduled_messages
61. sellers
62. stories
63. story_highlight_items
64. story_highlights
65. story_views
66. transactions
67. typing_indicators
68. user_activity_logs
69. user_blocks
70. user_privacy_exceptions
71. user_push_tokens
72. user_roles
73. user_sessions
74. user_settings
75. verification_requests
76. video_calls
77. wallets

---

## Key RPCs (Functions)

- `has_role(_user_id uuid, _role app_role)` → boolean
- `is_conversation_participant(_conversation_id uuid, _user_id uuid)` → boolean
- `is_channel_member(_channel_id uuid, _user_id uuid)` → boolean
- `is_channel_admin(_channel_id uuid, _user_id uuid)` → boolean
- `can_view_presence(target_user_id uuid)` → boolean
- `can_dm_user(p_sender_id uuid, p_recipient_id uuid)` → boolean
- `block_user(_target uuid, _reason text)` → jsonb
- `unblock_user(_target uuid)` → jsonb
- `report_content(...)` → jsonb
- `process_marketplace_order(...)` → jsonb
- `grant_admin_role(target_user_id uuid)` → boolean
- `revoke_admin_role(target_user_id uuid)` → boolean

---

## Critical Mismatches (Flutter must fix)

### 1. posts table
Flutter selects: `source_type`, `poll_data`, `tags`, `location`, `mentioned_users`, `thumbnail_url`, `video_duration`  
**Reality:** NONE of these columns exist.  
**Fix:** Remove all references to these columns.

### 2. user_settings table
Flutter selects: `search_safe_mode`  
**Reality:** Column does NOT exist.  
**Fix:** Remove all references to `search_safe_mode`.

### 3. conversation_participants table
Flutter selects: `mute_until`  
**Reality:** Column does NOT exist (only `is_muted` boolean exists).  
**Fix:** Replace `mute_until` logic with `is_muted`.

### 4. Admin system
Flutter has mixed implementation using both `profiles.is_admin` and `user_roles`.  
**Reality:** BOTH exist in schema.  
**Fix:** Standardize on `profiles.is_admin` for simple checks (it exists and is indexed).

---

## Next Steps

1. ✅ Schema reference created
2. ⏳ Audit all Flutter `.from()` / `.select()` calls
3. ⏳ Fix all column mismatches
4. ⏳ Update Dart models to be null-safe
5. ⏳ Test app launch without 42703 errors
