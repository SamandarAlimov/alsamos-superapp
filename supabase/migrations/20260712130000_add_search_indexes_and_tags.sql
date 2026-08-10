-- Search Enhancement Migration
-- Adds full-text search indexes and tags/hashtags functionality
-- Project: mbhjganbihamoiqmankv.supabase.co
-- Date: 2026-07-12
-- Run AFTER: 20260712120000_comprehensive_schema_sync.sql

-- ============================================================================
-- Full-text search indexes for posts
-- ============================================================================

-- Add tsvector column for efficient full-text search
ALTER TABLE posts 
ADD COLUMN IF NOT EXISTS content_search tsvector 
GENERATED ALWAYS AS (to_tsvector('english', COALESCE(content, ''))) STORED;

-- Create GIN index on tsvector column
CREATE INDEX IF NOT EXISTS idx_posts_content_search 
ON posts USING GIN(content_search);

-- Index for tag-based search (already exists from previous migration but ensuring it's there)
CREATE INDEX IF NOT EXISTS idx_posts_tags_gin 
ON posts USING GIN(tags) 
WHERE tags IS NOT NULL AND array_length(tags, 1) > 0;

COMMENT ON COLUMN posts.content_search IS 'Generated tsvector for full-text search on content';

-- ============================================================================
-- Products table: Ensure search-compatible columns exist
-- ============================================================================

-- Verify products table has required columns (add if missing)
ALTER TABLE products 
ADD COLUMN IF NOT EXISTS title text;

ALTER TABLE products 
ADD COLUMN IF NOT EXISTS description text;

ALTER TABLE products 
ADD COLUMN IF NOT EXISTS price numeric DEFAULT 0;

ALTER TABLE products 
ADD COLUMN IF NOT EXISTS currency text DEFAULT 'USD';

ALTER TABLE products 
ADD COLUMN IF NOT EXISTS status text DEFAULT 'active' 
CHECK (status IN ('active', 'draft', 'sold', 'deleted'));

-- Add tsvector for products search
ALTER TABLE products 
ADD COLUMN IF NOT EXISTS search_vector tsvector 
GENERATED ALWAYS AS (
  to_tsvector('english', 
    COALESCE(title, '') || ' ' || 
    COALESCE(description, '')
  )
) STORED;

-- Create GIN index on products search vector
CREATE INDEX IF NOT EXISTS idx_products_search_vector 
ON products USING GIN(search_vector);

-- Index for products status (for active filtering)
CREATE INDEX IF NOT EXISTS idx_products_status 
ON products(status);

COMMENT ON COLUMN products.search_vector IS 'Generated tsvector for full-text search on title and description';

-- ============================================================================
-- Materialized view for hashtags/tags aggregation
-- ============================================================================

-- Create materialized view that aggregates tags from posts
CREATE MATERIALIZED VIEW IF NOT EXISTS hashtags_aggregated AS
SELECT 
  UNNEST(tags) AS tag,
  COUNT(*) AS post_count,
  MAX(created_at) AS last_used_at
FROM posts
WHERE 
  tags IS NOT NULL 
  AND array_length(tags, 1) > 0
  AND visibility = 'public'
  AND (moderation_status IS NULL OR moderation_status = 'approved')
GROUP BY UNNEST(tags)
ORDER BY post_count DESC;

-- Create unique index on tag for fast lookups
CREATE UNIQUE INDEX IF NOT EXISTS idx_hashtags_aggregated_tag 
ON hashtags_aggregated(tag);

-- Index for sorting by popularity
CREATE INDEX IF NOT EXISTS idx_hashtags_aggregated_count 
ON hashtags_aggregated(post_count DESC);

-- Index for sorting by recency
CREATE INDEX IF NOT EXISTS idx_hashtags_aggregated_last_used 
ON hashtags_aggregated(last_used_at DESC);

COMMENT ON MATERIALIZED VIEW hashtags_aggregated IS 'Aggregated hashtag statistics from posts.tags array';

-- ============================================================================
-- Function to refresh hashtags (call after bulk post operations)
-- ============================================================================

CREATE OR REPLACE FUNCTION refresh_hashtags_aggregated()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  REFRESH MATERIALIZED VIEW CONCURRENTLY hashtags_aggregated;
END;
$$;

COMMENT ON FUNCTION refresh_hashtags_aggregated() IS 'Refreshes the hashtags_aggregated materialized view. Call periodically or after bulk operations.';

-- Initial refresh
REFRESH MATERIALIZED VIEW hashtags_aggregated;

-- ============================================================================
-- RLS for hashtags_aggregated (read-only, public)
-- ============================================================================

ALTER MATERIALIZED VIEW hashtags_aggregated OWNER TO postgres;

-- Note: Materialized views don't support RLS directly, but we can create a view wrapper
CREATE OR REPLACE VIEW hashtags AS
SELECT tag, post_count, last_used_at
FROM hashtags_aggregated
ORDER BY post_count DESC;

COMMENT ON VIEW hashtags IS 'Public read-only view of aggregated hashtags';

-- ============================================================================
-- Helper function: Extract hashtags from text
-- ============================================================================

CREATE OR REPLACE FUNCTION extract_hashtags(content text)
RETURNS text[]
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  matches text[];
BEGIN
  -- Extract all words starting with # (excluding the #)
  SELECT array_agg(DISTINCT LOWER(SUBSTRING(match FROM 2)))
  INTO matches
  FROM regexp_matches(content, '#([a-zA-Z0-9_]+)', 'g') AS match;
  
  RETURN COALESCE(matches, ARRAY[]::text[]);
END;
$$;

COMMENT ON FUNCTION extract_hashtags(text) IS 'Extracts hashtags from text content, returning array of lowercase tags without #';

-- ============================================================================
-- Trigger to auto-populate posts.tags from content
-- ============================================================================

CREATE OR REPLACE FUNCTION auto_extract_tags()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  -- Auto-extract tags from content if tags not explicitly set
  IF NEW.content IS NOT NULL AND (NEW.tags IS NULL OR array_length(NEW.tags, 1) IS NULL) THEN
    NEW.tags := extract_hashtags(NEW.content);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_auto_extract_tags ON posts;
CREATE TRIGGER trigger_auto_extract_tags
  BEFORE INSERT OR UPDATE OF content
  ON posts
  FOR EACH ROW
  EXECUTE FUNCTION auto_extract_tags();

COMMENT ON FUNCTION auto_extract_tags() IS 'Automatically extracts hashtags from post content and populates tags array';

-- ============================================================================
-- Reload API schema cache
-- ============================================================================
NOTIFY pgrst, 'reload schema';
