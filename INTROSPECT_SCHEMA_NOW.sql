-- ============================================================================
-- SUPABASE SCHEMA INTROSPECTION - COMPLETE
-- Run this ENTIRE script in Supabase SQL Editor
-- Project: mbhjganbihamoiqmankv.supabase.co
-- Purpose: Capture the REAL schema to align Flutter app
-- ============================================================================

-- ============================================================================
-- PART 1: ALL TABLES AND COLUMNS (with types, nullability, defaults)
-- ============================================================================

\echo '=== PART 1: TABLES AND COLUMNS ==='

SELECT 
  table_name,
  column_name,
  data_type,
  udt_name,
  is_nullable,
  column_default,
  character_maximum_length,
  numeric_precision,
  ordinal_position
FROM information_schema.columns
WHERE table_schema = 'public'
ORDER BY table_name, ordinal_position;

-- ============================================================================
-- PART 2: PRIMARY KEYS
-- ============================================================================

\echo '=== PART 2: PRIMARY KEYS ==='

SELECT 
  tc.table_name,
  kcu.column_name,
  tc.constraint_name
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu 
  ON tc.constraint_name = kcu.constraint_name
WHERE tc.table_schema = 'public'
  AND tc.constraint_type = 'PRIMARY KEY'
ORDER BY tc.table_name;

-- ============================================================================
-- PART 3: FOREIGN KEYS
-- ============================================================================

\echo '=== PART 3: FOREIGN KEYS ==='

SELECT 
  tc.table_name AS from_table,
  kcu.column_name AS from_column,
  ccu.table_name AS to_table,
  ccu.column_name AS to_column,
  tc.constraint_name,
  rc.update_rule,
  rc.delete_rule
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu 
  ON tc.constraint_name = kcu.constraint_name
JOIN information_schema.constraint_column_usage ccu 
  ON ccu.constraint_name = tc.constraint_name
JOIN information_schema.referential_constraints rc
  ON rc.constraint_name = tc.constraint_name
WHERE tc.table_schema = 'public'
  AND tc.constraint_type = 'FOREIGN KEY'
ORDER BY tc.table_name, kcu.column_name;

-- ============================================================================
-- PART 4: ENUMS AND CUSTOM TYPES
-- ============================================================================

\echo '=== PART 4: ENUMS AND CUSTOM TYPES ==='

SELECT 
  t.typname AS enum_name,
  e.enumlabel AS enum_value,
  e.enumsortorder AS sort_order
FROM pg_type t
JOIN pg_enum e ON e.enumtypid = t.oid
ORDER BY t.typname, e.enumsortorder;

-- ============================================================================
-- PART 5: INDEXES
-- ============================================================================

\echo '=== PART 5: INDEXES ==='

SELECT 
  tablename,
  indexname,
  indexdef
FROM pg_indexes
WHERE schemaname = 'public'
ORDER BY tablename, indexname;

-- ============================================================================
-- PART 6: RLS POLICIES
-- ============================================================================

\echo '=== PART 6: RLS POLICIES ==='

SELECT 
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
FROM pg_policies
WHERE schemaname = 'public'
ORDER BY tablename, policyname;

-- ============================================================================
-- PART 7: FUNCTIONS / RPCS
-- ============================================================================

\echo '=== PART 7: FUNCTIONS / RPCS ==='

SELECT 
  p.proname AS function_name,
  pg_get_function_identity_arguments(p.oid) AS arguments,
  pg_get_functiondef(p.oid) AS definition
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.prokind = 'f'  -- regular functions only (not aggregates)
ORDER BY p.proname;

-- ============================================================================
-- PART 8: TRIGGERS
-- ============================================================================

\echo '=== PART 8: TRIGGERS ==='

SELECT 
  event_object_table AS table_name,
  trigger_name,
  action_timing,
  event_manipulation,
  action_statement
FROM information_schema.triggers
WHERE trigger_schema = 'public'
ORDER BY event_object_table, trigger_name;

