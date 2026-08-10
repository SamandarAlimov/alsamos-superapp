BEGIN;

ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS linked_group_id uuid REFERENCES public.conversations(id) ON DELETE SET NULL;

ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS comment_count integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS original_post_id uuid REFERENCES public.messages(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_conversations_linked_group_id
  ON public.conversations(linked_group_id)
  WHERE linked_group_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_messages_original_post_id
  ON public.messages(original_post_id)
  WHERE original_post_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.update_message_comment_count()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  target_message_id uuid;
BEGIN
  IF TG_OP = 'INSERT' AND NEW.reply_to_id IS NOT NULL THEN
    SELECT COALESCE(original_post_id, id)
      INTO target_message_id
      FROM public.messages
      WHERE id = NEW.reply_to_id;

    IF target_message_id IS NOT NULL THEN
      UPDATE public.messages
      SET comment_count = COALESCE(comment_count, 0) + 1
      WHERE id = target_message_id;
    END IF;
  ELSIF TG_OP = 'DELETE' AND OLD.reply_to_id IS NOT NULL THEN
    SELECT COALESCE(original_post_id, id)
      INTO target_message_id
      FROM public.messages
      WHERE id = OLD.reply_to_id;

    IF target_message_id IS NOT NULL THEN
      UPDATE public.messages
      SET comment_count = GREATEST(COALESCE(comment_count, 0) - 1, 0)
      WHERE id = target_message_id;
    END IF;
  END IF;

  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS update_message_comment_count_trigger ON public.messages;
CREATE TRIGGER update_message_comment_count_trigger
AFTER INSERT OR DELETE ON public.messages
FOR EACH ROW
EXECUTE FUNCTION public.update_message_comment_count();

CREATE OR REPLACE FUNCTION public.forward_channel_message_to_group()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  linked_group uuid;
BEGIN
  SELECT linked_group_id
    INTO linked_group
    FROM public.conversations
    WHERE id = NEW.conversation_id
      AND type = 'channel'
      AND linked_group_id IS NOT NULL;

  IF linked_group IS NOT NULL
      AND COALESCE(NEW.is_deleted, false) = false
      AND NEW.reply_to_id IS NULL
      AND NEW.original_post_id IS NULL
      AND NOT EXISTS (
        SELECT 1
        FROM public.messages
        WHERE conversation_id = linked_group
          AND original_post_id = NEW.id
      ) THEN
    INSERT INTO public.messages (
      conversation_id,
      sender_id,
      content,
      media_url,
      media_type,
      metadata,
      original_post_id
    ) VALUES (
      linked_group,
      NEW.sender_id,
      NEW.content,
      NEW.media_url,
      NEW.media_type,
      COALESCE(NEW.metadata, '{}'::jsonb) || jsonb_build_object(
        'discussion_anchor', true,
        'channel_message_id', NEW.id,
        'channel_conversation_id', NEW.conversation_id
      ),
      NEW.id
    );
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS forward_channel_message_trigger ON public.messages;
CREATE TRIGGER forward_channel_message_trigger
AFTER INSERT ON public.messages
FOR EACH ROW
WHEN (NEW.reply_to_id IS NULL)
EXECUTE FUNCTION public.forward_channel_message_to_group();

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

-- RLS audit: linked discussions reuse existing conversation/message policies; trigger runs as definer and only mirrors channel posts into their configured linked group.
