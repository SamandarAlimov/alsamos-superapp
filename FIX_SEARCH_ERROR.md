# 🔧 Fix "column user_settings.search_safe_mode does not exist" Error

## ❌ Current Error

```
Exception: Failed to load search preferences: PostgrestException(
  message: column user_settings.search_safe_mode does not exist, 
  code: 42703, 
  details: Bad Request
)
```

## 🎯 Root Cause

The database migration that adds `search_safe_mode`, `search_region`, and `search_language` columns to the `user_settings` table was **never applied** to your live Supabase database.

## ✅ Solution (3 steps)

### Step 1: Apply the Migration to Database

**Option A: Via Supabase SQL Editor (Recommended)**

1. Go to your Supabase Dashboard: https://supabase.com/dashboard
2. Select your project
3. Navigate to **SQL Editor** (left sidebar)
4. Click **+ New Query**
5. Copy the entire contents of `APPLY_MIGRATION_NOW.sql` (in this repo)
6. Paste into the SQL editor
7. Click **Run** (or press Ctrl+Enter)
8. **Verify:** You should see "Success. No rows returned" (this is correct!)
9. Scroll down and run the **VERIFICATION QUERIES** section one-by-one to confirm:
   - Query 1: Should return 3 rows (search_safe_mode, search_region, search_language)
   - Query 2: Should return 2 rows (search_history, search_cache)
   - Query 3: Should return 3 rows (indexes)
   - Query 4: Should show `rowsecurity = t` (true)
   - Query 5: Should show the RLS policy

**Option B: Via Supabase CLI (If linked)**

```bash
# Link your project (if not already linked)
supabase login
supabase link --project-ref YOUR_PROJECT_REF

# Push the migration
supabase db push

# Or apply specific migration
supabase migration up --db-url YOUR_DB_URL
```

### Step 2: Reload PostgREST Schema Cache (CRITICAL!)

After applying the migration, PostgREST (the REST API layer) must reload its schema cache. Otherwise, it will still think the columns don't exist!

**Option A: Dashboard Restart (Easiest)**

1. Go to Supabase Dashboard → **Settings** → **API**
2. Click **"Restart API Server"** button
3. Wait 10-30 seconds for restart

**Option B: SQL NOTIFY (Advanced)**

Run this in SQL Editor:
```sql
NOTIFY pgrst, 'reload schema';
```

**Option C: Manual Cache Refresh**

```bash
curl -X POST "https://YOUR_PROJECT_REF.supabase.co/rest/v1/" \
  -H "apikey: YOUR_SERVICE_ROLE_KEY" \
  -H "Prefer: reload-schema"
```

### Step 3: Verify in Flutter App

1. **Hot restart** the Flutter app (not just hot reload):
   ```bash
   # Stop the app, then run:
   flutter run -d windows
   ```

2. Navigate to **Search → Global tab**

3. **Expected:** 
   - ✅ No error
   - ✅ Shows "Web qidiruvi" info card
   - ✅ Can perform searches

4. **If still errors:** Check browser DevTools / Flutter logs for any remaining issues

## 🛡️ Resilience Added

The Flutter client has been updated to **gracefully handle** missing columns:

**Before:**
```dart
// Threw exception if columns didn't exist
throw Exception('Failed to load search preferences: $e');
```

**After:**
```dart
// Returns defaults if columns don't exist (migration not applied yet)
catch (e) {
  print('Warning: Search preferences columns not found, using defaults: $e');
  return {
    'safeSearch': 'moderate',
    'region': 'uz',
    'language': 'uz',
  };
}
```

This means:
- ✅ App won't crash if migration is delayed
- ✅ Search will work with default preferences
- ⚠️ User preferences won't persist until migration is applied

## 🧪 Testing Checklist

After applying the fix:

- [ ] SQL verification queries all pass
- [ ] PostgREST schema cache reloaded
- [ ] Flutter app restarted (hot restart, not just hot reload)
- [ ] Global tab shows no error
- [ ] Can type query and see results
- [ ] No error in Flutter logs related to `search_safe_mode`

## 🔍 Debugging

If the error persists after all steps:

### Check 1: Verify columns exist in database

```sql
SELECT column_name, data_type, column_default 
FROM information_schema.columns 
WHERE table_name = 'user_settings' 
AND column_name IN ('search_safe_mode', 'search_region', 'search_language');
```

**Expected:** 3 rows returned

### Check 2: Verify user_settings row exists for current user

```sql
SELECT id, user_id, search_safe_mode, search_region, search_language
FROM user_settings
WHERE user_id = auth.uid();
```

**If no rows:** The user doesn't have a `user_settings` row yet. The app should create one on first settings access.

### Check 3: Check Flutter logs

Look for:
```
Warning: Search preferences columns not found, using defaults
```

If you see this **after** applying migration → PostgREST cache wasn't reloaded!

### Check 4: Verify PostgREST version

Very old PostgREST versions may not respect `NOTIFY pgrst`. Restart the API server via dashboard instead.

### Check 5: Test with direct API call

```bash
curl "https://YOUR_PROJECT_REF.supabase.co/rest/v1/user_settings?select=search_safe_mode,search_region,search_language" \
  -H "apikey: YOUR_ANON_KEY" \
  -H "Authorization: Bearer YOUR_USER_JWT"
```

**If this returns 400/42703:** Cache not reloaded or migration not applied.

## 📞 Still Stuck?

1. Check Supabase Dashboard → **Logs** → **API Logs** for detailed errors
2. Check **Database** → **Roles & Grants** to ensure `authenticated` role has SELECT on `user_settings`
3. Check **Database** → **Webhooks** for any triggers that might interfere
4. Re-run the entire migration SQL from scratch
5. Contact Supabase support with:
   - Project ref
   - Error message
   - Output of verification queries

## 🎉 Success Indicators

✅ Migration applied → Verification queries pass  
✅ Cache reloaded → API restart confirms in logs  
✅ Client resilient → Defaults used if columns missing  
✅ App works → Global tab shows web results  

Once all green, the Global web search is fully operational! 🚀
