BEGIN;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES
  (
    'chat-media',
    'chat-media',
    true,
    52428800,
    ARRAY[
      'image/jpeg','image/png','image/gif','image/webp',
      'video/mp4','video/quicktime',
      'audio/mp4','audio/mpeg','audio/wav',
      'application/pdf','text/plain','application/octet-stream'
    ]
  ),
  (
    'message-attachments',
    'message-attachments',
    true,
    52428800,
    ARRAY[
      'image/jpeg','image/png','image/gif','image/webp',
      'video/mp4','video/quicktime',
      'audio/mp4','audio/mpeg','audio/wav',
      'application/pdf','text/plain','application/octet-stream'
    ]
  )
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS "Public can read chat media" ON storage.objects;
CREATE POLICY "Public can read chat media"
  ON storage.objects
  FOR SELECT
  USING (bucket_id IN ('chat-media', 'message-attachments'));

DROP POLICY IF EXISTS "Users upload own chat media" ON storage.objects;
CREATE POLICY "Users upload own chat media"
  ON storage.objects
  FOR INSERT
  WITH CHECK (
    bucket_id IN ('chat-media', 'message-attachments')
    AND auth.role() = 'authenticated'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

DROP POLICY IF EXISTS "Users update own chat media" ON storage.objects;
CREATE POLICY "Users update own chat media"
  ON storage.objects
  FOR UPDATE
  USING (
    bucket_id IN ('chat-media', 'message-attachments')
    AND (storage.foldername(name))[1] = auth.uid()::text
  )
  WITH CHECK (
    bucket_id IN ('chat-media', 'message-attachments')
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

DROP POLICY IF EXISTS "Users delete own chat media" ON storage.objects;
CREATE POLICY "Users delete own chat media"
  ON storage.objects
  FOR DELETE
  USING (
    bucket_id IN ('chat-media', 'message-attachments')
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS media_file_name text,
  ADD COLUMN IF NOT EXISTS media_size_bytes bigint,
  ADD COLUMN IF NOT EXISTS location_payload jsonb;

CREATE INDEX IF NOT EXISTS idx_messages_media_type
  ON public.messages(conversation_id, media_type, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_messages_location_payload
  ON public.messages USING gin(location_payload)
  WHERE location_payload IS NOT NULL;

COMMENT ON COLUMN public.messages.location_payload IS
  'RLS audit: location_payload is protected by existing messages participant RLS; storage objects are write-scoped to auth.uid folder.';

COMMIT;

NOTIFY pgrst, 'reload schema';
