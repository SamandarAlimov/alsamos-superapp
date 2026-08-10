-- ═══════════════════════════════════════════════════════════════════════════
-- Alsamos Map P0 Features Migration
-- Creates tables for: POI caching, saved places, step history, taxi live locations
-- ═══════════════════════════════════════════════════════════════════════════

-- Ensure update_updated_at_column function exists
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE: map_pois (OSM Overpass cache)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.map_pois (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  osm_id TEXT NOT NULL UNIQUE,
  osm_type TEXT NOT NULL, -- node/way/relation
  category TEXT NOT NULL, -- restaurant|cafe|gas|atm|bank|pharmacy|hospital|shop
  name TEXT,
  latitude DOUBLE PRECISION NOT NULL,
  longitude DOUBLE PRECISION NOT NULL,
  tags JSONB DEFAULT '{}'::jsonb,
  address TEXT,
  phone TEXT,
  website TEXT,
  opening_hours TEXT,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Add columns if they don't exist (for idempotency)
ALTER TABLE public.map_pois ADD COLUMN IF NOT EXISTS osm_id TEXT;
ALTER TABLE public.map_pois ADD COLUMN IF NOT EXISTS osm_type TEXT;
ALTER TABLE public.map_pois ADD COLUMN IF NOT EXISTS category TEXT;
ALTER TABLE public.map_pois ADD COLUMN IF NOT EXISTS name TEXT;
ALTER TABLE public.map_pois ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION;
ALTER TABLE public.map_pois ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION;
ALTER TABLE public.map_pois ADD COLUMN IF NOT EXISTS tags JSONB;
ALTER TABLE public.map_pois ADD COLUMN IF NOT EXISTS address TEXT;
ALTER TABLE public.map_pois ADD COLUMN IF NOT EXISTS phone TEXT;
ALTER TABLE public.map_pois ADD COLUMN IF NOT EXISTS website TEXT;
ALTER TABLE public.map_pois ADD COLUMN IF NOT EXISTS opening_hours TEXT;
ALTER TABLE public.map_pois ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE;

-- Indexes for efficient spatial queries
CREATE INDEX IF NOT EXISTS idx_map_pois_category ON public.map_pois(category);
CREATE INDEX IF NOT EXISTS idx_map_pois_location ON public.map_pois(latitude, longitude);
CREATE INDEX IF NOT EXISTS idx_map_pois_updated ON public.map_pois(updated_at DESC);

-- RLS: Public read access (cached OSM data), no write from client
ALTER TABLE public.map_pois ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public read access to POI cache" ON public.map_pois;
CREATE POLICY "Public read access to POI cache"
  ON public.map_pois FOR SELECT
  USING (true);

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE: saved_place_lists (user's custom place collections)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.saved_place_lists (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT,
  icon TEXT,
  color TEXT,
  is_default BOOLEAN DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

ALTER TABLE public.saved_place_lists ADD COLUMN IF NOT EXISTS user_id UUID;
ALTER TABLE public.saved_place_lists ADD COLUMN IF NOT EXISTS name TEXT;
ALTER TABLE public.saved_place_lists ADD COLUMN IF NOT EXISTS description TEXT;
ALTER TABLE public.saved_place_lists ADD COLUMN IF NOT EXISTS icon TEXT;
ALTER TABLE public.saved_place_lists ADD COLUMN IF NOT EXISTS color TEXT;
ALTER TABLE public.saved_place_lists ADD COLUMN IF NOT EXISTS is_default BOOLEAN;
ALTER TABLE public.saved_place_lists ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE;

CREATE INDEX IF NOT EXISTS idx_saved_place_lists_user ON public.saved_place_lists(user_id);

ALTER TABLE public.saved_place_lists ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users manage own place lists" ON public.saved_place_lists;
CREATE POLICY "Users manage own place lists"
  ON public.saved_place_lists
  USING (auth.uid() = user_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE: saved_places (bookmarked locations)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.saved_places (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  list_id UUID REFERENCES public.saved_place_lists(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  latitude DOUBLE PRECISION NOT NULL,
  longitude DOUBLE PRECISION NOT NULL,
  address TEXT,
  notes TEXT,
  icon TEXT,
  is_favorite BOOLEAN DEFAULT false,
  visited_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

ALTER TABLE public.saved_places ADD COLUMN IF NOT EXISTS user_id UUID;
ALTER TABLE public.saved_places ADD COLUMN IF NOT EXISTS list_id UUID;
ALTER TABLE public.saved_places ADD COLUMN IF NOT EXISTS name TEXT;
ALTER TABLE public.saved_places ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION;
ALTER TABLE public.saved_places ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION;
ALTER TABLE public.saved_places ADD COLUMN IF NOT EXISTS address TEXT;
ALTER TABLE public.saved_places ADD COLUMN IF NOT EXISTS notes TEXT;
ALTER TABLE public.saved_places ADD COLUMN IF NOT EXISTS icon TEXT;
ALTER TABLE public.saved_places ADD COLUMN IF NOT EXISTS is_favorite BOOLEAN;
ALTER TABLE public.saved_places ADD COLUMN IF NOT EXISTS visited_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE public.saved_places ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE;

CREATE INDEX IF NOT EXISTS idx_saved_places_user ON public.saved_places(user_id);
CREATE INDEX IF NOT EXISTS idx_saved_places_list ON public.saved_places(list_id);
CREATE INDEX IF NOT EXISTS idx_saved_places_favorite ON public.saved_places(user_id, is_favorite) WHERE is_favorite = true;

ALTER TABLE public.saved_places ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users manage own saved places" ON public.saved_places;
CREATE POLICY "Users manage own saved places"
  ON public.saved_places
  USING (auth.uid() = user_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE: step_history (pedometer daily tracking)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.step_history (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  date DATE NOT NULL,
  steps INTEGER NOT NULL DEFAULT 0,
  distance_meters DOUBLE PRECISION DEFAULT 0,
  calories_burned INTEGER DEFAULT 0,
  active_minutes INTEGER DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  UNIQUE(user_id, date)
);

ALTER TABLE public.step_history ADD COLUMN IF NOT EXISTS user_id UUID;
ALTER TABLE public.step_history ADD COLUMN IF NOT EXISTS date DATE;
ALTER TABLE public.step_history ADD COLUMN IF NOT EXISTS steps INTEGER;
ALTER TABLE public.step_history ADD COLUMN IF NOT EXISTS distance_meters DOUBLE PRECISION;
ALTER TABLE public.step_history ADD COLUMN IF NOT EXISTS calories_burned INTEGER;
ALTER TABLE public.step_history ADD COLUMN IF NOT EXISTS active_minutes INTEGER;
ALTER TABLE public.step_history ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE;

CREATE INDEX IF NOT EXISTS idx_step_history_user_date ON public.step_history(user_id, date DESC);

ALTER TABLE public.step_history ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users manage own step history" ON public.step_history;
CREATE POLICY "Users manage own step history"
  ON public.step_history
  USING (auth.uid() = user_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE: taxi_live_locations (real-time driver positions)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.taxi_live_locations (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  driver_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  latitude DOUBLE PRECISION NOT NULL,
  longitude DOUBLE PRECISION NOT NULL,
  heading DOUBLE PRECISION, -- bearing in degrees
  speed_kmh DOUBLE PRECISION,
  is_available BOOLEAN DEFAULT true,
  is_on_trip BOOLEAN DEFAULT false,
  vehicle_type TEXT, -- sedan|suv|van|etc
  license_plate TEXT,
  last_updated TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

ALTER TABLE public.taxi_live_locations ADD COLUMN IF NOT EXISTS driver_id UUID;
ALTER TABLE public.taxi_live_locations ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION;
ALTER TABLE public.taxi_live_locations ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION;
ALTER TABLE public.taxi_live_locations ADD COLUMN IF NOT EXISTS heading DOUBLE PRECISION;
ALTER TABLE public.taxi_live_locations ADD COLUMN IF NOT EXISTS speed_kmh DOUBLE PRECISION;
ALTER TABLE public.taxi_live_locations ADD COLUMN IF NOT EXISTS is_available BOOLEAN;
ALTER TABLE public.taxi_live_locations ADD COLUMN IF NOT EXISTS is_on_trip BOOLEAN;
ALTER TABLE public.taxi_live_locations ADD COLUMN IF NOT EXISTS vehicle_type TEXT;
ALTER TABLE public.taxi_live_locations ADD COLUMN IF NOT EXISTS license_plate TEXT;
ALTER TABLE public.taxi_live_locations ADD COLUMN IF NOT EXISTS last_updated TIMESTAMP WITH TIME ZONE;

CREATE UNIQUE INDEX IF NOT EXISTS idx_taxi_locations_driver ON public.taxi_live_locations(driver_id);
CREATE INDEX IF NOT EXISTS idx_taxi_locations_available ON public.taxi_live_locations(is_available, is_on_trip) WHERE is_available = true AND is_on_trip = false;
CREATE INDEX IF NOT EXISTS idx_taxi_locations_updated ON public.taxi_live_locations(last_updated DESC);

ALTER TABLE public.taxi_live_locations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public read access to available taxis" ON public.taxi_live_locations;
CREATE POLICY "Public read access to available taxis"
  ON public.taxi_live_locations FOR SELECT
  USING (is_available = true);

DROP POLICY IF EXISTS "Drivers manage own location" ON public.taxi_live_locations;
CREATE POLICY "Drivers manage own location"
  ON public.taxi_live_locations
  USING (auth.uid() = driver_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE: map_incidents (user-generated content: traffic, hazards, police, etc)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.map_incidents (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  reporter_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  kind TEXT NOT NULL, -- accident|hazard|police|roadwork|traffic|closure|other
  latitude DOUBLE PRECISION NOT NULL,
  longitude DOUBLE PRECISION NOT NULL,
  description TEXT,
  severity TEXT DEFAULT 'medium', -- low|medium|high
  photo_url TEXT,
  upvotes INTEGER DEFAULT 0,
  downvotes INTEGER DEFAULT 0,
  expires_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

ALTER TABLE public.map_incidents ADD COLUMN IF NOT EXISTS reporter_id UUID;
ALTER TABLE public.map_incidents ADD COLUMN IF NOT EXISTS kind TEXT;
ALTER TABLE public.map_incidents ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION;
ALTER TABLE public.map_incidents ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION;
ALTER TABLE public.map_incidents ADD COLUMN IF NOT EXISTS description TEXT;
ALTER TABLE public.map_incidents ADD COLUMN IF NOT EXISTS severity TEXT;
ALTER TABLE public.map_incidents ADD COLUMN IF NOT EXISTS photo_url TEXT;
ALTER TABLE public.map_incidents ADD COLUMN IF NOT EXISTS upvotes INTEGER;
ALTER TABLE public.map_incidents ADD COLUMN IF NOT EXISTS downvotes INTEGER;
ALTER TABLE public.map_incidents ADD COLUMN IF NOT EXISTS expires_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE public.map_incidents ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE;

CREATE INDEX IF NOT EXISTS idx_map_incidents_location ON public.map_incidents(latitude, longitude);
CREATE INDEX IF NOT EXISTS idx_map_incidents_kind ON public.map_incidents(kind);
CREATE INDEX IF NOT EXISTS idx_map_incidents_expires ON public.map_incidents(expires_at, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_map_incidents_active ON public.map_incidents(created_at DESC);

ALTER TABLE public.map_incidents ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public read active incidents" ON public.map_incidents;
CREATE POLICY "Public read active incidents"
  ON public.map_incidents FOR SELECT
  USING (expires_at IS NULL OR expires_at > now());

DROP POLICY IF EXISTS "Authenticated users create incidents" ON public.map_incidents;
CREATE POLICY "Authenticated users create incidents"
  ON public.map_incidents FOR INSERT
  WITH CHECK (auth.uid() = reporter_id);

DROP POLICY IF EXISTS "Reporters update own incidents" ON public.map_incidents;
CREATE POLICY "Reporters update own incidents"
  ON public.map_incidents FOR UPDATE
  USING (auth.uid() = reporter_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- Triggers for updated_at
-- ─────────────────────────────────────────────────────────────────────────────
DROP TRIGGER IF EXISTS update_map_pois_updated_at ON public.map_pois;
CREATE TRIGGER update_map_pois_updated_at
  BEFORE UPDATE ON public.map_pois
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_saved_place_lists_updated_at ON public.saved_place_lists;
CREATE TRIGGER update_saved_place_lists_updated_at
  BEFORE UPDATE ON public.saved_place_lists
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_saved_places_updated_at ON public.saved_places;
CREATE TRIGGER update_saved_places_updated_at
  BEFORE UPDATE ON public.saved_places
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_step_history_updated_at ON public.step_history;
CREATE TRIGGER update_step_history_updated_at
  BEFORE UPDATE ON public.step_history
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_map_incidents_updated_at ON public.map_incidents;
CREATE TRIGGER update_map_incidents_updated_at
  BEFORE UPDATE ON public.map_incidents
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

-- ─────────────────────────────────────────────────────────────────────────────
-- Realtime subscriptions for live updates
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' 
    AND schemaname = 'public' 
    AND tablename = 'taxi_live_locations'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.taxi_live_locations;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' 
    AND schemaname = 'public' 
    AND tablename = 'map_incidents'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.map_incidents;
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Notify PostgREST to reload schema
-- ─────────────────────────────────────────────────────────────────────────────
NOTIFY pgrst, 'reload schema';
