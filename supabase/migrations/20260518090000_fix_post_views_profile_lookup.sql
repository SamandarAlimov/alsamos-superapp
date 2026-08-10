-- Make post and story viewer lists fast and safely joinable with public profiles.
CREATE INDEX IF NOT EXISTS idx_post_views_post_id_viewed_at
ON public.post_views (post_id, viewed_at DESC);

CREATE INDEX IF NOT EXISTS idx_post_views_user_id
ON public.post_views (user_id);

CREATE INDEX IF NOT EXISTS idx_story_views_story_id_viewed_at
ON public.story_views (story_id, viewed_at DESC);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'post_views_user_id_profiles_fkey'
      AND conrelid = 'public.post_views'::regclass
  ) THEN
    ALTER TABLE public.post_views
      ADD CONSTRAINT post_views_user_id_profiles_fkey
      FOREIGN KEY (user_id)
      REFERENCES public.profiles(id)
      ON DELETE CASCADE
      NOT VALID;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'story_views_viewer_id_profiles_fkey'
      AND conrelid = 'public.story_views'::regclass
  ) THEN
    ALTER TABLE public.story_views
      ADD CONSTRAINT story_views_viewer_id_profiles_fkey
      FOREIGN KEY (viewer_id)
      REFERENCES public.profiles(id)
      ON DELETE CASCADE
      NOT VALID;
  END IF;
END $$;
