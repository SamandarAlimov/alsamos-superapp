-- Migration: Global Web Search (FIXED)
-- Add search preferences to user_settings
ALTER TABLE user_settings
  ADD COLUMN IF NOT EXISTS search_safe_mode TEXT DEFAULT 'moderate',
  ADD COLUMN IF NOT EXISTS search_region   TEXT DEFAULT 'uz',
  ADD COLUMN IF NOT EXISTS search_language TEXT DEFAULT 'uz';

-- search_history table
CREATE TABLE IF NOT EXISTS search_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  query TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- search_cache table
CREATE TABLE IF NOT EXISTS search_cache (
  cache_key TEXT PRIMARY KEY,
  results JSONB NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_search_history_user_id ON search_history(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_search_history_created ON search_history(created_at);
CREATE INDEX IF NOT EXISTS idx_search_cache_created   ON search_cache(created_at);

-- RLS on search_history
ALTER TABLE search_history ENABLE ROW LEVEL SECURITY;

-- FIX: DROP + CREATE (CREATE POLICY IF NOT EXISTS o'rniga)
DROP POLICY IF EXISTS search_history_user_policy ON search_history;
CREATE POLICY search_history_user_policy ON search_history
  FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- Cleanup functions
CREATE OR REPLACE FUNCTION cleanup_old_search_history()
RETURNS void AS $$
BEGIN
  DELETE FROM search_history WHERE created_at < now() - interval '30 days';
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION cleanup_old_search_cache()
RETURNS void AS $$
BEGIN
  DELETE FROM search_cache WHERE created_at < now() - interval '1 hour';
END;
$$ LANGUAGE plpgsql;

-- Grants
GRANT SELECT, INSERT, DELETE ON search_history TO authenticated;
GRANT SELECT, INSERT, UPDATE ON search_cache TO service_role;

-- Comments
COMMENT ON TABLE  search_history IS 'User web search query history';
COMMENT ON TABLE  search_cache   IS 'Cached search results (shared, TTL 1 hour)';
COMMENT ON COLUMN user_settings.search_safe_mode IS 'Safe search level: off, moderate, strict';
COMMENT ON COLUMN user_settings.search_region    IS 'Search region code (uz, us, ru, etc)';
COMMENT ON COLUMN user_settings.search_language  IS 'Search language code (uz, en, ru)';

-- Reload API cache
NOTIFY pgrst, 'reload schema';