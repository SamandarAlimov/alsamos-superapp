# Quick Fix Guide - Schema Sync

## 🚨 Problem
App crashes with "column does not exist" (42703) errors on:
- Messages/Conversations loading
- Search results rendering  
- History page loading

## ✅ Solution (3 Steps)

### Step 1: Apply Database Migration (5 min)
```bash
# Open Supabase SQL Editor
# https://supabase.com/dashboard/project/mbhjganbihamoiqmankv/sql/new

# Copy & paste entire file:
supabase/migrations/20260712120000_comprehensive_schema_sync.sql

# Click "Run" button
```

### Step 2: Verify Migration Applied
```sql
-- Run this query in SQL Editor to confirm:
SELECT COUNT(*) as columns_added
FROM information_schema.columns
WHERE table_name IN ('posts', 'conversation_participants', 'user_preferences')
  AND column_name IN ('mute_until', 'poll_data', 'source_type', 'tags', 'history_paused');

-- Should return: columns_added = 5 (or more)
```

### Step 3: Test App
```bash
flutter clean
flutter pub get
flutter run -d windows
```

## ✅ Expected Results

**Before Fix**:
```
PostgrestException: column conversation_participants.mute_until does not exist
NoSuchMethodError: Class '_Map<String, dynamic>' has no instance getter 'name'
Firebase: [core/not-initialized]
```

**After Fix**:
```
✅ App launches clean
✅ Messages load successfully
✅ Search returns results without crash
✅ History page works
✅ No 42703 errors in console
```

## 📋 Verification Checklist

- [ ] Migration SQL ran without errors
- [ ] Verification query returns columns_added ≥ 5
- [ ] App launches without 42703 in console
- [ ] Navigate to Messages → conversations load
- [ ] Navigate to Search → type query → results render
- [ ] Navigate to Settings → History → page loads
- [ ] Check sidebar displays conversations

## 🆘 Troubleshooting

**"Permission denied"**
→ Make sure you're project owner/admin in Supabase dashboard

**"Column already exists"**
→ Good! Migration is idempotent, some columns may already exist

**App still crashes after migration**
→ Run `flutter clean && flutter pub get` and restart app

**"Cannot connect to Supabase"**
→ Check internet connection and SUPABASE_URL in api_constants.dart

## 📚 Full Documentation

- **Technical Details**: `SCHEMA_SYNC_FIX_COMPLETE.md`
- **Complete Summary**: `FINAL_SCHEMA_FIX_SUMMARY.md`
- **History Page**: `HISTORY_PAGE_REBUILD_COMPLETE.md`

---

**Database**: mbhjganbihamoiqmankv.supabase.co  
**Migration**: 20260712120000_comprehensive_schema_sync.sql  
**Status**: Ready to Apply ✅
