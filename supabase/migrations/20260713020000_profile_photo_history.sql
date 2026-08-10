-- Migration: Profile photo history table
BEGIN;

CREATE TABLE IF NOT EXISTS public.profile_photo_history (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  photo_url     TEXT        NOT NULL,
  is_current    BOOLEAN     NOT NULL DEFAULT FALSE,
  uploaded_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_profile_photo_history_user
  ON public.profile_photo_history (user_id, uploaded_at DESC);

CREATE UNIQUE INDEX IF NOT EXISTS idx_profile_photo_history_user_photo
  ON public.profile_photo_history (user_id, photo_url);

-- RLS
ALTER TABLE public.profile_photo_history ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can see their own photo history" ON public.profile_photo_history;
CREATE POLICY "Users can see their own photo history"
  ON public.profile_photo_history FOR SELECT
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can insert their own photo history" ON public.profile_photo_history;
CREATE POLICY "Users can insert their own photo history"
  ON public.profile_photo_history FOR INSERT
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can update their own photo history" ON public.profile_photo_history;
CREATE POLICY "Users can update their own photo history"
  ON public.profile_photo_history FOR UPDATE
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can delete their own photo history" ON public.profile_photo_history;
CREATE POLICY "Users can delete their own photo history"
  ON public.profile_photo_history FOR DELETE
  USING (user_id = auth.uid());

-- Backfill current avatar into history for existing profiles
INSERT INTO public.profile_photo_history (user_id, photo_url, is_current, uploaded_at)
SELECT id, avatar_url, TRUE, NOW()
FROM public.profiles
WHERE avatar_url IS NOT NULL AND avatar_url != ''
ON CONFLICT (user_id, photo_url) DO UPDATE
SET is_current = TRUE;

-- RPC to atomically change current photo and update profile
CREATE OR REPLACE FUNCTION public.set_current_profile_photo(p_user_id UUID, p_photo_id UUID, p_photo_url TEXT)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Verify ownership
  IF auth.uid() != p_user_id THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  -- Reset all to false
  IF NOT EXISTS (
    SELECT 1
    FROM public.profile_photo_history
    WHERE id = p_photo_id
      AND user_id = p_user_id
      AND photo_url = p_photo_url
  ) THEN
    RAISE EXCEPTION 'Photo not found';
  END IF;

  UPDATE public.profile_photo_history
  SET is_current = FALSE
  WHERE user_id = p_user_id;

  -- Set target to true
  UPDATE public.profile_photo_history
  SET is_current = TRUE
  WHERE id = p_photo_id AND user_id = p_user_id;

  -- Update profiles table
  UPDATE public.profiles
  SET avatar_url = p_photo_url
  WHERE id = p_user_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_current_profile_photo(UUID, UUID, TEXT) TO authenticated;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'profile_photo_history'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.profile_photo_history;
  END IF;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- RLS audit: users can only read/write their own photo history; current-photo RPC verifies ownership before updating profiles.avatar_url.
