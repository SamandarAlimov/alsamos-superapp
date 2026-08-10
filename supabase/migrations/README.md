# Alsamos Supabase Migrations

This directory contains SQL migration scripts for the Alsamos superapp database schema.

## Migration: 20260711_settings_backend_columns.sql

**Purpose:** Complete settings module backend persistence

**Added Columns to `user_settings` table:**

| Column | Type | Default | Description |
|--------|------|---------|-------------|
| `map_share_location` | BOOLEAN | false | Allow sharing user location on map |
| `map_style` | TEXT | 'standard' | Map display style (standard/satellite/terrain) |
| `ai_model` | TEXT | 'gpt-4' | Selected AI model (gpt-4/gpt-3.5) |
| `ai_personalization` | BOOLEAN | true | Enable AI personalized responses |
| `ai_data_sharing` | BOOLEAN | false | Consent to use data for AI improvement |
| `marketplace_order_notifications` | BOOLEAN | true | Enable order status notifications |
| `msg_enter_to_send` | BOOLEAN | true | Use Enter key to send messages |
| `msg_auto_download_images` | BOOLEAN | true | Auto-download images |
| `msg_auto_download_videos` | BOOLEAN | false | Auto-download videos |
| `msg_text_size` | DOUBLE PRECISION | 16.0 | Message text size in pixels |

**Created Table: `ai_chat_messages`**
- Stores AI chat conversation history
- Enables clear chat history feature
- RLS enabled (users can only access their own messages)

**Indexes:**
- `idx_user_settings_user_id` - Faster user settings lookup
- `idx_ai_chat_messages_user_id` - Faster AI chat history queries

## Migration: 20260711_marketplace_tables.sql

**Purpose:** Marketplace features - shipping addresses and store profiles

**Created Table: `user_addresses`**
- Full CRUD for shipping addresses
- Fields: label, full_name, phone, address_line, city, state, postal_code, is_default
- RLS enabled (users can only access their own addresses)
- Automatic updated_at timestamp trigger

**Created Table: `user_stores`**
- Seller store profiles
- Fields: store_name, tagline, description, logo_url
- One store per user (UNIQUE constraint on user_id)
- Logo uploaded to Supabase Storage public bucket
- RLS enabled (users can only access their own store)
- Automatic updated_at timestamp trigger

**Indexes:**
- `idx_user_addresses_user_id` - Faster address lookups
- `idx_user_addresses_default` - Faster default address queries
- `idx_user_stores_user_id` - Faster store lookups

## How to Apply

### Using Supabase CLI:
```bash
supabase db push
```

### Manual Application:
1. Go to Supabase Dashboard → SQL Editor
2. Copy contents of each migration file
3. Execute the scripts in order

## Rollback (if needed)

### Settings columns:
```sql
-- Remove added columns
ALTER TABLE user_settings 
DROP COLUMN IF EXISTS map_share_location,
DROP COLUMN IF EXISTS map_style,
DROP COLUMN IF EXISTS ai_model,
DROP COLUMN IF EXISTS ai_personalization,
DROP COLUMN IF EXISTS ai_data_sharing,
DROP COLUMN IF EXISTS marketplace_order_notifications,
DROP COLUMN IF EXISTS msg_enter_to_send,
DROP COLUMN IF EXISTS msg_auto_download_images,
DROP COLUMN IF EXISTS msg_auto_download_videos,
DROP COLUMN IF EXISTS msg_text_size;

-- Drop AI chat messages table
DROP TABLE IF EXISTS ai_chat_messages;

-- Drop indexes
DROP INDEX IF EXISTS idx_user_settings_user_id;
DROP INDEX IF EXISTS idx_ai_chat_messages_user_id;
```

### Marketplace tables:
```sql
-- Drop tables
DROP TABLE IF EXISTS user_addresses;
DROP TABLE IF EXISTS user_stores;

-- Drop function
DROP FUNCTION IF EXISTS update_updated_at_column();
```

## Related Files

Flutter pages using these tables:
- **Settings backend:**
  - `lib/features/settings/presentation/pages/map_settings_page.dart`
  - `lib/features/settings/presentation/pages/ai_settings_page.dart`
  - `lib/features/settings/presentation/pages/marketplace_settings_page.dart`
  - `lib/features/settings/presentation/pages/messages_settings_page.dart`
  - `lib/features/settings/presentation/pages/data_storage_settings_page.dart`

- **Marketplace features:**
  - `lib/features/marketplace/presentation/pages/shipping_addresses_page.dart`
  - `lib/features/marketplace/presentation/pages/store_profile_page.dart`

All pages follow the same pattern:
- `_loadSettings()` on init - loads from Supabase
- `_updateSetting(updates)` on change - persists to Supabase
- Optimistic UI with error handling

