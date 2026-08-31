-- Reconcile the web client's map schema with the canonical one.
--
-- Canonical sources:
--   20260712200000_map_p0_features.sql
--     map_pois, saved_place_lists, saved_places, step_history,
--     taxi_live_locations, map_incidents
--   20260803020000_social_map_features.sql
--     check_ins, place_reviews, review_helpful_votes,
--     meet_here_invitations, family_circles, circle_invitations,
--     place_statistics (materialized view)
--
-- The web client independently assumed:
--   saved_places(place_key, collection, category)   -> canonical uses list_id
--   place_reviews(place_key, comment)               -> canonical uses place_id, review_text
--   place_visits, taxi_providers                    -> genuinely new
--   place_rating_summary(p_place_key)               -> canonical has place_statistics
--
-- This is why the reported failure happened:
--   ERROR: 42703: column "collection" does not exist
-- saved_places already existed, CREATE TABLE IF NOT EXISTS did nothing, and the
-- following CREATE INDEX referenced a column that was never added.
--
-- Resolution: the canonical tables stay authoritative. Missing columns are
-- added, backfilled, and kept in sync by triggers, so both clients can read and
-- write either naming.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) saved_places: text collection alongside the canonical list_id
-- ---------------------------------------------------------------------------

ALTER TABLE public.saved_places ADD COLUMN IF NOT EXISTS collection text NOT NULL DEFAULT 'default';
ALTER TABLE public.saved_places ADD COLUMN IF NOT EXISTS category text;
ALTER TABLE public.saved_places ADD COLUMN IF NOT EXISTS place_key text;

-- place_key identifies an external POI. Derive a stable fallback from the
-- coordinates so the unique index below cannot collide on legacy rows.
UPDATE public.saved_places
   SET place_key = round(latitude::numeric, 5)::text || ',' || round(longitude::numeric, 5)::text
 WHERE place_key IS NULL
   AND latitude IS NOT NULL
   AND longitude IS NOT NULL;

CREATE INDEX IF NOT EXISTS saved_places_user_idx ON public.saved_places(user_id);
CREATE INDEX IF NOT EXISTS saved_places_collection_idx ON public.saved_places(user_id, collection);
CREATE UNIQUE INDEX IF NOT EXISTS saved_places_unique_idx
  ON public.saved_places(user_id, place_key)
  WHERE place_key IS NOT NULL;

-- A saved place created through a named list should report that list name as
-- its collection, and vice versa, so neither client sees an empty grouping.
CREATE OR REPLACE FUNCTION public.sync_saved_place_collection()
RETURNS TRIGGER AS $$
DECLARE
  v_list_name text;
BEGIN
  IF NEW.place_key IS NULL AND NEW.latitude IS NOT NULL AND NEW.longitude IS NOT NULL THEN
    NEW.place_key := round(NEW.latitude::numeric, 5)::text || ',' || round(NEW.longitude::numeric, 5)::text;
  END IF;

  IF NEW.list_id IS NOT NULL THEN
    SELECT name INTO v_list_name FROM public.saved_place_lists WHERE id = NEW.list_id;
    IF v_list_name IS NOT NULL AND (NEW.collection IS NULL OR NEW.collection = 'default') THEN
      NEW.collection := v_list_name;
    END IF;
  END IF;

  IF NEW.collection IS NULL THEN
    NEW.collection := 'default';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS sync_saved_place_collection ON public.saved_places;
CREATE TRIGGER sync_saved_place_collection
BEFORE INSERT OR UPDATE ON public.saved_places
FOR EACH ROW
EXECUTE FUNCTION public.sync_saved_place_collection();

-- ---------------------------------------------------------------------------
-- 2) place_reviews: place_key / comment aliases over place_id / review_text
-- ---------------------------------------------------------------------------

ALTER TABLE public.place_reviews ADD COLUMN IF NOT EXISTS place_key text;
ALTER TABLE public.place_reviews ADD COLUMN IF NOT EXISTS comment text;

