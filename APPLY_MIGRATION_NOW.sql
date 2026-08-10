-- ============================================================================
-- ALSAMOS GLOBAL SEARCH - DATABASE MIGRATION
-- ============================================================================
-- Copy this entire script and run it in Supabase SQL Editor:
-- https://supabase.com/dashboard/project/YOUR_PROJECT/sql/new
-- ============================================================================

-- Step 1: Add search preferences columns to user_settings
ALTER TABLE user_settings 
ADD COLUMN IF NOT EXISTS search_safe_mode TEXT DEFAULT 'moderate',
ADD COLUMN IF NOT EXISTS search_region TEXT DEFAULT 'uz',
ADD COLUMN IF NOT EXISTS search_language TEXT DEFAULT 'uz';

-- Step 2: Create search_history table for user query history
CREATE TABLE IF NOT EXISTS search_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  query TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Step 3: Create search_cache table for caching search results
CREATE TABLE IF NOT EXISTS search_cache (
  cache_key TEXT PRIMARY KEY,
  results JSONB NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Step 4: Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_search_history_user_id ON search_history(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_search_history_created ON search_history(created_at);
CREATE INDEX IF NOT EXISTS idx_search_cache_created ON search_cache(created_at);

-- Step 5: Enable RLS on search_history
ALTER TABLE search_history ENABLE ROW LEVEL SECURITY;

-- Step 6: RLS Policy - Users can only access their own search history
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
    AND tablename = 'search_history' 
    AND policyname = 'search_history_user_policy'
  ) THEN
    CREATE POLICY search_history_user_policy ON search_history
      FOR ALL
      USING (auth.uid() = user_id)
      WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

-- Step 7: Auto-cleanup old search history (30 days)
CREATE OR REPLACE FUNCTION cleanup_old_search_history()
RETURNS void AS $$
BEGIN
  DELETE FROM search_history
  WHERE created_at < now() - interval '30 days';
END;
$$ LANGUAGE plpgsql;

-- Step 8: Auto-cleanup old cache entries (1 hour)
CREATE OR REPLACE FUNCTION cleanup_old_search_cache()
RETURNS void AS $$
BEGIN
  DELETE FROM search_cache
  WHERE created_at < now() - interval '1 hour';
END;
$$ LANGUAGE plpgsql;

-- Step 9: Grant permissions
GRANT SELECT, INSERT, DELETE ON search_history TO authenticated;
GRANT SELECT, INSERT, UPDATE ON search_cache TO service_role;

-- Step 10: Add comments for documentation
COMMENT ON TABLE search_history IS 'User web search query history';
COMMENT ON TABLE search_cache IS 'Cached search results (shared, TTL 1 hour)';
COMMENT ON COLUMN user_settings.search_safe_mode IS 'Safe search level: off, moderate, strict';
COMMENT ON COLUMN user_settings.search_region IS 'Search region code (uz, us, ru, etc)';
COMMENT ON COLUMN user_settings.search_language IS 'Search language code (uz, en, ru)';

-- ============================================================================
-- VERIFICATION QUERIES
-- ============================================================================
-- After running the migration, run these to verify:

-- 1. Check columns were added to user_settings
SELECT column_name, data_type, column_default 
FROM information_schema.columns 
WHERE table_name = 'user_settings' 
AND column_name IN ('search_safe_mode', 'search_region', 'search_language');

-- 2. Check tables were created
SELECT tablename FROM pg_tables 
WHERE schemaname = 'public' 
AND tablename IN ('search_history', 'search_cache');

-- 3. Check indexes were created
SELECT indexname FROM pg_indexes 
WHERE schemaname = 'public' 
AND indexname LIKE 'idx_search_%';

-- 4. Check RLS is enabled on search_history
SELECT tablename, rowsecurity FROM pg_tables 
WHERE schemaname = 'public' AND tablename = 'search_history';

-- 5. Check policy exists
SELECT policyname, cmd, qual FROM pg_policies 
WHERE schemaname = 'public' AND tablename = 'search_history';

-- ============================================================================
-- EXPECTED OUTPUT:
-- Query 1: 3 rows (search_safe_mode, search_region, search_language)
-- Query 2: 2 rows (search_history, search_cache)
-- Query 3: 3 rows (idx_search_history_user_id, idx_search_history_created, idx_search_cache_created)
-- Query 4: search_history | t (rowsecurity = true)
-- Query 5: search_history_user_policy | ALL | (auth.uid() = user_id)
-- ============================================================================

-- ============================================================================
-- POSTGREST SCHEMA CACHE RELOAD (CRITICAL!)
-- ============================================================================
-- After migration, PostgREST needs to reload its schema cache.
-- Option 1: Supabase Dashboard → Settings → API → "Restart API Server" button
-- Option 2: Run this function (requires service_role or postgres role):
NOTIFY pgrst, 'reload schema';

-- Or use Supabase CLI:
-- supabase functions invoke --method POST --project-ref YOUR_REF \
--   /rest/v1/ -H "Prefer: reload-schema"

-- ============================================================================
-- MIGRATION COMPLETE
-- ============================================================================
