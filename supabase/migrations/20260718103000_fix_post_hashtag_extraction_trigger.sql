BEGIN;

-- Fix legacy hashtag extraction for posts.
-- regexp_matches() returns text[], so the captured hashtag must be read from
-- the first array element before applying text operations.
CREATE OR REPLACE FUNCTION public.extract_hashtags(content text)
RETURNS text[]
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v_tags text[];
BEGIN
  SELECT COALESCE(
    array_agg(DISTINCT lower((m.match)[1]) ORDER BY lower((m.match)[1])),
    ARRAY[]::text[]
  )
  INTO v_tags
  FROM regexp_matches(COALESCE(content, ''), '#([A-Za-z0-9_]+)', 'g') AS m(match);

  RETURN v_tags;
END;
$$;

COMMENT ON FUNCTION public.extract_hashtags(text) IS
  'Extracts hashtags from text content, returning lowercase tags without #';

CREATE OR REPLACE FUNCTION public.auto_extract_tags()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Keep explicitly supplied tags. Only derive them when the array is missing
  -- or empty, which preserves the current Create UI publish payload.
  IF NEW.content IS NOT NULL
     AND (NEW.tags IS NULL OR cardinality(NEW.tags) = 0) THEN
    NEW.tags := public.extract_hashtags(NEW.content);
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.auto_extract_tags() IS
  'Automatically extracts hashtags from post content and populates tags array';

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'posts'
      AND column_name = 'tags'
  ) THEN
    DROP TRIGGER IF EXISTS trigger_auto_extract_tags ON public.posts;
    CREATE TRIGGER trigger_auto_extract_tags
      BEFORE INSERT OR UPDATE OF content, tags
      ON public.posts
      FOR EACH ROW
      EXECUTE FUNCTION public.auto_extract_tags();
  END IF;
END $$;

GRANT EXECUTE ON FUNCTION public.extract_hashtags(text) TO authenticated, anon;

COMMIT;

NOTIFY pgrst, 'reload schema';
