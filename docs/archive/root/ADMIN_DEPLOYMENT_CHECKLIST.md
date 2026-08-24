# Admin System Deployment Checklist

## Pre-Deployment Verification

### Code Status
- ✅ Migration file corrected (no `CREATE POLICY IF NOT EXISTS` syntax error)
- ✅ Profiles table RLS NOT enabled (won't break cross-user reads)
- ✅ Security trigger added (prevents self-escalation)
- ✅ Admin role provider checks `profile.isAdmin`
- ✅ Admin route guard added to router
- ✅ Settings config has admin entry with conditional rendering
- ✅ Admin page exists with 5 functional tabs

### What's Being Deployed
1. `is_admin` column added to `profiles` table
2. Admin management RPC functions (check, grant, revoke)
3. Audit log table (`admin_actions`)
4. Security trigger (prevents non-admins from setting `is_admin`)
5. Schema cache reload

---

## Deployment Steps

### STEP 1: Open Supabase Dashboard
Navigate to: https://supabase.com/dashboard/project/mbhjganbihamoiqmankv/sql

**Verify** you're in the correct project:
- Project name should show "Alsamos" or "mbhjganbihamoiqmankv"
- URL should contain `mbhjganbihamoiqmankv`

### STEP 2: Run Deployment Script
1. Open `DEPLOY_ADMIN_NOW.sql`
2. Copy the ENTIRE file content
3. Paste into Supabase SQL Editor
4. Click "Run" (or Cmd+Enter / Ctrl+Enter)

**Expected Output**:
- Should execute without errors
- Final SELECT query should show a table of users

### STEP 3: Identify Your Two Super-Admins
From the output of Part 5 Step 5.1, identify the two users who should be admins.

Note their:
- Email addresses OR
- User IDs (UUIDs) OR
- Usernames

### STEP 4: Grant Admin to the Two Users
Scroll to Part 5 Step 5.2 in the SQL editor, uncomment ONE option and modify:

**Option A - By Email** (Recommended):
```sql
UPDATE profiles p
SET is_admin = true
FROM auth.users u
WHERE p.id = u.id
  AND u.email IN ('actual_email1@example.com', 'actual_email2@example.com');
```

**Option B - By UUID**:
```sql
UPDATE profiles 
SET is_admin = true
WHERE id IN ('actual-uuid-1', 'actual-uuid-2');
```

**Option C - By Username**:
```sql
UPDATE profiles 
SET is_admin = true
WHERE username IN ('actual_username1', 'actual_username2');
```

Click "Run" again to execute the UPDATE.

### STEP 5: Verify Admins Set
Run the verification query (Part 5 Step 5.3):
```sql
SELECT 
  p.id,
  u.email,
  p.username,
  p.display_name,
  p.is_admin
FROM profiles p
JOIN auth.users u ON u.id = p.id
WHERE p.is_admin = true;
```

**Expected**: Should return exactly 2 rows showing your admin users with `is_admin = true`

---

## Post-Deployment Verification

### Database Checks

Run these queries to confirm everything is set up:

**Check 1: Column exists**
```sql
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'profiles' AND column_name = 'is_admin';
```
Expected: 1 row with `column_name: is_admin, data_type: boolean`

**Check 2: Functions exist**
```sql
SELECT proname 
FROM pg_proc 
WHERE proname IN ('is_user_admin', 'grant_admin_role', 'revoke_admin_role');
```
Expected: 3 rows

**Check 3: Trigger exists**
```sql
SELECT tgname 
FROM pg_trigger 
WHERE tgname = 'trigger_prevent_admin_self_escalation';
```
Expected: 1 row

**Check 4: Audit table exists**
```sql
SELECT table_name 
FROM information_schema.tables 
WHERE table_name = 'admin_actions';
```
Expected: 1 row

**Check 5: Admins set correctly**
```sql
SELECT COUNT(*) as admin_count 
FROM profiles 
WHERE is_admin = true;
```
Expected: `admin_count: 2`

---

## App Verification

### As Admin User (Must Pass All)

1. **Login**
   - [ ] Logout from app
   - [ ] Login with one of the two admin user accounts

2. **Profile Reload**
   - [ ] Wait 3 seconds for profile to load
   - [ ] No errors in console

3. **Settings Page**
   - [ ] Navigate to Settings
   - [ ] Scroll to bottom
   - [ ] **See "Administration" group** (distinct section)
   - [ ] **See "Admin Panel" entry** (purple shield icon)

4. **Admin Panel**
   - [ ] Tap "Admin Panel"
   - [ ] Page opens (doesn't crash or redirect)
   - [ ] **See 5 tabs**: Analitika, Kontent, Pending, History, Admins
   - [ ] Can switch between tabs
   - [ ] No console errors

5. **Admin Functions**
   - [ ] Go to "Admins" tab
   - [ ] Can see list of admins (should show 2)
   - [ ] "Admin qo'shish" button visible

### As Normal User (Must Pass All)

1. **Login**
   - [ ] Logout
   - [ ] Login with a regular (non-admin) user account

2. **Settings Page**
   - [ ] Navigate to Settings
   - [ ] Scroll to entire page
   - [ ] **"Administration" group NOT visible**
   - [ ] **"Admin Panel" entry NOT visible**

3. **Direct Access Blocked**
   - [ ] Try navigating to `/#/admin` directly in browser
   - [ ] Should redirect to `/settings` or home
   - [ ] Should NOT show admin content

4. **Self-Escalation Blocked**
   - [ ] Open Supabase SQL editor
   - [ ] Try to grant admin to normal user:
     ```sql
     UPDATE profiles SET is_admin = true WHERE username = 'normal_user';
     ```
   - [ ] **Should fail** with error: "Only admins can change admin status"

---

## Troubleshooting

### Problem: Migration fails with syntax error

**Check the error message**:
- If contains "CREATE POLICY IF NOT EXISTS": You're running the old migration
- Solution: Use `DEPLOY_ADMIN_NOW.sql` instead

### Problem: Admin Panel doesn't appear for admin users

**Check 1: is_admin set correctly**
```sql
SELECT email, is_admin FROM auth.users u 
JOIN profiles p ON p.id = u.id 
WHERE u.email = 'YOUR_ADMIN_EMAIL';
```
Should show `is_admin: true`

**Check 2: Profile loaded in app**
Add temporary debug:
```dart
// In admin_role_provider.dart
print('Admin check: ${profile?.isAdmin}, Username: ${profile?.username}');
```
Should print `Admin check: true` after login

**Check 3: Force profile reload**
- Completely close app
- Restart app
- Login again

### Problem: Normal users can set their own is_admin

**This means the trigger didn't install correctly**

Check trigger exists:
```sql
SELECT tgname FROM pg_trigger WHERE tgname = 'trigger_prevent_admin_self_escalation';
```

If missing, re-run Part 4 of deployment script.

### Problem: Can't read other users' profiles (search broken)

**This means RLS was incorrectly enabled on profiles table**

Check RLS status:
```sql
SELECT relrowsecurity FROM pg_class WHERE relname = 'profiles';
```

If `relrowsecurity: true`, that's the problem:
```sql
ALTER TABLE profiles DISABLE ROW LEVEL SECURITY;
```

---

## Rollback Plan (If Needed)

If something goes wrong, run this to rollback:

```sql
-- Remove trigger
DROP TRIGGER IF EXISTS trigger_prevent_admin_self_escalation ON profiles;
DROP FUNCTION IF EXISTS prevent_admin_self_escalation();

-- Remove functions
DROP FUNCTION IF EXISTS is_user_admin(uuid);
DROP FUNCTION IF EXISTS grant_admin_role(uuid);
DROP FUNCTION IF EXISTS revoke_admin_role(uuid);
DROP FUNCTION IF EXISTS log_admin_action(text, uuid, jsonb);

-- Remove audit table
DROP TABLE IF EXISTS admin_actions CASCADE;

-- Remove column (CAUTION: This removes all admin flags)
ALTER TABLE profiles DROP COLUMN IF EXISTS is_admin;

-- Reload schema
NOTIFY pgrst, 'reload schema';
```

---

## Success Criteria Summary

All of these must be TRUE:

- [x] Migration runs without errors
- [ ] Exactly 2 users have `is_admin = true` in database
- [ ] Admin users see "Admin Panel" in Settings
- [ ] Admin users can open admin page with 5 tabs
- [ ] Normal users DON'T see "Admin Panel"
- [ ] Normal users can't access `/admin` URL
- [ ] Normal users can't set their own `is_admin` (trigger blocks)
- [ ] Search/profile viewing still works (RLS not enabled on profiles)
- [ ] No console errors or warnings

---

## Timeline

- **Database deployment**: 3 minutes
- **Set admins**: 1 minute
- **App verification**: 3 minutes
- **Total**: ~7 minutes

---

## Support

If stuck:
1. Check error message in SQL editor output
2. Verify correct project (mbhjganbihamoiqmankv)
3. Check console logs in app
4. Review troubleshooting section above
5. Verify trigger and functions exist in database

---

## Final Notes

- The migration is **idempotent** - safe to run multiple times
- Profiles table RLS is **NOT enabled** - won't break existing features
- Security is enforced via **trigger** (prevents self-escalation)
- Admin functions use **SECURITY DEFINER** - secure by design
- Audit log tracks all admin actions for accountability
