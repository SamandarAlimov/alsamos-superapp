-- Reconcile the web client's sticker schema with the canonical one.
--
-- Canonical source: 20260716000000_telegram_stickers.sql
--   sticker_packs(id, title, cover_url, cover_lottie_url, created_by,
--                 is_animated, created_at, updated_at)
--   stickers(id, pack_id, emoji, image_url, lottie_url, video_url,
--            thumbnail_url, type, position, created_at)
--   user_sticker_packs(user_id, pack_id, updated_at)
--   recent_stickers(user_id, sticker_id, use_count, last_used)
--
-- The web client independently expected slug / is_public / author_id on packs,
-- file_url / thumb_url / width / height on stickers, and two extra tables
-- (sticker_pack_installs, sticker_usage). Applying that version on top of the
-- canonical one fails, because CREATE TABLE IF NOT EXISTS is a no-op once the
-- table exists and the policies that follow reference columns that were never
-- added.
--
-- Resolution:
--   * the canonical tables stay authoritative
--   * missing columns are added and backfilled instead of recreated
--   * user_sticker_packs remains the single install table; the web client must
--     stop using sticker_pack_installs
--   * sticker_usage is created, because it is the only one of the two extra
--     tables that adds real capability (GIF recents)

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) sticker_packs: additive columns
-- ---------------------------------------------------------------------------

ALTER TABLE public.sticker_packs ADD COLUMN IF NOT EXISTS slug text;
ALTER TABLE public.sticker_packs ADD COLUMN IF NOT EXISTS is_public boolean NOT NULL DEFAULT true;
ALTER TABLE public.sticker_packs ADD COLUMN IF NOT EXISTS sticker_count integer NOT NULL DEFAULT 0;
ALTER TABLE public.sticker_packs ADD COLUMN IF NOT EXISTS install_count integer NOT NULL DEFAULT 0;

-- slug is nullable on purpose: existing rows predate it. Backfill a stable
-- value derived from the id so the unique index below can be created safely.
UPDATE public.sticker_packs
   SET slug = 'pack-' || left(replace(id::text, '-', ''), 10)
 WHERE slug IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS sticker_packs_slug_key
  ON public.sticker_packs(slug);

-- ---------------------------------------------------------------------------
-- 2) stickers: additive columns, backfilled from the canonical media columns
-- ---------------------------------------------------------------------------

ALTER TABLE public.stickers ADD COLUMN IF NOT EXISTS file_url text;
ALTER TABLE public.stickers ADD COLUMN IF NOT EXISTS thumb_url text;
ALTER TABLE public.stickers ADD COLUMN IF NOT EXISTS width integer;
ALTER TABLE public.stickers ADD COLUMN IF NOT EXISTS height integer;

UPDATE public.stickers
   SET file_url = COALESCE(file_url, image_url, video_url, lottie_url)
 WHERE file_url IS NULL;

UPDATE public.stickers
   SET thumb_url = COALESCE(thumb_url, thumbnail_url)
 WHERE thumb_url IS NULL;

-- The canonical `type` column is NOT NULL with no default, so any web insert
-- that omits it would fail. Give it a default instead of relaxing the check.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name = 'stickers'
       AND column_name = 'type'
  ) THEN
    ALTER TABLE public.stickers ALTER COLUMN type SET DEFAULT 'static';
  END IF;
END $$;

-- Keep the two naming conventions in sync in both directions, so neither
-- client has to know about the other's column names.
CREATE OR REPLACE FUNCTION public.sync_sticker_media_columns()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.file_url IS NULL THEN
    NEW.file_url := COALESCE(NEW.image_url, NEW.video_url, NEW.lottie_url);
  ELSIF NEW.image_url IS NULL AND NEW.video_url IS NULL AND NEW.lottie_url IS NULL THEN
    NEW.image_url := NEW.file_url;
  END IF;

  IF NEW.thumb_url IS NULL THEN
    NEW.thumb_url := NEW.thumbnail_url;
  ELSIF NEW.thumbnail_url IS NULL THEN
    NEW.thumbnail_url := NEW.thumb_url;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS sync_sticker_media_columns ON public.stickers;
CREATE TRIGGER sync_sticker_media_columns
BEFORE INSERT OR UPDATE ON public.stickers
FOR EACH ROW
EXECUTE FUNCTION public.sync_sticker_media_columns();

-- ---------------------------------------------------------------------------
-- 3) user_sticker_packs: single install table, plus manual ordering
-- ---------------------------------------------------------------------------

