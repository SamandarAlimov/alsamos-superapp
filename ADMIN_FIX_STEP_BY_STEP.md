# Admin Panel Fix - Step-by-Step Guide

## Problem
The Admin Panel entry does NOT appear in Settings for the two known super-admin users.

## Root Cause (Most Likely)
The migration `20260712140000_add_admin_role_system.sql` was **NEVER applied** to the connected Supabase project `mbhjganbihamoiqmankv.supabase.co`, so:
- The `is_admin` column doesn't exist in the `profiles` table
- The app tries to read `profiles.is_admin` but gets `null/false` for everyone
- Even if users were granted admin via another method, the app doesn't see it

## Solution Overview
1. Run diagnostic to confirm the problem
2. Apply the fix (add columns + set admins)
3. Force profile reload in app
4. Verify admin panel appears

---

## STEP 1: Run Diagnostic (2 minutes)

### 1.1 Open Supabase SQL Editor
Go to: https://supabase.com/dashboard/project/mbhjganbihamoiqmankv/sql

### 1.2 Run Diagnostic Script
Copy and paste the entire content of `ADMIN_DIAGNOSTIC_COMPLETE.sql` into the SQL editor and click "Run".

### 1.3 Review Results
Look for these key findings:

**Critical Questions:**
- ❓ **Step 1**: Does `is_admin` column exist in profiles table?
  - ✅ If YES → Column exists, check Step 3
  - ❌ If NO → **This is the problem!** Migration was never applied.

- ❓ **Step 3**: Are any users showing `is_admin = true`?
  - ✅ If YES → Check if your two admins are in the list
  - ❌ If NO → No admins are set

- ❓ **Step 6**: Can you identify the two super-admin users?
  - Note their emails or user IDs for the next step

---

## STEP 2: Apply the Fix (3 minutes)

### 2.1 Open SQL Editor Again
Same URL: https://supabase.com/dashboard/project/mbhjganbihamoiqmankv/sql

### 2.2 Apply Fix Script
Copy and paste the entire content of `ADMIN_FIX_UNIFIED.sql` into the SQL editor.

### 2.3 Identify Your Two Super-Admin Users
Before running, you need to identify them. Choose ONE method:

**Method A: By Email** (recommended)
1. Find this section in the script (PART 5):
```sql
SELECT 
  p.id,
  u.email,
  p.username,
  p.display_name
FROM profiles p
JOIN auth.users u ON u.id = p.id
WHERE u.email IN ('admin1@example.com', 'admin2@example.com');
```

2. Replace the emails with your actual admin emails
3. Run ONLY this SELECT query first
4. Copy the two UUIDs from the results

**Method B: By Username**
If you know their usernames, use:
```sql
SELECT id, username, display_name 
FROM profiles 
WHERE username IN ('admin_username1', 'admin_username2');
```

**Method C: By Creation Date** (last resort)
If they were the first two users created:
```sql
SELECT id, username, display_name, created_at 
FROM profiles 
ORDER BY created_at ASC 
LIMIT 2;
```

### 2.4 Set the Super-Admins
Find PART 5 in the script and uncomment ONE of the UPDATE statements:

**Option 1: By UUID** (most reliable):
```sql
UPDATE profiles 
SET is_admin = true, role = 'super_admin'
WHERE id IN (
  'REPLACE_WITH_UUID1_FROM_ABOVE',
  'REPLACE_WITH_UUID2_FROM_ABOVE'
);
```

**Option 2: By Username**:
```sql
UPDATE profiles 
SET is_admin = true, role = 'super_admin'
WHERE username IN ('actual_username1', 'actual_username2');
```

**Option 3: By Email** (requires join):
```sql
UPDATE profiles p
SET is_admin = true, role = 'super_admin'
FROM auth.users u
WHERE p.id = u.id
  AND u.email IN ('admin1@example.com', 'admin2@example.com');
```

### 2.5 Run the Complete Script
Click "Run" to execute the entire script (with your UPDATE statement uncommented).

### 2.6 Verify Success
The script will automatically run a verification query at the end (PART 6). You should see:
```
id                                  | email              | username | is_admin | role        | admin_check_result
------------------------------------+--------------------+----------+----------+-------------+-------------------
your-uuid-1                         | admin1@example.com | admin1   | true     | super_admin | true
your-uuid-2                         | admin2@example.com | admin2   | true     | super_admin | true
```

---

## STEP 3: Force App to Reload Profile (1 minute)

The app caches the profile after login. To see the admin flag, you need to force a reload.

### Option A: Logout and Login (Recommended)
1. Open the app
2. Go to Settings → Click your profile → Logout
3. Login again with an admin account
4. The profile will reload with `is_admin: true`

### Option B: Kill and Restart App
1. Close the app completely
2. Restart it
3. Should reload profile automatically

