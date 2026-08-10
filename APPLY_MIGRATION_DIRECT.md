# 🎯 DIRECT FIX: Apply Migration to Correct Database

## 🔴 Diagnosed Issue

The Flutter app connects to: **`mbhjganbihamoiqmankv.supabase.co`**

The database migration for Global search (search_safe_mode, search_region, search_language columns) was **NEVER applied to this specific project**.

## ✅ Solution: Apply Migration Directly to mbhjganbihamoiqmankv

### Step 1: Open Supabase SQL Editor

1. Go to: https://supabase.com/dashboard/project/mbhjganbihamoiqmankv/sql/new
2. You should be logged into your Supabase account
3. Select the **mbhjganbihamoiqmankv** project
4. Navigate to **SQL Editor** (left sidebar)

### Step 2: Run This SQL

Copy and paste the entire SQL below, then click **Run**:

```sql
-- ============================================================================
-- ALSAMOS GLOBAL SEARCH - DATABASE MIGRATION
-- Project: mbhjganbihamoiqmankv
-- ============================================================================

-- Step 1: Add search preferences columns to user_settings
ALTER TABLE user_settings 
ADD COLUMN IF NOT EXISTS search_safe_mode TEXT DEFAULT 'moderate',
ADD COLUMN IF NOT EXISTS search_region TEXT DEFAULT 'uz',
ADD COLUMN IF NOT EXISTS search_language TEXT DEFAULT 'uz';

-- Step 2: Create search_history table for user query history
CREATE TABLE IF NOT EXISTS search_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  query TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Step 3: Create search_cache table for caching search results
CREATE TABLE IF NOT EXISTS search_cache (
  cache_key TEXT PRIMARY KEY,
  results JSONB NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Step 4: Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_search_history_user_id ON search_history(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_search_history_created ON search_history(created_at);
CREATE INDEX IF NOT EXISTS idx_search_cache_created ON search_cache(created_at);

-- Step 5: Enable RLS on search_history
ALTER TABLE search_history ENABLE ROW LEVEL SECURITY;

-- Step 6: RLS Policy - Users can only access their own search history
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
    AND tablename = 'search_history' 
    AND policyname = 'search_history_user_policy'
  ) THEN
    CREATE POLICY search_history_user_policy ON search_history
      FOR ALL
      USING (auth.uid() = user_id)
      WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

-- Step 7: Grant permissions
GRANT SELECT, INSERT, DELETE ON search_history TO authenticated;
GRANT SELECT, INSERT, UPDATE ON search_cache TO service_role;

-- Step 8: Add comments for documentation
COMMENT ON TABLE search_history IS 'User web search query history';
COMMENT ON TABLE search_cache IS 'Cached search results (shared, TTL 1 hour)';
COMMENT ON COLUMN user_settings.search_safe_mode IS 'Safe search level: off, moderate, strict';
COMMENT ON COLUMN user_settings.search_region IS 'Search region code (uz, us, ru, etc)';
COMMENT ON COLUMN user_settings.search_language IS 'Search language code (uz, en, ru)';

-- ============================================================================
-- VERIFICATION
-- ============================================================================

-- Check columns were added
SELECT column_name, data_type, column_default 
FROM information_schema.columns 
WHERE table_name = 'user_settings' 
AND column_name IN ('search_safe_mode', 'search_region', 'search_language');
-- Expected: 3 rows

-- Check tables were created
SELECT tablename FROM pg_tables 
WHERE schemaname = 'public' 
AND tablename IN ('search_history', 'search_cache');
-- Expected: 2 rows

-- Check RLS is enabled
SELECT tablename, rowsecurity FROM pg_tables 
WHERE schemaname = 'public' AND tablename = 'search_history';
-- Expected: search_history | t

-- ============================================================================
-- RELOAD POSTGREST CACHE (CRITICAL!)
-- ============================================================================

NOTIFY pgrst, 'reload schema';

-- ============================================================================
-- DONE
-- ============================================================================
```

### Step 3: Verify Output

After clicking **Run**, you should see:
- ✅ "Success. No rows returned" (this is correct — DDL statements don't return rows)
- The verification queries at the end will return results confirming the tables/columns exist

### Step 4: Restart API Server

**Option A: Dashboard** (Recommended)
1. Go to: https://supabase.com/dashboard/project/mbhjganbihamoiqmankv/settings/api
2. Click **"Restart API Server"** button
3. Wait 10-30 seconds

**Option B: Already done** (The SQL includes `NOTIFY pgrst, 'reload schema'` which triggers cache reload)

### Step 5: Test in Flutter App

1. **Hot restart** the app (NOT hot reload):
   ```bash
   flutter run -d windows
   ```

2. Navigate to **Search → Global tab**

3. **Expected Result:**
   - ✅ No error message
   - ✅ Shows "Web qidiruvi" info card
   - ✅ Can type query and see results (if backend is deployed)

## 🛡️ What Changed in the App

The Flutter client is now **100% resilient** to missing database columns:

### Before (would crash):
```dart
throw Exception('Failed to load search preferences: $e');
```

### After (returns defaults):
```dart
catch (e) {
  print('Warning: Search preferences columns not found, using defaults: $e');
  return {
    'safeSearch': 'moderate',
    'region': 'uz',
    'language': 'uz',
  };
}
```

### Benefits:
- ✅ App works even if migration is delayed
- ✅ Search uses default preferences (moderate/uz/uz)
- ✅ No crash, no error dialog
- ⚠️ User preferences won't persist until migration is applied

## 🔍 Still Getting Error?

### Check 1: Wrong Project?

Verify the app is using the correct project:

```bash
# Check lib/core/constants/api_constants.dart
# Should show: https://mbhjganbihamoiqmankv.supabase.co
```

### Check 2: Columns Not Created?

Run in SQL Editor:
```sql
SELECT column_name FROM information_schema.columns 
WHERE table_name = 'user_settings';
```

Should include: `search_safe_mode`, `search_region`, `search_language`

### Check 3: Cache Not Reloaded?

1. Go to Settings → API → "Restart API Server"
2. Wait 30 seconds
3. Hot restart Flutter app

### Check 4: Check Flutter Logs

Look for:
```
Warning: Search preferences columns not found, using defaults
```

If you see this, it means:
- ✅ App is resilient (not crashing)
- ⚠️ Migration not applied yet OR cache not reloaded

## 🎉 Success Indicators

After migration:
- ✅ SQL verification queries return expected results
- ✅ API server restarted
- ✅ Flutter app shows Global tab without error
- ✅ Can perform web searches (if backend deployed)

---

**Summary:** Migration targets the **exact** project the app connects to (`mbhjganbihamoiqmankv`), and the Flutter client is now resilient so search works with or without the columns!