ALTER TABLE public.user_sticker_packs ADD COLUMN IF NOT EXISTS position integer NOT NULL DEFAULT 0;
ALTER TABLE public.user_sticker_packs ADD COLUMN IF NOT EXISTS installed_at timestamptz NOT NULL DEFAULT now();

CREATE INDEX IF NOT EXISTS idx_user_sticker_packs_position
  ON public.user_sticker_packs(user_id, position);

-- ---------------------------------------------------------------------------
-- 4) sticker_usage: frequently-used stickers AND GIFs
--
-- recent_stickers cannot serve this purpose: its sticker_id is a required
-- foreign key into stickers, so externally hosted GIFs have no row to point
-- at. sticker_usage is therefore keyed by url, with sticker_id optional.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.sticker_usage (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  file_url text NOT NULL,
  sticker_id uuid REFERENCES public.stickers(id) ON DELETE CASCADE,
  kind text NOT NULL DEFAULT 'sticker',
  use_count integer NOT NULL DEFAULT 1,
  last_used_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, file_url)
);

ALTER TABLE public.sticker_usage ADD COLUMN IF NOT EXISTS sticker_id uuid;
ALTER TABLE public.sticker_usage ADD COLUMN IF NOT EXISTS kind text NOT NULL DEFAULT 'sticker';
ALTER TABLE public.sticker_usage ADD COLUMN IF NOT EXISTS use_count integer NOT NULL DEFAULT 1;
ALTER TABLE public.sticker_usage ADD COLUMN IF NOT EXISTS last_used_at timestamptz NOT NULL DEFAULT now();

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'sticker_usage_kind_check'
  ) THEN
    ALTER TABLE public.sticker_usage
      ADD CONSTRAINT sticker_usage_kind_check CHECK (kind IN ('sticker', 'gif'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS sticker_usage_recent_idx
  ON public.sticker_usage(user_id, kind, last_used_at DESC);
CREATE INDEX IF NOT EXISTS sticker_usage_frequent_idx
  ON public.sticker_usage(user_id, kind, use_count DESC);

ALTER TABLE public.sticker_usage ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "sticker_usage_own" ON public.sticker_usage;
CREATE POLICY "sticker_usage_own" ON public.sticker_usage
  FOR ALL
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- Increment on every sticker or GIF send. Mirrors into recent_stickers when
-- the item is a real sticker row, so the Flutter client keeps working.
CREATE OR REPLACE FUNCTION public.touch_sticker_usage(
  p_file_url text,
  p_kind text DEFAULT 'sticker',
  p_sticker_id uuid DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL OR p_file_url IS NULL THEN
    RETURN;
  END IF;

  INSERT INTO public.sticker_usage (user_id, file_url, sticker_id, kind, use_count, last_used_at)
  VALUES (auth.uid(), p_file_url, p_sticker_id, COALESCE(p_kind, 'sticker'), 1, now())
  ON CONFLICT (user_id, file_url) DO UPDATE
    SET use_count = public.sticker_usage.use_count + 1,
        last_used_at = now(),
        kind = EXCLUDED.kind,
        sticker_id = COALESCE(EXCLUDED.sticker_id, public.sticker_usage.sticker_id);

  IF p_sticker_id IS NOT NULL THEN
    INSERT INTO public.recent_stickers (user_id, sticker_id, use_count, last_used)
    VALUES (auth.uid(), p_sticker_id, 1, now())
    ON CONFLICT (user_id, sticker_id) DO UPDATE
      SET use_count = public.recent_stickers.use_count + 1,
          last_used = now();
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- 5) Denormalised counters stay correct
-- ---------------------------------------------------------------------------

UPDATE public.sticker_packs p
   SET sticker_count = COALESCE(c.n, 0)
  FROM (SELECT pack_id, count(*) AS n FROM public.stickers GROUP BY pack_id) c
 WHERE c.pack_id = p.id
   AND p.sticker_count IS DISTINCT FROM COALESCE(c.n, 0);

UPDATE public.sticker_packs p
   SET install_count = COALESCE(c.n, 0)
  FROM (SELECT pack_id, count(*) AS n FROM public.user_sticker_packs GROUP BY pack_id) c
 WHERE c.pack_id = p.id
   AND p.install_count IS DISTINCT FROM COALESCE(c.n, 0);

COMMIT;

NOTIFY pgrst, 'reload schema';
