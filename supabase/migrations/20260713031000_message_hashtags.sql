BEGIN;

CREATE TABLE IF NOT EXISTS public.message_hashtags (
  message_id uuid NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  tag text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (message_id, tag)
);

ALTER TABLE public.message_hashtags ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_message_hashtags_conversation_tag
  ON public.message_hashtags(conversation_id, tag, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_message_hashtags_tag_created
  ON public.message_hashtags(tag, created_at DESC);

DROP POLICY IF EXISTS "Participants view message hashtags" ON public.message_hashtags;
CREATE POLICY "Participants view message hashtags"
  ON public.message_hashtags FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.conversation_participants cp
      WHERE cp.conversation_id = message_hashtags.conversation_id
        AND cp.user_id = auth.uid()
    )
  );

CREATE OR REPLACE FUNCTION public.sync_message_hashtags()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  tag_value text;
BEGIN
  DELETE FROM public.message_hashtags WHERE message_id = NEW.id;

  IF COALESCE(NEW.is_deleted, false) OR COALESCE(NEW.content, '') = '' THEN
    RETURN NEW;
  END IF;

  FOR tag_value IN
    SELECT DISTINCT lower((regexp_matches(NEW.content, '#([a-zA-Z0-9_]{1,64})', 'g'))[1])
  LOOP
    INSERT INTO public.message_hashtags(message_id, conversation_id, tag, created_at)
    VALUES (NEW.id, NEW.conversation_id, tag_value, COALESCE(NEW.created_at, now()))
    ON CONFLICT (message_id, tag) DO NOTHING;
  END LOOP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_message_hashtags_sync ON public.messages;
CREATE TRIGGER on_message_hashtags_sync
AFTER INSERT OR UPDATE OF content, is_deleted ON public.messages
FOR EACH ROW
EXECUTE FUNCTION public.sync_message_hashtags();

CREATE OR REPLACE FUNCTION public.search_conversation_hashtag(
  p_conversation_id uuid,
  p_tag text
)
RETURNS TABLE(message_id uuid, created_at timestamptz)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT mh.message_id, mh.created_at
  FROM public.message_hashtags mh
  WHERE mh.conversation_id = p_conversation_id
    AND mh.tag = lower(trim(leading '#' from p_tag))
    AND EXISTS (
      SELECT 1
      FROM public.conversation_participants cp
      WHERE cp.conversation_id = p_conversation_id
        AND cp.user_id = auth.uid()
    )
  ORDER BY mh.created_at DESC;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'message_hashtags'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.message_hashtags;
  END IF;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- RLS audit: message_hashtags is trigger-maintained and readable only by participants of the owning conversation.
