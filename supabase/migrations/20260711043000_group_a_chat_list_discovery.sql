BEGIN;

ALTER TABLE public.conversation_participants
  ADD COLUMN IF NOT EXISTS mute_until timestamptz,
  ADD COLUMN IF NOT EXISTS pinned_order integer,
  ADD COLUMN IF NOT EXISTS manually_unread boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS archived_at timestamptz,
  ADD COLUMN IF NOT EXISTS archive_on_new_message boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS folder_ids uuid[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

CREATE INDEX IF NOT EXISTS idx_conversation_participants_user_archived
  ON public.conversation_participants(user_id, is_archived, archived_at DESC);
CREATE INDEX IF NOT EXISTS idx_conversation_participants_user_pinned
  ON public.conversation_participants(user_id, is_pinned, pinned_order);
CREATE INDEX IF NOT EXISTS idx_conversation_participants_user_muted
  ON public.conversation_participants(user_id, is_muted, mute_until);

CREATE TABLE IF NOT EXISTS public.chat_folders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title text NOT NULL,
  position integer NOT NULL DEFAULT 0,
  include_types text[] NOT NULL DEFAULT '{}',
  include_conversation_ids uuid[] NOT NULL DEFAULT '{}',
  exclude_conversation_ids uuid[] NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.chat_folders ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_chat_folders_user_position
  ON public.chat_folders(user_id, position, updated_at DESC);

DROP POLICY IF EXISTS "Users manage own chat folders" ON public.chat_folders;
CREATE POLICY "Users manage own chat folders"
  ON public.chat_folders
  FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

ALTER TABLE public.posts
  ADD COLUMN IF NOT EXISTS source_type text,
  ADD COLUMN IF NOT EXISTS source_id uuid,
  ADD COLUMN IF NOT EXISTS source_title text,
  ADD COLUMN IF NOT EXISTS source_avatar_url text,
  ADD COLUMN IF NOT EXISTS source_message_id uuid;

CREATE UNIQUE INDEX IF NOT EXISTS idx_posts_source_message_id
  ON public.posts(source_message_id)
  WHERE source_message_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_posts_public_source
  ON public.posts(visibility, source_type, created_at DESC)
  WHERE visibility = 'public';

CREATE TABLE IF NOT EXISTS public.discovery_hidden_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  item_type text NOT NULL CHECK (item_type IN ('post', 'profile', 'channel', 'group')),
  item_id uuid NOT NULL,
  reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, item_type, item_id)
);

ALTER TABLE public.discovery_hidden_items ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_discovery_hidden_items_user
  ON public.discovery_hidden_items(user_id, item_type, created_at DESC);

DROP POLICY IF EXISTS "Users manage own hidden discovery items" ON public.discovery_hidden_items;
CREATE POLICY "Users manage own hidden discovery items"
  ON public.discovery_hidden_items
  FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE OR REPLACE FUNCTION public.touch_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_conversation_participants_updated_at ON public.conversation_participants;
CREATE TRIGGER trg_conversation_participants_updated_at
  BEFORE UPDATE ON public.conversation_participants
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

DROP TRIGGER IF EXISTS trg_chat_folders_updated_at ON public.chat_folders;
CREATE TRIGGER trg_chat_folders_updated_at
  BEFORE UPDATE ON public.chat_folders
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'chat_folders'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_folders;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'discovery_hidden_items'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.discovery_hidden_items;
  END IF;
END $$;

COMMENT ON TABLE public.chat_folders IS
  'RLS audit: users can only read and mutate their own chat folder definitions.';
COMMENT ON TABLE public.discovery_hidden_items IS
  'RLS audit: users can only hide/unhide discovery items for themselves.';

COMMIT;

NOTIFY pgrst, 'reload schema';
