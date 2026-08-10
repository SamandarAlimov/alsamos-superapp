BEGIN;

ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS media_path text;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS thumb_path text;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS duration_ms integer;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS waveform jsonb;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS width integer;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS height integer;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS size_bytes bigint;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS mime_type text;

CREATE INDEX IF NOT EXISTS idx_messages_chat_media_type_created
  ON public.messages(conversation_id, media_type, created_at DESC)
  WHERE media_type IN ('voice', 'audio', 'video', 'video_note');

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES
  ('chat-audio', 'chat-audio', false, 15728640,
   ARRAY['audio/mp4', 'audio/m4a', 'audio/aac', 'audio/mpeg', 'audio/ogg', 'audio/webm']),
  ('chat-video', 'chat-video', false, 157286400,
   ARRAY['video/mp4', 'video/quicktime', 'video/webm']),
  ('chat-thumbs', 'chat-thumbs', false, 5242880,
   ARRAY['image/jpeg', 'image/png', 'image/webp'])
ON CONFLICT (id) DO UPDATE SET
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

DROP POLICY IF EXISTS "Chat media participants read" ON storage.objects;
CREATE POLICY "Chat media participants read"
  ON storage.objects FOR SELECT
  USING (
    bucket_id IN ('chat-audio', 'chat-video', 'chat-thumbs')
    AND EXISTS (
      SELECT 1
      FROM public.conversation_participants cp
      WHERE cp.conversation_id::text = (storage.foldername(name))[1]
        AND cp.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Chat media participants upload" ON storage.objects;
CREATE POLICY "Chat media participants upload"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id IN ('chat-audio', 'chat-video', 'chat-thumbs')
    AND owner = auth.uid()
    AND EXISTS (
      SELECT 1
      FROM public.conversation_participants cp
      WHERE cp.conversation_id::text = (storage.foldername(name))[1]
        AND cp.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Chat media owner update" ON storage.objects;
CREATE POLICY "Chat media owner update"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id IN ('chat-audio', 'chat-video', 'chat-thumbs')
    AND owner = auth.uid()
  )
  WITH CHECK (
    bucket_id IN ('chat-audio', 'chat-video', 'chat-thumbs')
    AND owner = auth.uid()
  );

DROP POLICY IF EXISTS "Chat media owner delete" ON storage.objects;
CREATE POLICY "Chat media owner delete"
  ON storage.objects FOR DELETE
  USING (
    bucket_id IN ('chat-audio', 'chat-video', 'chat-thumbs')
    AND owner = auth.uid()
  );

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'messages'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
  END IF;
END $$;

COMMIT;
NOTIFY pgrst, 'reload schema';

