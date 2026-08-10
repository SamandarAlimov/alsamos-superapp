-- ============================================================================
-- ADMIN PANEL DIAGNOSTIC SCRIPT - COMPLETE
-- Run this ENTIRE script in Supabase SQL Editor to diagnose admin issues
-- Project: mbhjganbihamoiqmankv.supabase.co
-- ============================================================================

-- ============================================================================
-- STEP 1: Check if is_admin column exists in profiles table
-- ============================================================================
\echo '=== STEP 1: Check profiles table columns ==='
SELECT 
  column_name, 
  data_type, 
  column_default, 
  is_nullable
FROM information_schema.columns 
WHERE table_name = 'profiles' 
  AND column_name IN ('is_admin', 'role')
ORDER BY column_name;

-- Expected: Should see 'is_admin' column (boolean) and optionally 'role' column
-- If empty: The migration was NEVER applied! That's the root cause.

-- ============================================================================
-- STEP 2: Check ALL admin-related tables
-- ============================================================================
\echo '=== STEP 2: Admin-related tables ==='
SELECT 
  table_name,
  table_type
FROM information_schema.tables 
WHERE table_schema = 'public'
  AND (
    table_name ILIKE '%admin%' 
    OR table_name = 'user_roles'
    OR table_name = 'permissions'
  )
ORDER BY table_name;

-- Look for: admin_users, admin_actions, user_roles, etc.

-- ============================================================================
-- STEP 3: Find ALL users with admin indicators
-- ============================================================================
\echo '=== STEP 3: Find potential admin users ==='

-- From profiles table (if is_admin column exists)
SELECT 
  p.id,
  u.email,
  p.username,
  p.display_name,
  p.is_admin,
  p.role,
  p.created_at
FROM profiles p
LEFT JOIN auth.users u ON u.id = p.id
WHERE p.is_admin = true
   OR p.role IN ('admin', 'super_admin', 'moderator')
ORDER BY p.created_at;

-- If this fails with "column does not exist", the migration wasn't applied!

-- ============================================================================
-- STEP 4: Check auth.users metadata for admin claims
-- ============================================================================
\echo '=== STEP 4: Check auth metadata ==='
SELECT 
  id,
  email,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at
FROM auth.users
WHERE 
  raw_app_meta_data::text ILIKE '%admin%'
  OR raw_user_meta_data::text ILIKE '%admin%'
  OR raw_app_meta_data->>'role' IN ('admin', 'super_admin')
ORDER BY created_at;

-- ============================================================================
-- STEP 5: Check admin_users table (if it exists from old migration)
-- ============================================================================
\echo '=== STEP 5: Check admin_users table ==='
-- This will error if table doesn't exist - that's OK
SELECT 
  au.*,
  u.email,
  p.username,
  p.display_name
FROM admin_users au
LEFT JOIN auth.users u ON u.id = au.user_id
LEFT JOIN profiles p ON p.id = au.user_id
ORDER BY au.created_at DESC;

-- If this errors: No admin_users table exists

-- ============================================================================
-- STEP 6: List ALL users (to identify the two known admins)
-- ============================================================================
\echo '=== STEP 6: All users in system ==='
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
-- STEP 7: Check if admin RPC functions exist
-- ============================================================================
\echo '=== STEP 7: Check admin functions ==='
SELECT 
  proname as function_name,
  pg_get_functiondef(oid) as definition
FROM pg_proc
WHERE proname IN (
  'is_user_admin',
  'grant_admin_role',
  'revoke_admin_role',
  'log_admin_action'
)
ORDER BY proname;

-- If empty: Migration wasn't applied

-- ============================================================================
-- DIAGNOSTIC SUMMARY
-- ============================================================================
\echo '=== DIAGNOSTIC COMPLETE ==='
\echo 'Review the results above to determine:'
\echo '1. Does profiles.is_admin column exist? (Step 1)'
\echo '2. Are there any admin tables? (Step 2)'
\echo '3. Are any users flagged as admin? (Step 3)'
\echo '4. Are admins in auth metadata? (Step 4)'
\echo '5. Do admin functions exist? (Step 7)'
\echo ''
\echo 'Most likely cause: Migration 20260712140000_add_admin_role_system.sql was NEVER applied'
