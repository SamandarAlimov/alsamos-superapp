-- ============================================================================
-- ADMIN PANEL FIX - UNIFIED SOLUTION
-- Apply this after running diagnostic to fix admin panel visibility
-- Project: mbhjganbihamoiqmankv.supabase.co
-- ============================================================================

-- ============================================================================
-- PART 1: Ensure is_admin column exists
-- ============================================================================

-- Add is_admin column if it doesn't exist
ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS is_admin boolean DEFAULT false NOT NULL;

-- Add role column as well (for future flexibility)
ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS role text DEFAULT 'user' CHECK (role IN ('user', 'admin', 'super_admin', 'moderator'));

-- Create index for fast admin lookups
CREATE INDEX IF NOT EXISTS idx_profiles_is_admin 
ON profiles(is_admin) 
WHERE is_admin = true;

-- Create index for role lookups
CREATE INDEX IF NOT EXISTS idx_profiles_role 
ON profiles(role) 
WHERE role != 'user';

COMMENT ON COLUMN profiles.is_admin IS 'Whether the user has admin privileges';
COMMENT ON COLUMN profiles.role IS 'User role: user, admin, super_admin, or moderator';

-- ============================================================================
-- PART 2: Enhanced admin check function (works with multiple sources)
-- ============================================================================

-- Function that checks ALL possible admin sources
CREATE OR REPLACE FUNCTION is_user_admin(user_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
AS $$
DECLARE
  admin_status boolean := false;
  user_role text;
BEGIN
  -- Check profiles.is_admin
  SELECT is_admin, role INTO admin_status, user_role
  FROM profiles
  WHERE id = user_id;
  
  -- Return true if is_admin = true OR role is admin/super_admin
  RETURN COALESCE(admin_status, false) 
         OR COALESCE(user_role, 'user') IN ('admin', 'super_admin');
END;
$$;

COMMENT ON FUNCTION is_user_admin(uuid) IS 'Checks if a user has admin privileges from any source (is_admin or role)';

GRANT EXECUTE ON FUNCTION is_user_admin(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION is_user_admin(uuid) TO anon;

-- ============================================================================
-- PART 3: Admin management functions
-- ============================================================================

-- Function to grant admin role (only callable by existing admins)
CREATE OR REPLACE FUNCTION grant_admin_role(target_user_id uuid, admin_role text DEFAULT 'admin')
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  caller_is_admin boolean;
BEGIN
  -- Validate role
  IF admin_role NOT IN ('admin', 'super_admin') THEN
    RAISE EXCEPTION 'Invalid role. Must be admin or super_admin';
  END IF;
  
  -- Check if caller is admin (using unified check)
  caller_is_admin := is_user_admin(auth.uid());
  
  IF NOT caller_is_admin THEN
    RAISE EXCEPTION 'Only admins can grant admin privileges';
  END IF;
  
  -- Grant admin to target user
  UPDATE profiles
  SET is_admin = true,
      role = admin_role
  WHERE id = target_user_id;
  
  -- Log the action
  INSERT INTO admin_actions (admin_id, action, target_id, details)
  VALUES (
    auth.uid(), 
    'grant_admin_role', 
    target_user_id,
    jsonb_build_object('role', admin_role)
  );
  
  RETURN true;
END;
$$;

COMMENT ON FUNCTION grant_admin_role(uuid, text) IS 'Grants admin role to a user. Only callable by existing admins.';
GRANT EXECUTE ON FUNCTION grant_admin_role(uuid, text) TO authenticated;

-- Function to revoke admin role (only callable by existing admins)
CREATE OR REPLACE FUNCTION revoke_admin_role(target_user_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  caller_is_admin boolean;
BEGIN
  -- Prevent revoking your own admin status
  IF target_user_id = auth.uid() THEN
    RAISE EXCEPTION 'Cannot revoke your own admin privileges';
  END IF;
  
  -- Check if caller is admin
  caller_is_admin := is_user_admin(auth.uid());
  
  IF NOT caller_is_admin THEN
    RAISE EXCEPTION 'Only admins can revoke admin privileges';
  END IF;
  
  -- Revoke admin from target user
  UPDATE profiles
  SET is_admin = false,
      role = 'user'
  WHERE id = target_user_id;
  
  -- Log the action
  INSERT INTO admin_actions (admin_id, action, target_id)
  VALUES (auth.uid(), 'revoke_admin_role', target_user_id);
  
  RETURN true;
END;
$$;

COMMENT ON FUNCTION revoke_admin_role(uuid) IS 'Revokes admin role from a user. Only callable by existing admins.';
GRANT EXECUTE ON FUNCTION revoke_admin_role(uuid) TO authenticated;

-- ============================================================================
-- PART 4: Admin audit log table
-- ============================================================================

CREATE TABLE IF NOT EXISTS admin_actions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id uuid NOT NULL REFERENCES profiles(id) ON DELETE SET NULL,
  action text NOT NULL,
  target_id uuid,
  details jsonb,
  created_at timestamptz DEFAULT now() NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_admin_actions_admin_id 
ON admin_actions(admin_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_admin_actions_target_id 
ON admin_actions(target_id, created_at DESC);

COMMENT ON TABLE admin_actions IS 'Audit log for admin actions';

-- RLS: Only admins can read the audit log
ALTER TABLE admin_actions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Only admins can read audit log" ON admin_actions;
CREATE POLICY "Only admins can read audit log"
ON admin_actions FOR SELECT
USING (is_user_admin(auth.uid()));

-- ============================================================================
-- PART 5: Set the two known super-admin users
-- ============================================================================

-- IMPORTANT: You must identify the two super-admin users first
-- Run the diagnostic script to find their user IDs or emails

-- Option 1: Set by email (recommended)
-- Replace 'admin1@example.com' and 'admin2@example.com' with actual emails

-- Find the user IDs first (uncomment and run):
/*
SELECT 
  p.id,
  u.email,
  p.username,
  p.display_name
FROM profiles p
JOIN auth.users u ON u.id = p.id
WHERE u.email IN ('admin1@example.com', 'admin2@example.com');
*/

-- Then set them as super admins (replace the UUIDs):
-- UPDATE profiles 
-- SET is_admin = true, role = 'super_admin'
-- WHERE id IN (
--   'REPLACE_WITH_ADMIN1_UUID',
--   'REPLACE_WITH_ADMIN2_UUID'
-- );

-- Option 2: Set by username (if you know their usernames)
-- UPDATE profiles 
-- SET is_admin = true, role = 'super_admin'
-- WHERE username IN ('admin_username1', 'admin_username2');

-- Option 3: Set the first user as super admin (emergency fallback)
-- UPDATE profiles 
-- SET is_admin = true, role = 'super_admin'
-- WHERE id = (
--   SELECT id FROM profiles 
--   ORDER BY created_at ASC 
--   LIMIT 1
-- );

-- ============================================================================
-- PART 6: Verify the fix
-- ============================================================================

-- Check that admins are now set correctly
SELECT 
  p.id,
  u.email,
  p.username,
  p.display_name,
  p.is_admin,
  p.role,
  is_user_admin(p.id) as admin_check_result
FROM profiles p
JOIN auth.users u ON u.id = p.id
WHERE p.is_admin = true OR p.role IN ('admin', 'super_admin')
ORDER BY p.created_at;

-- Should show your two super-admin users with is_admin = true and role = 'super_admin'

-- ============================================================================
-- PART 7: Reload PostgREST schema cache
-- ============================================================================

NOTIFY pgrst, 'reload schema';

-- ============================================================================
-- COMPLETION MESSAGE
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE '=== ADMIN FIX COMPLETE ===';
  RAISE NOTICE 'Next steps:';
  RAISE NOTICE '1. Uncomment and run ONE of the UPDATE statements in PART 5 to set your super-admins';
  RAISE NOTICE '2. Run the verification query in PART 6 to confirm';
  RAISE NOTICE '3. In the app: Force logout and login again for admin users';
  RAISE NOTICE '4. Admin Panel should now appear in Settings for those users';
END $$;
