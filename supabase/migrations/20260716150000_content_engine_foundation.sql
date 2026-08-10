BEGIN;

ALTER TABLE public.posts
  ADD COLUMN IF NOT EXISTS content_type text NOT NULL DEFAULT 'text',
  ADD COLUMN IF NOT EXISTS effects_used text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS hashtags text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS location_lat double precision,
  ADD COLUMN IF NOT EXISTS location_lng double precision,
  ADD COLUMN IF NOT EXISTS location_name text,
  ADD COLUMN IF NOT EXISTS location_address text,
  ADD COLUMN IF NOT EXISTS location_geohash text;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'posts'
      AND column_name = 'tags'
  ) THEN
    UPDATE public.posts
    SET hashtags = tags
    WHERE (hashtags IS NULL OR hashtags = '{}'::text[])
      AND tags IS NOT NULL
      AND tags <> '{}'::text[];
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_posts_content_type_created
  ON public.posts(content_type, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_posts_hashtags_gin
  ON public.posts USING GIN(hashtags)
  WHERE hashtags IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_posts_location_lat_lng
  ON public.posts(location_lat, location_lng)
  WHERE location_lat IS NOT NULL AND location_lng IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_posts_location_geohash
  ON public.posts(location_geohash)
  WHERE location_geohash IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.post_product_tags (
  post_id uuid NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
  product_id uuid NOT NULL,
  tagged_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  position jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (post_id, product_id)
);

ALTER TABLE public.post_product_tags
  ADD COLUMN IF NOT EXISTS position jsonb;

DO $$
BEGIN
  IF to_regclass('public.products') IS NOT NULL
     AND NOT EXISTS (
       SELECT 1
       FROM pg_constraint
       WHERE conname = 'post_product_tags_product_id_fkey'
         AND conrelid = 'public.post_product_tags'::regclass
     ) THEN
    ALTER TABLE public.post_product_tags
      ADD CONSTRAINT post_product_tags_product_id_fkey
      FOREIGN KEY (product_id)
      REFERENCES public.products(id)
      ON DELETE CASCADE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_post_product_tags_product
  ON public.post_product_tags(product_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_post_product_tags_post
  ON public.post_product_tags(post_id);

ALTER TABLE public.post_product_tags ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public product tags are readable" ON public.post_product_tags;
CREATE POLICY "Public product tags are readable"
  ON public.post_product_tags FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.posts p
      WHERE p.id = post_product_tags.post_id
        AND (p.visibility = 'public' OR p.user_id = auth.uid())
    )
  );

DROP POLICY IF EXISTS "Post owners manage product tags" ON public.post_product_tags;
CREATE POLICY "Post owners manage product tags"
  ON public.post_product_tags FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.posts p
      WHERE p.id = post_product_tags.post_id
        AND p.user_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.posts p
      WHERE p.id = post_product_tags.post_id
        AND p.user_id = auth.uid()
    )
  );

CREATE TABLE IF NOT EXISTS public.post_hashtags (
  post_id uuid NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
  hashtag text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (post_id, hashtag)
);

CREATE INDEX IF NOT EXISTS idx_post_hashtags_hashtag_created
  ON public.post_hashtags(hashtag, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_post_hashtags_post
  ON public.post_hashtags(post_id);

ALTER TABLE public.post_hashtags ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public hashtags are readable" ON public.post_hashtags;
CREATE POLICY "Public hashtags are readable"
  ON public.post_hashtags FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.posts p
      WHERE p.id = post_hashtags.post_id
        AND (p.visibility = 'public' OR p.user_id = auth.uid())
    )
  );

DROP POLICY IF EXISTS "Post owners manage hashtags" ON public.post_hashtags;
CREATE POLICY "Post owners manage hashtags"
  ON public.post_hashtags FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.posts p
      WHERE p.id = post_hashtags.post_id
        AND p.user_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.posts p
      WHERE p.id = post_hashtags.post_id
        AND p.user_id = auth.uid()
    )
  );

CREATE OR REPLACE FUNCTION public.sync_post_hashtags_from_posts()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tag text;
  v_hashtags text[];
BEGIN
  DELETE FROM public.post_hashtags WHERE post_id = NEW.id;

  SELECT array_agg(value)
  INTO v_hashtags
  FROM jsonb_array_elements_text(COALESCE(to_jsonb(NEW)->'hashtags', '[]'::jsonb)) AS value;

  IF (v_hashtags IS NULL OR v_hashtags = '{}'::text[]) THEN
    SELECT array_agg(value)
    INTO v_hashtags
    FROM jsonb_array_elements_text(COALESCE(to_jsonb(NEW)->'tags', '[]'::jsonb)) AS value;
  END IF;

  IF v_hashtags IS NOT NULL THEN
    FOREACH v_tag IN ARRAY v_hashtags
    LOOP
      v_tag := lower(regexp_replace(trim(v_tag), '^#', ''));
      IF v_tag <> '' THEN
        INSERT INTO public.post_hashtags(post_id, hashtag)
        VALUES (NEW.id, v_tag)
        ON CONFLICT (post_id, hashtag) DO NOTHING;
      END IF;
    END LOOP;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS sync_post_hashtags_trigger ON public.posts;
CREATE TRIGGER sync_post_hashtags_trigger
  AFTER INSERT OR UPDATE
  ON public.posts
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_post_hashtags_from_posts();

INSERT INTO public.post_hashtags(post_id, hashtag)
SELECT p.id, lower(regexp_replace(trim(tag), '^#', ''))
FROM public.posts p
CROSS JOIN LATERAL unnest(p.hashtags) AS tag
WHERE p.hashtags IS NOT NULL
  AND trim(tag) <> ''
ON CONFLICT (post_id, hashtag) DO NOTHING;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'post_product_tags'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.post_product_tags;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'post_hashtags'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.post_hashtags;
  END IF;
END $$;

-- RLS audit: post_product_tags and post_hashtags expose public post metadata
-- publicly, while write access remains limited to the owner of the parent post.

COMMIT;

NOTIFY pgrst, 'reload schema';
