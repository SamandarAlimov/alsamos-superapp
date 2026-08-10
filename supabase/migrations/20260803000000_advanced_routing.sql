-- ═══════════════════════════════════════════════════════════════════════════
-- Advanced Routing Features Migration
-- Creates tables for: saved routes, live trips, route history
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE: saved_routes (favorite/frequent routes)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.saved_routes (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  origin TEXT NOT NULL, -- "lat,lng"
  destination TEXT NOT NULL, -- "lat,lng"
  origin_name TEXT,
  destination_name TEXT,
  mode TEXT NOT NULL DEFAULT 'driving', -- driving|walking|cycling|transit|taxi
  preference TEXT NOT NULL DEFAULT 'fastest', -- fastest|shortest|balanced|avoidHighways|avoidTolls
  use_count INTEGER DEFAULT 0,
  last_used_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

ALTER TABLE public.saved_routes ADD COLUMN IF NOT EXISTS user_id UUID;
ALTER TABLE public.saved_routes ADD COLUMN IF NOT EXISTS name TEXT;
ALTER TABLE public.saved_routes ADD COLUMN IF NOT EXISTS origin TEXT;
ALTER TABLE public.saved_routes ADD COLUMN IF NOT EXISTS destination TEXT;
ALTER TABLE public.saved_routes ADD COLUMN IF NOT EXISTS origin_name TEXT;
ALTER TABLE public.saved_routes ADD COLUMN IF NOT EXISTS destination_name TEXT;
ALTER TABLE public.saved_routes ADD COLUMN IF NOT EXISTS mode TEXT;
ALTER TABLE public.saved_routes ADD COLUMN IF NOT EXISTS preference TEXT;
ALTER TABLE public.saved_routes ADD COLUMN IF NOT EXISTS use_count INTEGER;
ALTER TABLE public.saved_routes ADD COLUMN IF NOT EXISTS last_used_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE public.saved_routes ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE;

CREATE INDEX IF NOT EXISTS idx_saved_routes_user ON public.saved_routes(user_id);
CREATE INDEX IF NOT EXISTS idx_saved_routes_usage ON public.saved_routes(user_id, use_count DESC, last_used_at DESC);

-- RLS
ALTER TABLE public.saved_routes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users manage own saved routes" ON public.saved_routes;
CREATE POLICY "Users manage own saved routes"
  ON public.saved_routes
  USING (auth.uid() = user_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE: live_trips (active trips with ETA sharing)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.live_trips (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  origin TEXT NOT NULL, -- "lat,lng"
  destination TEXT NOT NULL, -- "lat,lng"
  planned_route JSONB, -- [[lat,lng],[lat,lng],...]
  current_location TEXT, -- "lat,lng"
  progress DOUBLE PRECISION DEFAULT 0, -- 0-1
  started_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  estimated_arrival TIMESTAMP WITH TIME ZONE,
  is_active BOOLEAN DEFAULT true,
  shared_with TEXT[] DEFAULT '{}', -- Array of user IDs
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

ALTER TABLE public.live_trips ADD COLUMN IF NOT EXISTS user_id UUID;
ALTER TABLE public.live_trips ADD COLUMN IF NOT EXISTS origin TEXT;
ALTER TABLE public.live_trips ADD COLUMN IF NOT EXISTS destination TEXT;
ALTER TABLE public.live_trips ADD COLUMN IF NOT EXISTS planned_route JSONB;
ALTER TABLE public.live_trips ADD COLUMN IF NOT EXISTS current_location TEXT;
ALTER TABLE public.live_trips ADD COLUMN IF NOT EXISTS progress DOUBLE PRECISION;
ALTER TABLE public.live_trips ADD COLUMN IF NOT EXISTS started_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE public.live_trips ADD COLUMN IF NOT EXISTS estimated_arrival TIMESTAMP WITH TIME ZONE;
ALTER TABLE public.live_trips ADD COLUMN IF NOT EXISTS is_active BOOLEAN;
ALTER TABLE public.live_trips ADD COLUMN IF NOT EXISTS shared_with TEXT[];
ALTER TABLE public.live_trips ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE;

CREATE INDEX IF NOT EXISTS idx_live_trips_user ON public.live_trips(user_id);
CREATE INDEX IF NOT EXISTS idx_live_trips_active ON public.live_trips(is_active, started_at DESC) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_live_trips_shared ON public.live_trips USING GIN(shared_with);

-- RLS
ALTER TABLE public.live_trips ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users manage own trips" ON public.live_trips;
CREATE POLICY "Users manage own trips"
  ON public.live_trips
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users view shared trips" ON public.live_trips;
CREATE POLICY "Users view shared trips"
  ON public.live_trips FOR SELECT
  USING (
    auth.uid() = user_id 
    OR auth.uid()::text = ANY(shared_with)
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE: route_history (completed routes for analytics)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.route_history (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  origin TEXT NOT NULL,
  destination TEXT NOT NULL,
  origin_name TEXT,
  destination_name TEXT,
  mode TEXT NOT NULL DEFAULT 'driving',
  distance_meters DOUBLE PRECISION NOT NULL,
  duration_seconds INTEGER NOT NULL,
  actual_duration_seconds INTEGER, -- Real travel time if trip was tracked
  route_geometry JSONB, -- [[lat,lng],...]
  started_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  completed_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

ALTER TABLE public.route_history ADD COLUMN IF NOT EXISTS user_id UUID;
ALTER TABLE public.route_history ADD COLUMN IF NOT EXISTS origin TEXT;
ALTER TABLE public.route_history ADD COLUMN IF NOT EXISTS destination TEXT;
ALTER TABLE public.route_history ADD COLUMN IF NOT EXISTS origin_name TEXT;
ALTER TABLE public.route_history ADD COLUMN IF NOT EXISTS destination_name TEXT;
ALTER TABLE public.route_history ADD COLUMN IF NOT EXISTS mode TEXT;
ALTER TABLE public.route_history ADD COLUMN IF NOT EXISTS distance_meters DOUBLE PRECISION;
ALTER TABLE public.route_history ADD COLUMN IF NOT EXISTS duration_seconds INTEGER;
ALTER TABLE public.route_history ADD COLUMN IF NOT EXISTS actual_duration_seconds INTEGER;
ALTER TABLE public.route_history ADD COLUMN IF NOT EXISTS route_geometry JSONB;
ALTER TABLE public.route_history ADD COLUMN IF NOT EXISTS started_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE public.route_history ADD COLUMN IF NOT EXISTS completed_at TIMESTAMP WITH TIME ZONE;

CREATE INDEX IF NOT EXISTS idx_route_history_user ON public.route_history(user_id, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_route_history_mode ON public.route_history(user_id, mode);

-- RLS
ALTER TABLE public.route_history ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users manage own route history" ON public.route_history;
CREATE POLICY "Users manage own route history"
  ON public.route_history
  USING (auth.uid() = user_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- FUNCTION: Increment route use count
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.increment_route_use_count(route_id UUID)
RETURNS VOID AS $$
BEGIN
  UPDATE public.saved_routes
  SET 
    use_count = use_count + 1,
    last_used_at = now()
  WHERE id = route_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ─────────────────────────────────────────────────────────────────────────────
-- Triggers for updated_at
-- ─────────────────────────────────────────────────────────────────────────────
DROP TRIGGER IF EXISTS update_saved_routes_updated_at ON public.saved_routes;
CREATE TRIGGER update_saved_routes_updated_at
  BEFORE UPDATE ON public.saved_routes
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_live_trips_updated_at ON public.live_trips;
CREATE TRIGGER update_live_trips_updated_at
  BEFORE UPDATE ON public.live_trips
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

-- ─────────────────────────────────────────────────────────────────────────────
-- Realtime subscriptions
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' 
    AND schemaname = 'public' 
    AND tablename = 'live_trips'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.live_trips;
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Notify PostgREST to reload schema
-- ─────────────────────────────────────────────────────────────────────────────
NOTIFY pgrst, 'reload schema';
