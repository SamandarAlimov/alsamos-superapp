-- Phase 4 chat list: per-user folders, mute durations, pin ordering, archive metadata, manual unread.

BEGIN;

ALTER TABLE public.conversation_participants
  ADD COLUMN IF NOT EXISTS mute_until timestamptz,
  ADD COLUMN IF NOT EXISTS pinned_order integer,
  ADD COLUMN IF NOT EXISTS manually_unread boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS archived_at timestamptz,
  ADD COLUMN IF NOT EXISTS archive_on_new_message boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS folder_ids uuid[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

CREATE INDEX IF NOT EXISTS idx_conversation_participants_user_archived_pinned
  ON public.conversation_participants(user_id, is_archived, is_pinned, pinned_order);
CREATE INDEX IF NOT EXISTS idx_conversation_participants_user_mute_until
  ON public.conversation_participants(user_id, mute_until);
CREATE INDEX IF NOT EXISTS idx_conversation_participants_user_updated
  ON public.conversation_participants(user_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_conversation_participants_folder_ids
  ON public.conversation_participants USING gin(folder_ids);

CREATE TABLE IF NOT EXISTS public.chat_folders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  title text NOT NULL,
  position integer NOT NULL DEFAULT 0,
  include_types text[] NOT NULL DEFAULT '{}',
  include_conversation_ids uuid[] NOT NULL DEFAULT '{}',
  exclude_conversation_ids uuid[] NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_chat_folders_user_position
  ON public.chat_folders(user_id, position);
CREATE INDEX IF NOT EXISTS idx_chat_folders_user_updated
  ON public.chat_folders(user_id, updated_at DESC);

ALTER TABLE public.chat_folders ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users manage own chat folders" ON public.chat_folders;
CREATE POLICY "Users manage own chat folders"
  ON public.chat_folders
  FOR ALL
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE OR REPLACE FUNCTION public.touch_conversation_participants_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_conversation_participants_updated_at ON public.conversation_participants;
CREATE TRIGGER trg_conversation_participants_updated_at
  BEFORE UPDATE ON public.conversation_participants
  FOR EACH ROW
  EXECUTE FUNCTION public.touch_conversation_participants_updated_at();

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime')
     AND NOT EXISTS (
       SELECT 1 FROM pg_publication_tables
       WHERE pubname = 'supabase_realtime'
         AND schemaname = 'public'
         AND tablename = 'chat_folders'
     ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_folders;
  END IF;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- RLS audit: chat_folders rows are visible/mutable only to owner via auth.uid(); participant metadata remains protected by existing conversation_participants owner policies.
