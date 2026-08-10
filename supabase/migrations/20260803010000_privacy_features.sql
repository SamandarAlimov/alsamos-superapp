-- ═══════════════════════════════════════════════════════════════════════════
-- Privacy Features Migration
-- Creates tables for: privacy settings, privacy zones, location share tokens
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE: privacy_settings (user privacy preferences)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.privacy_settings (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  visibility TEXT NOT NULL DEFAULT 'followers', -- public|followers|friends|family|selected|nobody
  ghost_mode_enabled BOOLEAN DEFAULT false,
  incognito_mode_enabled BOOLEAN DEFAULT false,
  share_history BOOLEAN DEFAULT true,
  share_accurate_location BOOLEAN DEFAULT true,
  blocked_users TEXT[] DEFAULT '{}',
  allowed_users TEXT[] DEFAULT '{}',
  pause_tracking BOOLEAN DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

ALTER TABLE public.privacy_settings ADD COLUMN IF NOT EXISTS user_id UUID;
ALTER TABLE public.privacy_settings ADD COLUMN IF NOT EXISTS visibility TEXT;
ALTER TABLE public.privacy_settings ADD COLUMN IF NOT EXISTS ghost_mode_enabled BOOLEAN;
ALTER TABLE public.privacy_settings ADD COLUMN IF NOT EXISTS incognito_mode_enabled BOOLEAN;
ALTER TABLE public.privacy_settings ADD COLUMN IF NOT EXISTS share_history BOOLEAN;
ALTER TABLE public.privacy_settings ADD COLUMN IF NOT EXISTS share_accurate_location BOOLEAN;
ALTER TABLE public.privacy_settings ADD COLUMN IF NOT EXISTS blocked_users TEXT[];
ALTER TABLE public.privacy_settings ADD COLUMN IF NOT EXISTS allowed_users TEXT[];
ALTER TABLE public.privacy_settings ADD COLUMN IF NOT EXISTS pause_tracking BOOLEAN;
ALTER TABLE public.privacy_settings ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE;

CREATE INDEX IF NOT EXISTS idx_privacy_settings_user ON public.privacy_settings(user_id);

-- RLS
ALTER TABLE public.privacy_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users manage own privacy settings" ON public.privacy_settings;
CREATE POLICY "Users manage own privacy settings"
  ON public.privacy_settings
  USING (auth.uid() = user_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE: privacy_zones (areas where location is hidden)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.privacy_zones (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  center TEXT NOT NULL, -- "lat,lng"
  radius_meters DOUBLE PRECISION NOT NULL DEFAULT 100,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

ALTER TABLE public.privacy_zones ADD COLUMN IF NOT EXISTS user_id UUID;
ALTER TABLE public.privacy_zones ADD COLUMN IF NOT EXISTS name TEXT;
ALTER TABLE public.privacy_zones ADD COLUMN IF NOT EXISTS center TEXT;
ALTER TABLE public.privacy_zones ADD COLUMN IF NOT EXISTS radius_meters DOUBLE PRECISION;
ALTER TABLE public.privacy_zones ADD COLUMN IF NOT EXISTS is_active BOOLEAN;
ALTER TABLE public.privacy_zones ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE;

CREATE INDEX IF NOT EXISTS idx_privacy_zones_user ON public.privacy_zones(user_id);
CREATE INDEX IF NOT EXISTS idx_privacy_zones_active ON public.privacy_zones(user_id, is_active) WHERE is_active = true;

-- RLS
ALTER TABLE public.privacy_zones ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users manage own privacy zones" ON public.privacy_zones;
CREATE POLICY "Users manage own privacy zones"
  ON public.privacy_zones
  USING (auth.uid() = user_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE: location_share_tokens (temporary location sharing)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.location_share_tokens (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
  allowed_users TEXT[], -- NULL = anyone with link, [] = specific users
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

ALTER TABLE public.location_share_tokens ADD COLUMN IF NOT EXISTS user_id UUID;
ALTER TABLE public.location_share_tokens ADD COLUMN IF NOT EXISTS expires_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE public.location_share_tokens ADD COLUMN IF NOT EXISTS allowed_users TEXT[];
ALTER TABLE public.location_share_tokens ADD COLUMN IF NOT EXISTS is_active BOOLEAN;

CREATE INDEX IF NOT EXISTS idx_share_tokens_user ON public.location_share_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_share_tokens_active ON public.location_share_tokens(is_active, expires_at) WHERE is_active = true;

-- RLS
ALTER TABLE public.location_share_tokens ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users manage own share tokens" ON public.location_share_tokens;
CREATE POLICY "Users manage own share tokens"
  ON public.location_share_tokens
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users with token can view shared location" ON public.location_share_tokens;
CREATE POLICY "Users with token can view shared location"
  ON public.location_share_tokens FOR SELECT
  USING (
    is_active = true 
    AND expires_at > now() 
    AND (
      allowed_users IS NULL 
      OR auth.uid()::text = ANY(allowed_users)
    )
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- FUNCTION: Check if user can see another user's location
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.can_see_user_location(
  target_user_id UUID,
  requester_user_id UUID
)
RETURNS BOOLEAN AS $$
DECLARE
  settings RECORD;
  is_follower BOOLEAN;
  is_friend BOOLEAN;
  is_family BOOLEAN;
BEGIN
  -- Get privacy settings
  SELECT * INTO settings 
  FROM public.privacy_settings 
  WHERE user_id = target_user_id;
  
  -- Default to followers if no settings
  IF settings IS NULL THEN
    settings.visibility := 'followers';
    settings.ghost_mode_enabled := false;
    settings.blocked_users := '{}';
    settings.allowed_users := '{}';
  END IF;
  
  -- Ghost mode = nobody can see
  IF settings.ghost_mode_enabled THEN
    RETURN false;
  END IF;
  
  -- Blocked users
  IF requester_user_id::text = ANY(settings.blocked_users) THEN
    RETURN false;
  END IF;
  
  -- Check visibility level
  CASE settings.visibility
    WHEN 'nobody' THEN
      RETURN false;
      
    WHEN 'public' THEN
      RETURN true;
      
    WHEN 'selected' THEN
      RETURN requester_user_id::text = ANY(settings.allowed_users);
      
    WHEN 'followers' THEN
      SELECT EXISTS(
        SELECT 1 FROM public.follows 
        WHERE follower_id = requester_user_id 
        AND following_id = target_user_id
      ) INTO is_follower;
      RETURN is_follower;
      
    WHEN 'friends' THEN
      -- Mutual follow = friends
      SELECT EXISTS(
        SELECT 1 FROM public.follows f1
        INNER JOIN public.follows f2 
          ON f1.following_id = f2.follower_id 
          AND f1.follower_id = f2.following_id
        WHERE f1.follower_id = requester_user_id 
        AND f1.following_id = target_user_id
      ) INTO is_friend;
      RETURN is_friend;
      
    WHEN 'family' THEN
      -- Check family circle membership
      SELECT EXISTS(
        SELECT 1 FROM public.family_circles fc1
        INNER JOIN public.family_circles fc2 
          ON fc1.circle_id = fc2.circle_id
        WHERE fc1.user_id = requester_user_id 
        AND fc2.user_id = target_user_id
      ) INTO is_family;
      RETURN is_family;
      
    ELSE
      RETURN false;
  END CASE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ─────────────────────────────────────────────────────────────────────────────
-- Triggers for updated_at
-- ─────────────────────────────────────────────────────────────────────────────
DROP TRIGGER IF EXISTS update_privacy_settings_updated_at ON public.privacy_settings;
CREATE TRIGGER update_privacy_settings_updated_at
  BEFORE UPDATE ON public.privacy_settings
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_privacy_zones_updated_at ON public.privacy_zones;
CREATE TRIGGER update_privacy_zones_updated_at
  BEFORE UPDATE ON public.privacy_zones
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

-- ─────────────────────────────────────────────────────────────────────────────
-- Create default privacy settings for existing users
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO public.privacy_settings (user_id, visibility)
SELECT id, 'followers'
FROM auth.users
WHERE id NOT IN (SELECT user_id FROM public.privacy_settings)
ON CONFLICT (user_id) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- Notify PostgREST to reload schema
-- ─────────────────────────────────────────────────────────────────────────────
NOTIFY pgrst, 'reload schema';
