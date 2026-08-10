BEGIN;

ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS metadata jsonb NOT NULL DEFAULT '{}'::jsonb;
CREATE INDEX IF NOT EXISTS idx_messages_metadata_gin ON public.messages USING gin (metadata);

CREATE TABLE IF NOT EXISTS public.message_media_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id uuid NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  album_id text,
  url text NOT NULL,
  thumbnail_url text,
  media_type text NOT NULL,
  file_name text,
  size_bytes bigint,
  width integer,
  height integer,
  duration_ms integer,
  position integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.message_media_items ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_message_media_items_message_pos ON public.message_media_items(message_id, position);
CREATE INDEX IF NOT EXISTS idx_message_media_items_album ON public.message_media_items(album_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_message_media_items_message_url ON public.message_media_items(message_id, url);
DROP POLICY IF EXISTS "Participants view media items" ON public.message_media_items;
CREATE POLICY "Participants view media items" ON public.message_media_items FOR SELECT
USING (EXISTS (
  SELECT 1 FROM public.messages m
  JOIN public.conversation_participants cp ON cp.conversation_id = m.conversation_id
  WHERE m.id = message_media_items.message_id AND cp.user_id = auth.uid()
));
DROP POLICY IF EXISTS "Sender manages media items" ON public.message_media_items;
CREATE POLICY "Sender manages media items" ON public.message_media_items FOR ALL
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

CREATE TABLE IF NOT EXISTS public.user_media_settings (
  user_id uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  image_quality integer NOT NULL DEFAULT 85 CHECK (image_quality BETWEEN 40 AND 100),
  video_quality text NOT NULL DEFAULT 'balanced',
  auto_download_images boolean NOT NULL DEFAULT true,
  auto_download_videos boolean NOT NULL DEFAULT false,
  auto_download_files boolean NOT NULL DEFAULT false,
  auto_download_images_mobile boolean NOT NULL DEFAULT true,
  auto_download_videos_mobile boolean NOT NULL DEFAULT false,
  auto_download_files_mobile boolean NOT NULL DEFAULT false,
  auto_download_roaming boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.user_media_settings ADD COLUMN IF NOT EXISTS auto_download_images_mobile boolean NOT NULL DEFAULT true;
ALTER TABLE public.user_media_settings ADD COLUMN IF NOT EXISTS auto_download_videos_mobile boolean NOT NULL DEFAULT false;
ALTER TABLE public.user_media_settings ADD COLUMN IF NOT EXISTS auto_download_files_mobile boolean NOT NULL DEFAULT false;
ALTER TABLE public.user_media_settings ADD COLUMN IF NOT EXISTS auto_download_roaming boolean NOT NULL DEFAULT false;
ALTER TABLE public.user_media_settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users manage own media settings" ON public.user_media_settings;
CREATE POLICY "Users manage own media settings" ON public.user_media_settings FOR ALL
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

CREATE TABLE IF NOT EXISTS public.media_thumbnail_cache (
  media_url text PRIMARY KEY,
  thumbnail_url text NOT NULL,
  media_type text NOT NULL,
  width integer,
  height integer,
  duration_ms integer,
  generated_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.media_thumbnail_cache ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_media_thumbnail_cache_type ON public.media_thumbnail_cache(media_type, updated_at DESC);
DROP POLICY IF EXISTS "Authenticated users read thumbnail cache" ON public.media_thumbnail_cache;
CREATE POLICY "Authenticated users read thumbnail cache" ON public.media_thumbnail_cache FOR SELECT
USING (auth.uid() IS NOT NULL);
DROP POLICY IF EXISTS "Users write generated thumbnail cache" ON public.media_thumbnail_cache;
CREATE POLICY "Users write generated thumbnail cache" ON public.media_thumbnail_cache FOR INSERT
WITH CHECK (generated_by = auth.uid());
DROP POLICY IF EXISTS "Users update own thumbnail cache" ON public.media_thumbnail_cache;
CREATE POLICY "Users update own thumbnail cache" ON public.media_thumbnail_cache FOR UPDATE
USING (generated_by = auth.uid())
WITH CHECK (generated_by = auth.uid());

CREATE TABLE IF NOT EXISTS public.message_polls (
  message_id uuid PRIMARY KEY REFERENCES public.messages(id) ON DELETE CASCADE,
  question text NOT NULL,
  options jsonb NOT NULL DEFAULT '[]'::jsonb,
  is_anonymous boolean NOT NULL DEFAULT true,
  allows_multiple boolean NOT NULL DEFAULT false,
  closes_at timestamptz,
  created_by uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.message_polls ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Participants view polls" ON public.message_polls;
CREATE POLICY "Participants view polls" ON public.message_polls FOR SELECT
USING (EXISTS (
  SELECT 1 FROM public.messages m
  JOIN public.conversation_participants cp ON cp.conversation_id = m.conversation_id
  WHERE m.id = message_polls.message_id AND cp.user_id = auth.uid()
));
DROP POLICY IF EXISTS "Creators manage polls" ON public.message_polls;
CREATE POLICY "Creators manage polls" ON public.message_polls FOR ALL
USING (created_by = auth.uid())
WITH CHECK (created_by = auth.uid());

CREATE TABLE IF NOT EXISTS public.message_poll_votes (
  message_id uuid NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  option_id text NOT NULL,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (message_id, user_id, option_id)
);
ALTER TABLE public.message_poll_votes ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_message_poll_votes_message ON public.message_poll_votes(message_id);
DROP POLICY IF EXISTS "Participants view poll votes" ON public.message_poll_votes;
CREATE POLICY "Participants view poll votes" ON public.message_poll_votes FOR SELECT
USING (EXISTS (
  SELECT 1 FROM public.messages m
  JOIN public.conversation_participants cp ON cp.conversation_id = m.conversation_id
  WHERE m.id = message_poll_votes.message_id AND cp.user_id = auth.uid()
));
DROP POLICY IF EXISTS "Participants vote polls" ON public.message_poll_votes;
CREATE POLICY "Participants vote polls" ON public.message_poll_votes FOR INSERT
WITH CHECK (
  user_id = auth.uid()
  AND EXISTS (
    SELECT 1 FROM public.messages m
    JOIN public.conversation_participants cp ON cp.conversation_id = m.conversation_id
    WHERE m.id = message_poll_votes.message_id AND cp.user_id = auth.uid()
  )
);
DROP POLICY IF EXISTS "Users update own poll votes" ON public.message_poll_votes;
CREATE POLICY "Users update own poll votes" ON public.message_poll_votes FOR UPDATE
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

CREATE TABLE IF NOT EXISTS public.sticker_packs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  title text NOT NULL,
  slug text UNIQUE NOT NULL,
  cover_url text,
  is_public boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.sticker_packs ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_sticker_packs_public ON public.sticker_packs(is_public, updated_at DESC);
DROP POLICY IF EXISTS "Public or owner sticker packs readable" ON public.sticker_packs;
CREATE POLICY "Public or owner sticker packs readable" ON public.sticker_packs FOR SELECT
USING (is_public OR owner_id = auth.uid());
DROP POLICY IF EXISTS "Owners manage sticker packs" ON public.sticker_packs;
CREATE POLICY "Owners manage sticker packs" ON public.sticker_packs FOR ALL
USING (owner_id = auth.uid())
WITH CHECK (owner_id = auth.uid());

CREATE TABLE IF NOT EXISTS public.stickers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pack_id uuid NOT NULL REFERENCES public.sticker_packs(id) ON DELETE CASCADE,
  emoji text,
  image_url text NOT NULL,
  keywords text[] NOT NULL DEFAULT '{}',
  position integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.stickers ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_stickers_pack_pos ON public.stickers(pack_id, position);
CREATE INDEX IF NOT EXISTS idx_stickers_keywords ON public.stickers USING gin (keywords);
DROP POLICY IF EXISTS "Readable stickers through packs" ON public.stickers;
CREATE POLICY "Readable stickers through packs" ON public.stickers FOR SELECT
USING (EXISTS (
  SELECT 1 FROM public.sticker_packs p
  WHERE p.id = stickers.pack_id AND (p.is_public OR p.owner_id = auth.uid())
));
DROP POLICY IF EXISTS "Pack owners manage stickers" ON public.stickers;
CREATE POLICY "Pack owners manage stickers" ON public.stickers FOR ALL
USING (EXISTS (SELECT 1 FROM public.sticker_packs p WHERE p.id = stickers.pack_id AND p.owner_id = auth.uid()))
WITH CHECK (EXISTS (SELECT 1 FROM public.sticker_packs p WHERE p.id = stickers.pack_id AND p.owner_id = auth.uid()));

CREATE TABLE IF NOT EXISTS public.user_sticker_packs (
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  pack_id uuid NOT NULL REFERENCES public.sticker_packs(id) ON DELETE CASCADE,
  added_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, pack_id)
);
ALTER TABLE public.user_sticker_packs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users manage own sticker packs" ON public.user_sticker_packs;
CREATE POLICY "Users manage own sticker packs" ON public.user_sticker_packs FOR ALL
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

CREATE TABLE IF NOT EXISTS public.message_translations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id uuid NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  user_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  source_text text,
  target_language text NOT NULL,
  translated_text text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(message_id, user_id, target_language)
);
ALTER TABLE public.message_translations ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_message_translations_message ON public.message_translations(message_id);
DROP POLICY IF EXISTS "Participants view translations" ON public.message_translations;
CREATE POLICY "Participants view translations" ON public.message_translations FOR SELECT
USING (EXISTS (
  SELECT 1 FROM public.messages m
  JOIN public.conversation_participants cp ON cp.conversation_id = m.conversation_id
  WHERE m.id = message_translations.message_id AND cp.user_id = auth.uid()
));
DROP POLICY IF EXISTS "Users create own translations" ON public.message_translations;
CREATE POLICY "Users create own translations" ON public.message_translations FOR INSERT
WITH CHECK (user_id = auth.uid());

CREATE TABLE IF NOT EXISTS public.message_transcriptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id uuid NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE UNIQUE,
  user_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  audio_url text,
  text text NOT NULL,
  language text,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.message_transcriptions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Participants view transcriptions" ON public.message_transcriptions;
CREATE POLICY "Participants view transcriptions" ON public.message_transcriptions FOR SELECT
USING (EXISTS (
  SELECT 1 FROM public.messages m
  JOIN public.conversation_participants cp ON cp.conversation_id = m.conversation_id
  WHERE m.id = message_transcriptions.message_id AND cp.user_id = auth.uid()
));
DROP POLICY IF EXISTS "Users create transcriptions for visible messages" ON public.message_transcriptions;
CREATE POLICY "Users create transcriptions for visible messages" ON public.message_transcriptions FOR INSERT
WITH CHECK (
  user_id = auth.uid()
  AND EXISTS (
    SELECT 1 FROM public.messages m
    JOIN public.conversation_participants cp ON cp.conversation_id = m.conversation_id
    WHERE m.id = message_transcriptions.message_id AND cp.user_id = auth.uid()
  )
);

CREATE TABLE IF NOT EXISTS public.saved_message_tags (
  message_id uuid NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  tag text NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (message_id, user_id, tag)
);
ALTER TABLE public.saved_message_tags ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_saved_message_tags_user_tag ON public.saved_message_tags(user_id, tag);
DROP POLICY IF EXISTS "Users manage own saved message tags" ON public.saved_message_tags;
CREATE POLICY "Users manage own saved message tags" ON public.saved_message_tags FOR ALL
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

CREATE OR REPLACE FUNCTION public.search_visible_messages(
  p_user_id uuid,
  p_query text,
  p_media_type text DEFAULT NULL
)
RETURNS SETOF public.messages
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT m.*
  FROM public.messages m
  JOIN public.conversation_participants cp ON cp.conversation_id = m.conversation_id
  WHERE cp.user_id = p_user_id
    AND m.is_deleted = false
    AND (p_media_type IS NULL OR m.media_type = p_media_type)
    AND (
      p_query IS NULL OR p_query = ''
      OR m.content ILIKE '%' || p_query || '%'
      OR m.metadata::text ILIKE '%' || p_query || '%'
    )
  ORDER BY m.created_at DESC
  LIMIT 100;
$$;
GRANT EXECUTE ON FUNCTION public.search_visible_messages(uuid, text, text) TO authenticated;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'message_media_items') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.message_media_items;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'message_poll_votes') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.message_poll_votes;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'message_polls') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.message_polls;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'media_thumbnail_cache') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.media_thumbnail_cache;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'saved_message_tags') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.saved_message_tags;
  END IF;
END $$;

COMMIT;
NOTIFY pgrst, 'reload schema';