-- ============================================================================
-- PART 9: VIEWS
-- ============================================================================

\echo '=== PART 9: VIEWS ==='

SELECT 
  table_name AS view_name,
  view_definition
FROM information_schema.views
WHERE table_schema = 'public'
ORDER BY table_name;

-- ============================================================================
-- PART 10: MATERIALIZED VIEWS
-- ============================================================================

\echo '=== PART 10: MATERIALIZED VIEWS ==='

SELECT 
  schemaname,
  matviewname,
  matviewowner,
  tablespace,
  hasindexes,
  ispopulated,
  definition
FROM pg_matviews
WHERE schemaname = 'public'
ORDER BY matviewname;

-- ============================================================================
-- PART 11: TABLE SIZES (for reference)
-- ============================================================================

\echo '=== PART 11: TABLE SIZES ==='

SELECT 
  schemaname,
  tablename,
  pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
LIMIT 50;

-- ============================================================================
-- PART 12: STORAGE BUCKETS
-- ============================================================================

\echo '=== PART 12: STORAGE BUCKETS ==='

SELECT 
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
FROM storage.buckets
ORDER BY name;

-- ============================================================================
-- PART 13: STORAGE POLICIES
-- ============================================================================

\echo '=== PART 13: STORAGE POLICIES ==='

SELECT 
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual
FROM pg_policies
WHERE schemaname = 'storage'
ORDER BY tablename, policyname;

-- ============================================================================
-- PART 14: CHECK CONSTRAINTS
-- ============================================================================

\echo '=== PART 14: CHECK CONSTRAINTS ==='

SELECT 
  tc.table_name,
  tc.constraint_name,
  cc.check_clause
FROM information_schema.table_constraints tc
JOIN information_schema.check_constraints cc
  ON tc.constraint_name = cc.constraint_name
WHERE tc.table_schema = 'public'
  AND tc.constraint_type = 'CHECK'
ORDER BY tc.table_name, tc.constraint_name;

-- ============================================================================
-- PART 15: SEQUENCES
-- ============================================================================

\echo '=== PART 15: SEQUENCES ==='

SELECT 
  sequence_name,
  data_type,
  start_value,
  minimum_value,
  maximum_value,
  increment
FROM information_schema.sequences
WHERE sequence_schema = 'public'
ORDER BY sequence_name;

-- ============================================================================
-- PART 16: TABLE COMMENTS
-- ============================================================================

\echo '=== PART 16: TABLE COMMENTS ==='

SELECT 
  c.relname AS table_name,
  obj_description(c.oid) AS table_comment
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind = 'r'  -- regular tables
  AND obj_description(c.oid) IS NOT NULL
ORDER BY c.relname;

-- ============================================================================
-- PART 17: COLUMN COMMENTS
-- ============================================================================

\echo '=== PART 17: COLUMN COMMENTS ==='

SELECT 
  c.relname AS table_name,
  a.attname AS column_name,
  col_description(c.oid, a.attnum) AS column_comment
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_attribute a ON a.attrelid = c.oid
WHERE n.nspname = 'public'
  AND c.relkind = 'r'
  AND a.attnum > 0
  AND NOT a.attisdropped
  AND col_description(c.oid, a.attnum) IS NOT NULL
ORDER BY c.relname, a.attnum;

-- ============================================================================
-- INTROSPECTION COMPLETE
-- ============================================================================

\echo ''
\echo '=== INTROSPECTION COMPLETE ==='
\echo ''
\echo 'Copy all output above and save to a file.'
\echo 'This is the REAL schema that Flutter must match.'
\echo ''
\echo 'Next steps:'
\echo '1. Save output as SCHEMA_INTROSPECTION_OUTPUT.txt'
\echo '2. I will parse it to create SUPABASE_SCHEMA_REFERENCE.md'
\echo '3. Then audit every Flutter query against this schema'
\echo '4. Fix all mismatches to eliminate 42703 errors'
