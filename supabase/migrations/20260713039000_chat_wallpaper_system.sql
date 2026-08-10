BEGIN;

ALTER TABLE public.user_settings
  ADD COLUMN IF NOT EXISTS chat_wallpaper_type text,
  ADD COLUMN IF NOT EXISTS chat_wallpaper_value text,
  ADD COLUMN IF NOT EXISTS chat_wallpaper_dim double precision NOT NULL DEFAULT 0.16,
  ADD COLUMN IF NOT EXISTS chat_wallpaper_blur double precision NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS chat_wallpaper_updated_at timestamptz;

ALTER TABLE public.conversation_participants
  ADD COLUMN IF NOT EXISTS wallpaper_type text,
  ADD COLUMN IF NOT EXISTS wallpaper_value text,
  ADD COLUMN IF NOT EXISTS wallpaper_dim double precision,
  ADD COLUMN IF NOT EXISTS wallpaper_blur double precision,
  ADD COLUMN IF NOT EXISTS wallpaper_updated_at timestamptz;

CREATE INDEX IF NOT EXISTS idx_conversation_participants_wallpaper_user
  ON public.conversation_participants(user_id, wallpaper_updated_at DESC);

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'chat-wallpapers',
  'chat-wallpapers',
  false,
  8388608,
  ARRAY['image/jpeg', 'image/png', 'image/webp']::text[]
)
ON CONFLICT (id) DO UPDATE
SET public = false,
    file_size_limit = 8388608,
    allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp']::text[];

DROP POLICY IF EXISTS "Users read own chat wallpapers" ON storage.objects;
CREATE POLICY "Users read own chat wallpapers"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'chat-wallpapers'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

DROP POLICY IF EXISTS "Users upload own chat wallpapers" ON storage.objects;
CREATE POLICY "Users upload own chat wallpapers"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'chat-wallpapers'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

DROP POLICY IF EXISTS "Users update own chat wallpapers" ON storage.objects;
CREATE POLICY "Users update own chat wallpapers"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'chat-wallpapers'
    AND (storage.foldername(name))[1] = auth.uid()::text
  )
  WITH CHECK (
    bucket_id = 'chat-wallpapers'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

DROP POLICY IF EXISTS "Users delete own chat wallpapers" ON storage.objects;
CREATE POLICY "Users delete own chat wallpapers"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'chat-wallpapers'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

COMMENT ON COLUMN public.user_settings.chat_wallpaper_type IS
  'Global chat wallpaper kind: preset, color, gradient, or image.';
COMMENT ON COLUMN public.conversation_participants.wallpaper_type IS
  'Nullable per-user per-chat wallpaper override; null inherits global wallpaper.';

-- RLS audit: global wallpaper remains protected by existing user_settings owner policies; per-chat wallpaper is stored on the authenticated user participant row; storage policies restrict custom images to auth.uid() folder owners.

COMMIT;
NOTIFY pgrst, 'reload schema';
