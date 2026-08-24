# Admin Panel Quick Fix - 5 Minutes

## Problem
Admin Panel doesn't appear for super-admin users.

## Cause
Migration was never applied → `is_admin` column doesn't exist.

## Fix (Do This Now)

### 1. Apply Migration (Supabase Dashboard)
Go to: https://supabase.com/dashboard/project/mbhjganbihamoiqmankv/sql

Paste and run this:

```sql
-- Add columns
ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS is_admin boolean DEFAULT false NOT NULL;

ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS role text DEFAULT 'user';

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_profiles_is_admin ON profiles(is_admin) WHERE is_admin = true;

-- Set your two admins (REPLACE EMAILS)
UPDATE profiles p
SET is_admin = true, role = 'super_admin'
FROM auth.users u
WHERE p.id = u.id
  AND u.email IN ('YOUR_ADMIN1_EMAIL', 'YOUR_ADMIN2_EMAIL');

-- Verify
SELECT 
  u.email,
  p.username,
  p.is_admin,
  p.role
FROM profiles p
JOIN auth.users u ON u.id = p.id
WHERE p.is_admin = true;

-- Reload schema
NOTIFY pgrst, 'reload schema';
```

### 2. Restart App
- Logout
- Login as admin
- Go to Settings
- See "Administration" → "Admin Panel" ✅

## If You Don't Know Admin Emails

Find them first:
```sql
SELECT u.id, u.email, p.username, u.created_at 
FROM auth.users u
JOIN profiles p ON p.id = u.id
ORDER BY u.created_at
LIMIT 5;
```

Pick the two that should be admins, then use their UUIDs:
```sql
UPDATE profiles 
SET is_admin = true, role = 'super_admin'
WHERE id IN ('UUID1', 'UUID2');
```

## Done!
Admin Panel should now appear in Settings for those users.

For detailed troubleshooting, see: `ADMIN_FIX_STEP_BY_STEP.md`
