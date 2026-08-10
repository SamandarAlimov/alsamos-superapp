BEGIN;

CREATE INDEX IF NOT EXISTS idx_profiles_username_lower
  ON public.profiles (lower(username))
  WHERE username IS NOT NULL;

CREATE OR REPLACE FUNCTION public.notify_on_message_mention()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  mentioned_username text;
  mentioned_user_id uuid;
  author_name text;
  content_preview text;
BEGIN
  IF COALESCE(NEW.content, '') = '' THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(display_name, username)
    INTO author_name
    FROM public.profiles
    WHERE id = NEW.sender_id;

  content_preview := LEFT(NEW.content, 160);

  FOR mentioned_username IN
    SELECT DISTINCT lower((regexp_matches(NEW.content, '@([a-zA-Z0-9_]{3,32})', 'g'))[1])
  LOOP
    SELECT id
      INTO mentioned_user_id
      FROM public.profiles
      WHERE lower(username) = mentioned_username
      LIMIT 1;

    IF mentioned_user_id IS NOT NULL
       AND mentioned_user_id <> NEW.sender_id
       AND EXISTS (
         SELECT 1
         FROM public.conversation_participants cp
         WHERE cp.conversation_id = NEW.conversation_id
           AND cp.user_id = mentioned_user_id
       )
       AND NOT EXISTS (
         SELECT 1
         FROM public.notifications n
         WHERE n.user_id = mentioned_user_id
           AND n.type = 'mention'
           AND n.data->>'message_id' = NEW.id::text
       ) THEN
      INSERT INTO public.notifications (user_id, type, title, body, data)
      VALUES (
        mentioned_user_id,
        'mention',
        'Yangi eslatish',
        COALESCE(author_name, 'Kimdir') || ' sizni xabarda eslatdi',
        jsonb_build_object(
          'message_id', NEW.id,
          'conversation_id', NEW.conversation_id,
          'mentioner_id', NEW.sender_id,
          'content_preview', content_preview
        )
      );
    END IF;
  END LOOP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_message_mention ON public.messages;
CREATE TRIGGER on_message_mention
AFTER INSERT OR UPDATE OF content ON public.messages
FOR EACH ROW
WHEN (NEW.is_deleted = false)
EXECUTE FUNCTION public.notify_on_message_mention();

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'notifications'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
  END IF;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- RLS audit: mention notifications are inserted by a SECURITY DEFINER trigger only for users who are participants in the message conversation; notifications SELECT remains owner-only.
