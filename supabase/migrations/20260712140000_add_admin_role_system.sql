-- Admin Role System Migration - CORRECTED
-- Adds is_admin column to profiles and sets up admin management
-- Project: mbhjganbihamoiqmankv.supabase.co
-- Date: 2026-07-12
-- IMPORTANT: Does NOT enable RLS on profiles (would break cross-user reads)

-- ============================================================================
-- Add is_admin column to profiles table
-- ============================================================================

-- Add is_admin boolean column (defaults to false for all users)
ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS is_admin boolean DEFAULT false NOT NULL;

-- Create index for fast admin lookups
CREATE INDEX IF NOT EXISTS idx_profiles_is_admin 
ON profiles(is_admin) 
WHERE is_admin = true;

COMMENT ON COLUMN profiles.is_admin IS 'Whether the user has admin privileges (admin panel access, moderation tools, etc.)';

-- ============================================================================
-- NOTE: We do NOT enable RLS on profiles table
-- Reason: Would break reading other users' profiles (search, creators, etc.)
-- Security: is_admin changes are protected via trigger (see end of file)
-- ============================================================================

-- ============================================================================
-- Admin management functions
-- ============================================================================

-- Function to check if a user is an admin
CREATE OR REPLACE FUNCTION is_user_admin(user_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
AS $$
DECLARE
  admin_status boolean;
BEGIN
  SELECT is_admin INTO admin_status
  FROM profiles
  WHERE id = user_id;
  
  RETURN COALESCE(admin_status, false);
END;
$$;

COMMENT ON FUNCTION is_user_admin(uuid) IS 'Checks if a user has admin privileges';

-- Grant execute to authenticated users (so they can check their own status)
GRANT EXECUTE ON FUNCTION is_user_admin(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION is_user_admin(uuid) TO anon;

-- Function to grant admin role (only callable by existing admins)
CREATE OR REPLACE FUNCTION grant_admin_role(target_user_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  caller_is_admin boolean;
BEGIN
  -- Check if caller is admin
  SELECT is_admin INTO caller_is_admin
  FROM profiles
  WHERE id = auth.uid();
  
  IF NOT COALESCE(caller_is_admin, false) THEN
    RAISE EXCEPTION 'Only admins can grant admin privileges';
  END IF;
  
  -- Grant admin to target user
  UPDATE profiles
  SET is_admin = true
  WHERE id = target_user_id;
  
  RETURN true;
END;
$$;

COMMENT ON FUNCTION grant_admin_role(uuid) IS 'Grants admin role to a user. Only callable by existing admins.';

-- Grant execute to authenticated users (function enforces admin check internally)
GRANT EXECUTE ON FUNCTION grant_admin_role(uuid) TO authenticated;

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
  SELECT is_admin INTO caller_is_admin
  FROM profiles
  WHERE id = auth.uid();
  
  IF NOT COALESCE(caller_is_admin, false) THEN
    RAISE EXCEPTION 'Only admins can revoke admin privileges';
  END IF;
  
  -- Revoke admin from target user
  UPDATE profiles
  SET is_admin = false
  WHERE id = target_user_id;
  
  RETURN true;
END;
$$;

COMMENT ON FUNCTION revoke_admin_role(uuid) IS 'Revokes admin role from a user. Only callable by existing admins. Cannot revoke own admin.';

-- Grant execute to authenticated users (function enforces admin check internally)
GRANT EXECUTE ON FUNCTION revoke_admin_role(uuid) TO authenticated;

-- ============================================================================
-- Set initial admin (CHANGE THIS TO YOUR ADMIN USER ID)
-- ============================================================================

-- IMPORTANT: Replace 'YOUR_ADMIN_USER_ID_HERE' with the actual UUID of your admin user
-- You can find your user ID by running: SELECT id FROM auth.users WHERE email = 'your_email@example.com';
-- 
-- Example:
-- UPDATE profiles SET is_admin = true WHERE id = '12345678-1234-1234-1234-123456789012';
--
-- OR set by username:
-- UPDATE profiles SET is_admin = true WHERE username = 'admin';

-- Uncomment and modify one of these lines after determining your admin user:
-- UPDATE profiles SET is_admin = true WHERE id = 'YOUR_ADMIN_USER_ID_HERE';
-- UPDATE profiles SET is_admin = true WHERE username = 'YOUR_USERNAME_HERE';

-- ============================================================================
-- Admin audit log table (separate table, safe to enable RLS)
-- ============================================================================

CREATE TABLE IF NOT EXISTS admin_actions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id uuid REFERENCES profiles(id) ON DELETE SET NULL,
  action text NOT NULL,
  target_id uuid,
  details jsonb,
  created_at timestamptz DEFAULT now() NOT NULL
);

-- Index for querying actions by admin
CREATE INDEX IF NOT EXISTS idx_admin_actions_admin_id 
ON admin_actions(admin_id, created_at DESC);

-- Index for querying actions by target
CREATE INDEX IF NOT EXISTS idx_admin_actions_target_id 
ON admin_actions(target_id, created_at DESC);

COMMENT ON TABLE admin_actions IS 'Audit log for admin actions (for accountability and debugging)';

-- RLS: Only admins can read the audit log
ALTER TABLE admin_actions ENABLE ROW LEVEL SECURITY;

-- Drop old policy if it exists, then create new one
-- Note: PostgreSQL does NOT support CREATE POLICY IF NOT EXISTS
DROP POLICY IF EXISTS "Only admins can read audit log" ON admin_actions;

CREATE POLICY "Only admins can read audit log"
ON admin_actions FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM profiles
    WHERE id = auth.uid() AND is_admin = true
  )
);

-- Function to log admin actions (automatically called by admin functions)
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

COMMENT ON FUNCTION log_admin_action(text, uuid, jsonb) IS 'Logs admin actions for audit trail';

-- ============================================================================
-- Security: Prevent self-escalation (users cannot set their own is_admin)
-- ============================================================================

-- Trigger function to block unauthorized is_admin changes
CREATE OR REPLACE FUNCTION prevent_admin_self_escalation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  caller_is_admin boolean;
BEGIN
  -- If is_admin column is being changed
  IF NEW.is_admin IS DISTINCT FROM OLD.is_admin THEN
    -- Check if caller is already an admin
    SELECT is_admin INTO caller_is_admin
    FROM profiles
    WHERE id = auth.uid();
    
    -- If caller is not an admin, block the change
    IF NOT COALESCE(caller_is_admin, false) THEN
      RAISE EXCEPTION 'Only admins can change admin status. Use grant_admin_role() or revoke_admin_role() functions.';
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION prevent_admin_self_escalation() IS 'Prevents non-admins from setting their own is_admin flag';

-- Drop trigger if it exists, then create it
DROP TRIGGER IF EXISTS trigger_prevent_admin_self_escalation ON profiles;

CREATE TRIGGER trigger_prevent_admin_self_escalation
  BEFORE UPDATE OF is_admin ON profiles
  FOR EACH ROW
  EXECUTE FUNCTION prevent_admin_self_escalation();

-- ============================================================================
-- Reload API schema cache
-- ============================================================================
NOTIFY pgrst, 'reload schema';
