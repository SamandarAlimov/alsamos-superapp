# Deploy Admin System - Quick Guide (5 Minutes)

## What You're Deploying
- `is_admin` column added to profiles
- Admin management functions (secure)
- Security trigger (prevents self-escalation)
- Audit logging
- Grant admin to 2 super-admin users

## Step 1: Run SQL (3 minutes)

### 1.1 Open Supabase
https://supabase.com/dashboard/project/mbhjganbihamoiqmankv/sql

### 1.2 Copy & Paste
Open `DEPLOY_ADMIN_NOW.sql` → Copy entire file → Paste in SQL editor

### 1.3 Execute
Click "Run" (or Ctrl+Enter)

**Should see**: Table of users at the end (no errors)

## Step 2: Set Admins (1 minute)

### 2.1 Identify Admins
From the user list shown, note the emails of your two admin users.

### 2.2 Grant Admin
In the SQL editor, scroll to Part 5 Step 5.2, uncomment this and modify:

```sql
UPDATE profiles p
SET is_admin = true
FROM auth.users u
WHERE p.id = u.id
  AND u.email IN ('ADMIN1@EMAIL.COM', 'ADMIN2@EMAIL.COM');
```

Click "Run" again.

### 2.3 Verify
Should see: `UPDATE 2` (meaning 2 rows updated)

Run verification:
```sql
SELECT u.email, p.is_admin 
FROM profiles p
JOIN auth.users u ON u.id = p.id
WHERE p.is_admin = true;
```

Should show your 2 admins with `is_admin = true`.

## Step 3: Test in App (1 minute)

### 3.1 Admin User
1. Logout from app
2. Login as one of the admin users
3. Go to Settings
4. ✅ See "Administration" → "Admin Panel" at bottom
5. Tap it → ✅ Opens with 5 tabs

### 3.2 Normal User
1. Logout
2. Login as regular user
3. Go to Settings
4. ✅ "Administration" group NOT visible

## Done! ✅

Admin system is live. Both super-admins can now access the admin panel.

---

## If Something Goes Wrong

**Admin Panel doesn't appear**:
1. Verify admins set: `SELECT * FROM profiles WHERE is_admin = true;`
2. Force app reload: Close app completely → Restart → Login

**Migration errors**:
- Check you're in correct project (mbhjganbihamoiqmankv)
- Paste error message to troubleshoot

**Self-escalation not blocked**:
- Check trigger exists: `SELECT * FROM pg_trigger WHERE tgname = 'trigger_prevent_admin_self_escalation';`

See `ADMIN_DEPLOYMENT_CHECKLIST.md` for detailed troubleshooting.
