-- Migration: Admin role and history tracking tables
-- Created: 2026-01-11
-- Description: Adds admin role support and security/audit event tables for history tracking

-- ============================================================================
-- PART 1: Add admin role to profiles table
-- ============================================================================

-- Add is_admin and role columns to profiles if they don't exist
DO $$ 
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                 WHERE table_name = 'profiles' AND column_name = 'is_admin') THEN
    ALTER TABLE profiles ADD COLUMN is_admin BOOLEAN DEFAULT FALSE;
  END IF;
  
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                 WHERE table_name = 'profiles' AND column_name = 'role') THEN
    ALTER TABLE profiles ADD COLUMN role TEXT DEFAULT 'user';
  END IF;
END $$;

-- Create index on admin columns for performance
CREATE INDEX IF NOT EXISTS idx_profiles_is_admin ON profiles(is_admin) WHERE is_admin = TRUE;
CREATE INDEX IF NOT EXISTS idx_profiles_role ON profiles(role) WHERE role IN ('admin', 'alsamos_admin');

-- ============================================================================
-- PART 2: Create security_events table for audit logging
-- ============================================================================

CREATE TABLE IF NOT EXISTS security_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  event_type TEXT NOT NULL, -- 'password_change', 'two_factor_enable', 'two_factor_disable', 'email_change', 'phone_change', 'account_recovery'
  description TEXT NOT NULL,
  metadata JSONB, -- Additional event data
  ip_address INET,
  user_agent TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_security_events_user_id ON security_events(user_id);
CREATE INDEX IF NOT EXISTS idx_security_events_created_at ON security_events(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_security_events_event_type ON security_events(event_type);

-- ============================================================================
-- PART 3: Row Level Security (RLS) Policies
-- ============================================================================

-- Enable RLS on security_events
ALTER TABLE security_events ENABLE ROW LEVEL SECURITY;

-- Users can only view their own security events
CREATE POLICY "Users can view own security events" ON security_events
  FOR SELECT
  USING (auth.uid() = user_id);

-- Only the system/backend can insert security events (not users directly)
-- This prevents users from creating fake security events
CREATE POLICY "System can insert security events" ON security_events
  FOR INSERT
  WITH CHECK (auth.role() = 'service_role');

-- Admins can view all security events for monitoring
CREATE POLICY "Admins can view all security events" ON security_events
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM profiles 
      WHERE profiles.id = auth.uid() 
      AND (profiles.is_admin = TRUE OR profiles.role IN ('admin', 'alsamos_admin'))
    )
  );

-- ============================================================================
-- PART 4: Admin access control function
-- ============================================================================

-- Function to check if current user is admin
CREATE OR REPLACE FUNCTION is_admin()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM profiles 
    WHERE id = auth.uid() 
    AND (is_admin = TRUE OR role IN ('admin', 'alsamos_admin'))
  );
$$;

-- ============================================================================
-- PART 5: Trigger to log security events automatically
-- ============================================================================

-- Function to log password changes
CREATE OR REPLACE FUNCTION log_password_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF NEW.encrypted_password IS DISTINCT FROM OLD.encrypted_password THEN
    INSERT INTO security_events (user_id, event_type, description, ip_address)
    VALUES (
      NEW.id,
      'password_change',
      'Parol o''zgartirildi',
      inet_client_addr()
    );
  END IF;
  RETURN NEW;
END;
$$;

-- Create trigger on auth.users for password changes
DROP TRIGGER IF EXISTS on_password_change ON auth.users;
CREATE TRIGGER on_password_change
  AFTER UPDATE ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION log_password_change();

-- ============================================================================
-- PART 6: Add comments for documentation
-- ============================================================================

COMMENT ON TABLE security_events IS 'Audit log for security-related events (password changes, 2FA, etc.)';
COMMENT ON COLUMN profiles.is_admin IS 'Boolean flag indicating if user is an Alsamos Corporation admin';
COMMENT ON COLUMN profiles.role IS 'User role (user, admin, alsamos_admin, moderator, etc.)';
COMMENT ON FUNCTION is_admin() IS 'Returns true if the current user has admin privileges';

-- ============================================================================
-- PART 7: Grant appropriate permissions
-- ============================================================================

-- Grant select on profiles to authenticated users (for role checking)
GRANT SELECT ON profiles TO authenticated;

-- Grant usage on security_events to authenticated (RLS will control access)
GRANT SELECT ON security_events TO authenticated;

-- ============================================================================
-- PART 8: Seed data (optional - set yourself as admin for testing)
-- ============================================================================

-- Uncomment and replace with your user ID to make yourself admin:
-- UPDATE profiles SET is_admin = TRUE, role = 'alsamos_admin' 
-- WHERE id = 'YOUR_USER_ID_HERE';

-- Example: Set admin by email (safer):
-- UPDATE profiles SET is_admin = TRUE, role = 'alsamos_admin'
-- WHERE id = (SELECT id FROM auth.users WHERE email = 'admin@alsamos.uz');

