-- ============================================================================
-- DEPLOY ADMIN SYSTEM TO PRODUCTION
-- Run this ENTIRE script in Supabase SQL Editor
-- Project: mbhjganbihamoiqmankv.supabase.co
-- ============================================================================

-- ============================================================================
-- PART 1: Apply the corrected migration
-- ============================================================================

-- Add is_admin column
ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS is_admin boolean DEFAULT false NOT NULL;

-- Create index
CREATE INDEX IF NOT EXISTS idx_profiles_is_admin 
ON profiles(is_admin) 
WHERE is_admin = true;

-- ============================================================================
-- PART 2: Create admin management functions
-- ============================================================================

-- Check if user is admin
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

-- Grant admin role
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

-- Revoke admin role
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
-- PART 3: Create audit log table
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

-- Enable RLS only on admin_actions table (NOT on profiles)
ALTER TABLE admin_actions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Only admins can read audit log" ON admin_actions;

CREATE POLICY "Only admins can read audit log"
ON admin_actions FOR SELECT
USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND is_admin = true));

-- Log function
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
-- PART 4: Security trigger to prevent self-escalation
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
-- PART 5: IDENTIFY AND SET YOUR TWO SUPER-ADMINS
-- ============================================================================

-- Step 5.1: Find all users (identify your two admins from this list)
SELECT 
  u.id,
  u.email,
  p.username,
  p.display_name,
  p.created_at
FROM auth.users u
LEFT JOIN profiles p ON p.id = u.id
ORDER BY u.created_at
LIMIT 20;

-- Step 5.2: Once you've identified the two admin users, uncomment and run ONE of these:

-- Option A: Set by email (RECOMMENDED - replace with actual emails)
-- UPDATE profiles p
-- SET is_admin = true
-- FROM auth.users u
-- WHERE p.id = u.id
--   AND u.email IN ('admin1@example.com', 'admin2@example.com');

-- Option B: Set by UUID (if you copied IDs from above)
-- UPDATE profiles 
-- SET is_admin = true
-- WHERE id IN ('UUID1_FROM_ABOVE', 'UUID2_FROM_ABOVE');

-- Option C: Set by username
-- UPDATE profiles 
-- SET is_admin = true
-- WHERE username IN ('admin_username1', 'admin_username2');

-- Step 5.3: Verify admins are set
SELECT 
  p.id,
  u.email,
  p.username,
  p.display_name,
  p.is_admin
FROM profiles p
JOIN auth.users u ON u.id = p.id
WHERE p.is_admin = true;

-- Should show exactly 2 users

-- ============================================================================
-- PART 6: Reload schema cache
-- ============================================================================

NOTIFY pgrst, 'reload schema';

-- ============================================================================
-- DEPLOYMENT COMPLETE
-- ============================================================================

-- Next steps:
-- 1. Verify the SELECT above shows your two admin users
-- 2. In the app: Logout and login as one of the admin users
-- 3. Go to Settings - you should see "Administration" group
-- 4. Tap "Admin Panel" - should open with 5 tabs
-- 5. Test that normal users DON'T see the Admin Panel entry