UPDATE public.place_reviews SET place_key = place_id WHERE place_key IS NULL;
UPDATE public.place_reviews SET comment = review_text WHERE comment IS NULL AND review_text IS NOT NULL;

CREATE INDEX IF NOT EXISTS place_reviews_place_idx ON public.place_reviews(place_key);
CREATE INDEX IF NOT EXISTS place_reviews_user_place_idx ON public.place_reviews(user_id, place_key);

-- place_id and place_name are NOT NULL on the canonical table, so a web insert
-- that only supplies place_key and comment would fail. Fill them here.
CREATE OR REPLACE FUNCTION public.sync_place_review_aliases()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.place_id IS NULL THEN
    NEW.place_id := NEW.place_key;
  ELSIF NEW.place_key IS NULL THEN
    NEW.place_key := NEW.place_id;
  END IF;

  IF NEW.review_text IS NULL THEN
    NEW.review_text := NEW.comment;
  ELSIF NEW.comment IS NULL THEN
    NEW.comment := NEW.review_text;
  END IF;

  IF NEW.place_name IS NULL THEN
    NEW.place_name := COALESCE(NEW.place_key, 'Nomsiz joy');
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS sync_place_review_aliases ON public.place_reviews;
CREATE TRIGGER sync_place_review_aliases
BEFORE INSERT OR UPDATE ON public.place_reviews
FOR EACH ROW
EXECUTE FUNCTION public.sync_place_review_aliases();

-- The web client calls place_rating_summary. The canonical equivalent is the
-- place_statistics materialized view, which is only refreshed periodically, so
-- this reads the base table directly and stays live.
CREATE OR REPLACE FUNCTION public.place_rating_summary(p_place_key text)
RETURNS TABLE (average_rating numeric, review_count integer)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT
    COALESCE(round(AVG(rating)::numeric, 2), 0)::numeric AS average_rating,
    COUNT(*)::integer AS review_count
  FROM public.place_reviews
  WHERE place_key = p_place_key OR place_id = p_place_key;
$$;

