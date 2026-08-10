-- Telegram-style animated stickers system
BEGIN;

CREATE TABLE IF NOT EXISTS public.sticker_packs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL,
  cover_url text,
  cover_lottie_url text,
  created_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  is_animated boolean DEFAULT false,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.stickers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pack_id uuid NOT NULL REFERENCES public.sticker_packs(id) ON DELETE CASCADE,
  emoji text NOT NULL DEFAULT ':)',
  image_url text,
  lottie_url text,
  video_url text,
  thumbnail_url text,
  type text NOT NULL CHECK (type IN ('static', 'animated', 'video')),
  position integer DEFAULT 0,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.user_sticker_packs (
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  pack_id uuid NOT NULL REFERENCES public.sticker_packs(id) ON DELETE CASCADE,
  updated_at timestamptz DEFAULT now(),
  PRIMARY KEY (user_id, pack_id)
);

CREATE TABLE IF NOT EXISTS public.recent_stickers (
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  sticker_id uuid NOT NULL REFERENCES public.stickers(id) ON DELETE CASCADE,
  use_count integer DEFAULT 1,
  last_used timestamptz DEFAULT now(),
  PRIMARY KEY (user_id, sticker_id)
);

CREATE INDEX IF NOT EXISTS idx_stickers_pack_id ON public.stickers(pack_id);
CREATE INDEX IF NOT EXISTS idx_stickers_position ON public.stickers(pack_id, position);
CREATE INDEX IF NOT EXISTS idx_user_sticker_packs_user ON public.user_sticker_packs(user_id);
CREATE INDEX IF NOT EXISTS idx_user_sticker_packs_updated ON public.user_sticker_packs(user_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_recent_stickers_user ON public.recent_stickers(user_id);
CREATE INDEX IF NOT EXISTS idx_recent_stickers_last_used ON public.recent_stickers(user_id, last_used DESC);

ALTER TABLE public.sticker_packs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stickers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_sticker_packs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.recent_stickers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Sticker packs are viewable by everyone" ON public.sticker_packs;
CREATE POLICY "Sticker packs are viewable by everyone"
ON public.sticker_packs
FOR SELECT
USING (true);

DROP POLICY IF EXISTS "Sticker packs insertable by authenticated users" ON public.sticker_packs;
CREATE POLICY "Sticker packs insertable by authenticated users"
ON public.sticker_packs
FOR INSERT
TO authenticated
WITH CHECK (created_by = auth.uid());

DROP POLICY IF EXISTS "Sticker packs updatable by creator" ON public.sticker_packs;
CREATE POLICY "Sticker packs updatable by creator"
ON public.sticker_packs
FOR UPDATE
TO authenticated
USING (created_by = auth.uid())
WITH CHECK (created_by = auth.uid());

DROP POLICY IF EXISTS "Stickers are viewable by everyone" ON public.stickers;
CREATE POLICY "Stickers are viewable by everyone"
ON public.stickers
FOR SELECT
USING (true);

DROP POLICY IF EXISTS "Stickers insertable by pack creator" ON public.stickers;
CREATE POLICY "Stickers insertable by pack creator"
ON public.stickers
FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.sticker_packs
    WHERE id = pack_id AND created_by = auth.uid()
  )
);

DROP POLICY IF EXISTS "User sticker packs viewable by owner" ON public.user_sticker_packs;
CREATE POLICY "User sticker packs viewable by owner"
ON public.user_sticker_packs
FOR SELECT
TO authenticated
USING (user_id = auth.uid());

DROP POLICY IF EXISTS "User sticker packs insertable by owner" ON public.user_sticker_packs;
CREATE POLICY "User sticker packs insertable by owner"
ON public.user_sticker_packs
FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "User sticker packs deletable by owner" ON public.user_sticker_packs;
CREATE POLICY "User sticker packs deletable by owner"
ON public.user_sticker_packs
FOR DELETE
TO authenticated
USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Recent stickers viewable by owner" ON public.recent_stickers;
CREATE POLICY "Recent stickers viewable by owner"
ON public.recent_stickers
FOR SELECT
TO authenticated
USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Recent stickers insertable by owner" ON public.recent_stickers;
CREATE POLICY "Recent stickers insertable by owner"
ON public.recent_stickers
FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Recent stickers updatable by owner" ON public.recent_stickers;
CREATE POLICY "Recent stickers updatable by owner"
ON public.recent_stickers
FOR UPDATE
TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Recent stickers deletable by owner" ON public.recent_stickers;
CREATE POLICY "Recent stickers deletable by owner"
ON public.recent_stickers
FOR DELETE
TO authenticated
USING (user_id = auth.uid());

CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_sticker_packs_updated_at ON public.sticker_packs;
CREATE TRIGGER update_sticker_packs_updated_at
BEFORE UPDATE ON public.sticker_packs
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_user_sticker_packs_updated_at ON public.user_sticker_packs;
CREATE TRIGGER update_user_sticker_packs_updated_at
BEFORE UPDATE ON public.user_sticker_packs
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();

COMMIT;
NOTIFY pgrst, 'reload schema';
