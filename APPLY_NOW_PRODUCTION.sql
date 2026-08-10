-- ============================================================================
-- ALSAMOS ADMIN SYSTEM - PRODUCTION DEPLOYMENT
-- Apply this ENTIRE script to: mbhjganbihamoiqmankv.supabase.co
-- Run in: https://supabase.com/dashboard/project/mbhjganbihamoiqmankv/sql
-- ============================================================================

-- ============================================================================
-- PART 1: Add is_admin column to profiles
-- ============================================================================

ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS is_admin boolean DEFAULT false NOT NULL;

CREATE INDEX IF NOT EXISTS idx_profiles_is_admin 
ON profiles(is_admin) 
WHERE is_admin = true;

-- ============================================================================
-- PART 2: Admin check function
-- ============================================================================

CREATE OR REPLACE FUNCTION is_user_admin(user_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
AS $$
DECLARE
  admin_status boolean;
BEGIN
  SELECT is_admin INTO admin_status FROM profiles WHERE id = user_id;
  RETURN COALESCE(admin_status, false);
END;
$$;

GRANT EXECUTE ON FUNCTION is_user_admin(uuid) TO authenticated, anon;

-- ============================================================================
-- PART 3: Grant admin function (only admins can call)
-- ============================================================================

CREATE OR REPLACE FUNCTION grant_admin_role(target_user_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  caller_is_admin boolean;
BEGIN
  SELECT is_admin INTO caller_is_admin FROM profiles WHERE id = auth.uid();
  IF NOT COALESCE(caller_is_admin, false) THEN
    RAISE EXCEPTION 'Only admins can grant admin privileges';
  END IF;
  UPDATE profiles SET is_admin = true WHERE id = target_user_id;
  RETURN true;
END;
$$;

GRANT EXECUTE ON FUNCTION grant_admin_role(uuid) TO authenticated;

-- ============================================================================
-- PART 4: Revoke admin function (only admins can call)
-- ============================================================================

CREATE OR REPLACE FUNCTION revoke_admin_role(target_user_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  caller_is_admin boolean;
BEGIN
  IF target_user_id = auth.uid() THEN
    RAISE EXCEPTION 'Cannot revoke your own admin privileges';
  END IF;
  SELECT is_admin INTO caller_is_admin FROM profiles WHERE id = auth.uid();
  IF NOT COALESCE(caller_is_admin, false) THEN
    RAISE EXCEPTION 'Only admins can revoke admin privileges';
  END IF;
  UPDATE profiles SET is_admin = false WHERE id = target_user_id;
  RETURN true;
END;
$$;

GRANT EXECUTE ON FUNCTION revoke_admin_role(uuid) TO authenticated;

-- ============================================================================
-- PART 5: Admin audit log table
-- ============================================================================

CREATE TABLE IF NOT EXISTS admin_actions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id uuid REFERENCES profiles(id) ON DELETE SET NULL,
  action text NOT NULL,
  target_id uuid,
  details jsonb,
  created_at timestamptz DEFAULT now() NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_admin_actions_admin_id ON admin_actions(admin_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_admin_actions_target_id ON admin_actions(target_id, created_at DESC);

ALTER TABLE admin_actions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Only admins can read audit log" ON admin_actions;

CREATE POLICY "Only admins can read audit log"
ON admin_actions FOR SELECT
USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND is_admin = true));

-- ============================================================================
-- PART 6: Audit log function
-- ============================================================================

CREATE OR REPLACE FUNCTION log_admin_action(
  action_type text,
  target_user_id uuid DEFAULT NULL,
  action_details jsonb DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO admin_actions (admin_id, action, target_id, details)
  VALUES (auth.uid(), action_type, target_user_id, action_details);
END;
$$;

GRANT EXECUTE ON FUNCTION log_admin_action(text, uuid, jsonb) TO authenticated;

-- ============================================================================
-- PART 7: Security trigger to prevent self-escalation
-- ============================================================================

CREATE OR REPLACE FUNCTION prevent_admin_self_escalation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  caller_is_admin boolean;
BEGIN
  IF NEW.is_admin IS DISTINCT FROM OLD.is_admin THEN
    SELECT is_admin INTO caller_is_admin FROM profiles WHERE id = auth.uid();
    IF NOT COALESCE(caller_is_admin, false) THEN
      RAISE EXCEPTION 'Only admins can change admin status';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_prevent_admin_self_escalation ON profiles;

CREATE TRIGGER trigger_prevent_admin_self_escalation
  BEFORE UPDATE OF is_admin ON profiles
  FOR EACH ROW
  EXECUTE FUNCTION prevent_admin_self_escalation();

-- ============================================================================
-- PART 8: Reload schema cache
-- ============================================================================

NOTIFY pgrst, 'reload schema';

-- ============================================================================
-- VERIFICATION: Check what was created
-- ============================================================================

-- Check column exists
SELECT column_name, data_type, column_default 
FROM information_schema.columns 
WHERE table_name = 'profiles' AND column_name = 'is_admin';

-- Check functions exist
SELECT proname as function_name
FROM pg_proc
WHERE proname IN ('is_user_admin', 'grant_admin_role', 'revoke_admin_role', 'log_admin_action', 'prevent_admin_self_escalation')
ORDER BY proname;

-- Check trigger exists
SELECT tgname as trigger_name
FROM pg_trigger
WHERE tgname = 'trigger_prevent_admin_self_escalation';

-- Check audit table exists
SELECT table_name
FROM information_schema.tables
WHERE table_name = 'admin_actions';

-- ============================================================================
-- READY TO SET ADMINS
-- ============================================================================

-- List all users to identify your two super-admins
SELECT 
  u.id,
  u.email,
  p.username,
  p.display_name,
  u.created_at,
  u.last_sign_in_at
FROM auth.users u
LEFT JOIN profiles p ON p.id = u.id
ORDER BY u.created_at
LIMIT 50;

-- ============================================================================
-- INSTRUCTIONS FOR NEXT STEP:
-- 1. Look at the user list above
-- 2. Identify your two super-admin users (by email or username)
-- 3. Copy this file's content again
-- 4. Scroll down to PART 9 below
-- 5. Uncomment and modify the UPDATE statement with your admin emails
-- 6. Run the ENTIRE script again (it's idempotent - safe to re-run)
-- ============================================================================


-- ============================================================================
-- PART 9: GRANT ADMIN TO YOUR TWO SUPER-ADMINS
-- ============================================================================

-- UNCOMMENT ONE OF THESE OPTIONS AND MODIFY WITH YOUR ACTUAL ADMIN DETAILS:

-- Option A: Set by email (RECOMMENDED)
-- UPDATE profiles p
-- SET is_admin = true
-- FROM auth.users u
-- WHERE p.id = u.id
--   AND u.email IN ('admin1@example.com', 'admin2@example.com');

-- Option B: Set by user ID
-- UPDATE profiles 
-- SET is_admin = true
-- WHERE id IN ('uuid-1', 'uuid-2');

-- Option C: Set by username
-- UPDATE profiles 
-- SET is_admin = true
-- WHERE username IN ('admin_username1', 'admin_username2');

-- ============================================================================
-- PART 10: VERIFY ADMINS ARE SET
-- ============================================================================

-- Check that exactly 2 users have is_admin = true
SELECT 
  p.id,
  u.email,
  p.username,
  p.display_name,
  p.is_admin,
  is_user_admin(p.id) as admin_check_passes
FROM profiles p
JOIN auth.users u ON u.id = p.id
WHERE p.is_admin = true;

-- Expected: 2 rows showing your admin users with is_admin = true and admin_check_passes = true

-- Count total admins
SELECT COUNT(*) as total_admins FROM profiles WHERE is_admin = true;

-- Expected: total_admins = 2

-- ============================================================================
-- DEPLOYMENT COMPLETE
-- ============================================================================

-- ✅ Migration applied successfully
-- ✅ Functions created
-- ✅ Trigger installed (prevents self-escalation)
-- ✅ Audit table ready
-- ✅ Schema cache reloaded

-- NEXT STEPS:
-- 1. If you haven't already, uncomment and modify PART 9 above to set your admins
-- 2. Run the script again if you just set the admins
-- 3. In your Flutter app:
--    - Logout
--    - Login as one of the admin users
--    - Go to Settings
--    - Verify "Administration" group appears with "Admin Panel" entry
--    - Tap it - should open admin page with 5 tabs
-- 4. Test with normal user:
--    - Logout
--    - Login as regular user
--    - Verify "Administration" group does NOT appear in Settings