-- ---------------------------------------------------------------------------
-- 3) place_visits: automatic dwell tracking. Genuinely new.
--
-- Distinct from check_ins: check-ins are deliberate and social, visits are
-- passive and private.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.place_visits (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name text,
  address text,
  category text,
  latitude double precision NOT NULL,
  longitude double precision NOT NULL,
  dwell_seconds integer NOT NULL DEFAULT 0,
  source text NOT NULL DEFAULT 'auto',
  device_id text,
  arrived_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.place_visits ADD COLUMN IF NOT EXISTS name text;
ALTER TABLE public.place_visits ADD COLUMN IF NOT EXISTS address text;
ALTER TABLE public.place_visits ADD COLUMN IF NOT EXISTS category text;
ALTER TABLE public.place_visits ADD COLUMN IF NOT EXISTS dwell_seconds integer NOT NULL DEFAULT 0;
ALTER TABLE public.place_visits ADD COLUMN IF NOT EXISTS source text NOT NULL DEFAULT 'auto';
ALTER TABLE public.place_visits ADD COLUMN IF NOT EXISTS device_id text;
ALTER TABLE public.place_visits ADD COLUMN IF NOT EXISTS arrived_at timestamptz NOT NULL DEFAULT now();

CREATE INDEX IF NOT EXISTS place_visits_user_idx ON public.place_visits(user_id, arrived_at DESC);
CREATE INDEX IF NOT EXISTS place_visits_geo_idx ON public.place_visits(latitude, longitude);

ALTER TABLE public.place_visits ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "place_visits_own" ON public.place_visits;
CREATE POLICY "place_visits_own" ON public.place_visits
  FOR ALL
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- Upsert-like: extend the dwell time of a recent nearby visit instead of
-- inserting a duplicate row every time the tracker syncs.
CREATE OR REPLACE FUNCTION public.track_place_visit(
  p_latitude double precision,
  p_longitude double precision,
  p_name text DEFAULT NULL,
  p_address text DEFAULT NULL,
  p_category text DEFAULT NULL,
  p_dwell_seconds integer DEFAULT 0,
  p_source text DEFAULT 'auto',
  p_device_id text DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
BEGIN
  IF auth.uid() IS NULL OR p_latitude IS NULL OR p_longitude IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT id INTO v_id
    FROM public.place_visits
   WHERE user_id = auth.uid()
     AND arrived_at > now() - interval '6 hours'
     AND abs(latitude - p_latitude) < 0.0015
     AND abs(longitude - p_longitude) < 0.0015
   ORDER BY arrived_at DESC
   LIMIT 1;

  IF v_id IS NOT NULL THEN
    UPDATE public.place_visits
       SET dwell_seconds = GREATEST(dwell_seconds, COALESCE(p_dwell_seconds, 0)),
           name = COALESCE(name, p_name),
           address = COALESCE(address, p_address),
           category = COALESCE(category, p_category)
     WHERE id = v_id;
    RETURN v_id;
  END IF;

  INSERT INTO public.place_visits (
    user_id, name, address, category, latitude, longitude,
    dwell_seconds, source, device_id
  ) VALUES (
    auth.uid(), p_name, p_address, p_category, p_latitude, p_longitude,
    COALESCE(p_dwell_seconds, 0), COALESCE(p_source, 'auto'), p_device_id
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

-- ---------------------------------------------------------------------------
-- 4) taxi_providers: external taxi services we deep-link into. Genuinely new.
--
-- Not related to taxi_live_locations, which tracks our own drivers. We are not
-- running a fleet, we are handing off to existing operators, so deep-link
-- templates and tariffs live in the client (src/lib/taxiProviders.ts) and only
-- the enable/disable state and ordering are stored here.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.taxi_providers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug text NOT NULL,
  name text NOT NULL,
  logo_url text,
  base_fare numeric,
  per_km numeric,
  per_min numeric,
  currency text NOT NULL DEFAULT 'UZS',
  is_active boolean NOT NULL DEFAULT true,
  position integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.taxi_providers ADD COLUMN IF NOT EXISTS logo_url text;
ALTER TABLE public.taxi_providers ADD COLUMN IF NOT EXISTS base_fare numeric;
ALTER TABLE public.taxi_providers ADD COLUMN IF NOT EXISTS per_km numeric;
ALTER TABLE public.taxi_providers ADD COLUMN IF NOT EXISTS per_min numeric;
ALTER TABLE public.taxi_providers ADD COLUMN IF NOT EXISTS currency text NOT NULL DEFAULT 'UZS';
ALTER TABLE public.taxi_providers ADD COLUMN IF NOT EXISTS is_active boolean NOT NULL DEFAULT true;
ALTER TABLE public.taxi_providers ADD COLUMN IF NOT EXISTS position integer NOT NULL DEFAULT 0;

CREATE UNIQUE INDEX IF NOT EXISTS taxi_providers_slug_key ON public.taxi_providers(slug);

ALTER TABLE public.taxi_providers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "taxi_providers_read" ON public.taxi_providers;
CREATE POLICY "taxi_providers_read" ON public.taxi_providers
  FOR SELECT
  USING (true);

INSERT INTO public.taxi_providers (slug, name, position)
VALUES
  ('yandex_go', 'Yandex Go', 1),
  ('yandex_maps_taxi', 'Yandex Maps Taxi', 2),
  ('mytaxi', 'MyTaxi', 3),
  ('indrive', 'inDrive', 4),
  ('millennium', 'Millennium', 5)
ON CONFLICT (slug) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 5) products: coordinates for the nearby-listings filter
-- ---------------------------------------------------------------------------

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
     WHERE table_schema = 'public' AND table_name = 'products'
  ) THEN
    ALTER TABLE public.products ADD COLUMN IF NOT EXISTS latitude double precision;
    ALTER TABLE public.products ADD COLUMN IF NOT EXISTS longitude double precision;
    CREATE INDEX IF NOT EXISTS products_geo_idx ON public.products(latitude, longitude);
  END IF;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';
