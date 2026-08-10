BEGIN;

ALTER TABLE public.posts
  ADD COLUMN IF NOT EXISTS source_type text NOT NULL DEFAULT 'user',
  ADD COLUMN IF NOT EXISTS source_conversation_id uuid REFERENCES public.conversations(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_posts_public_source_trending
  ON public.posts (
    visibility,
    source_type,
    likes_count DESC,
    comments_count DESC,
    views_count DESC,
    created_at DESC
  )
  WHERE visibility = 'public';

CREATE INDEX IF NOT EXISTS idx_posts_source_conversation
  ON public.posts(source_conversation_id, created_at DESC)
  WHERE source_conversation_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.trending_public_posts(p_limit integer DEFAULT 12)
RETURNS SETOF public.posts
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p.*
  FROM public.posts p
  WHERE p.visibility = 'public'
    AND COALESCE(p.moderation_status, 'approved') <> 'rejected'
    AND p.source_type IN ('channel', 'group', 'public_channel', 'public_group')
  ORDER BY
    COALESCE(p.likes_count, 0) DESC,
    COALESCE(p.comments_count, 0) DESC,
    COALESCE(p.views_count, 0) DESC,
    p.created_at DESC
  LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 12), 50));
$$;

GRANT EXECUTE ON FUNCTION public.trending_public_posts(integer)
  TO anon, authenticated;

COMMIT;
NOTIFY pgrst, 'reload schema';
