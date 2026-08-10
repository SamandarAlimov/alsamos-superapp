-- RPC function for tag search (fallback when materialized view not available)
-- Project: mbhjganbihamoiqmankv.supabase.co
-- Date: 2026-07-12

CREATE OR REPLACE FUNCTION search_tags(search_term text)
RETURNS TABLE (
  tag text,
  post_count bigint,
  last_used_at timestamptz
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    UNNEST(posts.tags) AS tag,
    COUNT(*) AS post_count,
    MAX(posts.created_at) AS last_used_at
  FROM posts
  WHERE 
    posts.tags IS NOT NULL 
    AND array_length(posts.tags, 1) > 0
    AND posts.visibility = 'public'
    AND (posts.moderation_status IS NULL OR posts.moderation_status = 'approved')
    AND UNNEST(posts.tags) ILIKE ('%' || search_term || '%')
  GROUP BY UNNEST(posts.tags)
  ORDER BY post_count DESC
  LIMIT 20;
END;
$$;

COMMENT ON FUNCTION search_tags(text) IS 'Searches for hashtags matching the search term, returns tag statistics';

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION search_tags(text) TO authenticated;
GRANT EXECUTE ON FUNCTION search_tags(text) TO anon;

-- Reload schema
NOTIFY pgrst, 'reload schema';