### Option C: Wait for Profile Refresh
The auth provider refreshes profile periodically, but this could take a while.

---

## STEP 4: Verify Admin Panel Appears (30 seconds)

### 4.1 As Admin User
1. Open the app (logged in as one of the two admin users)
2. Navigate to Settings
3. Scroll to the bottom
4. **You should now see**: "Administration" group with "Admin Panel" entry (purple shield icon)
5. Tap "Admin Panel"
6. **Expected**: Opens admin page with 5 tabs (Analytics, Content, Pending, History, Admins)

### 4.2 As Normal User (Optional)
1. Logout
2. Login with a regular user account
3. Go to Settings
4. **Expected**: NO "Administration" group visible
5. Try direct URL: `/#/admin` → should redirect to `/settings`

---

## STEP 5: Troubleshooting

### Problem: Admin Panel Still Doesn't Appear

**Check 1: Verify Database Change Applied**
```sql
SELECT id, username, is_admin, role 
FROM profiles 
WHERE is_admin = true;
```
Should show your two admin users.

**Check 2: Verify Profile Loaded in App**
Add temporary debug logging:
```dart
// In admin_role_provider.dart, temporarily add:
final adminRoleStateProvider = Provider<bool>((ref) {
  final authState = ref.watch(authProvider);
  final profile = authState.profile;
  
  print('🔍 Admin Check - Profile: ${profile?.username}, isAdmin: ${profile?.isAdmin}, role: ${profile?.role}');
  
  if (profile == null) return false;
  // ... rest of code
});
```

Then check console logs after login. You should see:
```
🔍 Admin Check - Profile: admin1, isAdmin: true, role: super_admin
```

**Check 3: Verify Column Exists**
```sql
SELECT column_name 
FROM information_schema.columns 
WHERE table_name = 'profiles' 
  AND column_name = 'is_admin';
```
Should return one row with `column_name: is_admin`.

**Check 4: Force Profile Reload**
In the app, add this temporary code to force reload:
```dart
// In some accessible place (e.g., settings page)
ElevatedButton(
  onPressed: () async {
    final userId = ref.read(authProvider).user?.id;
    if (userId != null) {
      await ref.read(authProvider.notifier).loadProfile(userId);
      print('Profile reloaded');
    }
  },
  child: Text('Reload Profile'),
)
```

### Problem: Migration Fails to Apply

**Error: "column already exists"**
- The column was partially added before
- Check current state: `SELECT is_admin FROM profiles LIMIT 1;`
- If it works, the column exists - just need to set the admins (Part 5)

**Error: "permission denied"**
- You don't have admin rights in Supabase dashboard
- Contact project owner to run the migration

**Error: "relation does not exist"**
- Wrong project or profiles table doesn't exist
- Verify you're in the correct project: mbhjganbihamoiqmankv

---

## STEP 6: Make It Permanent

Once verified working:

### 6.1 Remove Debug Logging
Remove any temporary `print()` statements added for debugging.

### 6.2 Document Your Admins
Create a note somewhere secure listing:
- Admin 1: email, username, user ID
- Admin 2: email, username, user ID

### 6.3 Grant Additional Admins (If Needed)
To add more admins later:
```sql
-- Via SQL
UPDATE profiles 
SET is_admin = true, role = 'admin'
WHERE username = 'new_admin_username';

-- Or via RPC (once logged in as admin)
SELECT grant_admin_role('TARGET_USER_ID', 'admin');
```

Or use the Admin Panel UI:
1. Login as admin
2. Go to Admin Panel → Admins tab
3. Click "Admin qo'shish" (Add admin)
4. Enter username
5. Confirm

---

## Summary Checklist

- [ ] Ran diagnostic script (ADMIN_DIAGNOSTIC_COMPLETE.sql)
- [ ] Confirmed `is_admin` column missing OR admins not set
- [ ] Applied fix script (ADMIN_FIX_UNIFIED.sql)
- [ ] Identified two super-admin user IDs/emails
- [ ] Updated profiles table with is_admin = true for both
- [ ] Verified in database: SELECT shows both as admins
- [ ] Logged out and back in as admin user
- [ ] Admin Panel appears in Settings → Administration
- [ ] Tapped Admin Panel → opens with 5 tabs
- [ ] Verified normal users DON'T see Admin Panel
- [ ] Removed any debug code

---

## Expected Timeline
- **Diagnostic**: 2 minutes
- **Apply Fix**: 3 minutes
- **Reload App**: 1 minute
- **Verify**: 1 minute
- **Total**: ~7 minutes

---

## Support

If you're still stuck after following this guide:

1. **Check the diagnostic output** - paste it here for review
2. **Check console logs** - look for profile load errors
3. **Verify the correct project** - confirm you're in mbhjganbihamoiqmankv
4. **Check auth state** - ensure user is actually logged in

The most common issue is that the migration was never applied to the connected project.
