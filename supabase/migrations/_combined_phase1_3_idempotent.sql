BEGIN;

-- Phase 1: read receipt upsert policies.
CREATE TABLE IF NOT EXISTS public.message_reads (
  message_id uuid NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  read_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (message_id, user_id)
);

ALTER TABLE public.message_reads ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can mark as read" ON public.message_reads;
DROP POLICY IF EXISTS "Users can update own read receipts" ON public.message_reads;

CREATE POLICY "Users can mark as read" ON public.message_reads
  FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = user_id
    AND EXISTS (
      SELECT 1
      FROM public.messages m
      JOIN public.conversation_participants cp
        ON cp.conversation_id = m.conversation_id
      WHERE m.id = message_reads.message_id
        AND cp.user_id = auth.uid()
    )
  );

CREATE POLICY "Users can update own read receipts" ON public.message_reads
  FOR UPDATE TO authenticated
  USING (
    auth.uid() = user_id
    AND EXISTS (
      SELECT 1
      FROM public.messages m
      JOIN public.conversation_participants cp
        ON cp.conversation_id = m.conversation_id
      WHERE m.id = message_reads.message_id
        AND cp.user_id = auth.uid()
    )
  )
  WITH CHECK (
    auth.uid() = user_id
    AND EXISTS (
      SELECT 1
      FROM public.messages m
      JOIN public.conversation_participants cp
        ON cp.conversation_id = m.conversation_id
      WHERE m.id = message_reads.message_id
        AND cp.user_id = auth.uid()
    )
  );

-- Phase 1: client-side message id dedup.
ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS client_message_id text;

CREATE UNIQUE INDEX IF NOT EXISTS messages_sender_client_message_id_idx
  ON public.messages(sender_id, client_message_id)
  WHERE client_message_id IS NOT NULL;

-- Phase 2: message interactions.
ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS forwarded_from_message_id uuid REFERENCES public.messages(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS forwarded_from_name text,
  ADD COLUMN IF NOT EXISTS is_silent boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS deleted_at timestamptz,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

CREATE INDEX IF NOT EXISTS idx_messages_forwarded_from_message_id
  ON public.messages(forwarded_from_message_id);
CREATE INDEX IF NOT EXISTS idx_messages_deleted_at
  ON public.messages(conversation_id, deleted_at);
CREATE INDEX IF NOT EXISTS idx_messages_updated_at
  ON public.messages(conversation_id, updated_at DESC);

CREATE TABLE IF NOT EXISTS public.message_reactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id uuid NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  emoji text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (message_id, user_id, emoji)
);

ALTER TABLE public.message_reactions
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

CREATE INDEX IF NOT EXISTS idx_message_reactions_message_id
  ON public.message_reactions(message_id);
CREATE INDEX IF NOT EXISTS idx_message_reactions_user_id
  ON public.message_reactions(user_id);
CREATE INDEX IF NOT EXISTS idx_message_reactions_updated_at
  ON public.message_reactions(updated_at DESC);

CREATE TABLE IF NOT EXISTS public.message_edit_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id uuid NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  editor_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  previous_content text,
  new_content text,
  edited_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_message_edit_history_message_id
  ON public.message_edit_history(message_id, edited_at DESC);
CREATE INDEX IF NOT EXISTS idx_message_edit_history_conversation_id
  ON public.message_edit_history(conversation_id, edited_at DESC);

ALTER TABLE public.message_edit_history ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Participants can view edit history" ON public.message_edit_history;
CREATE POLICY "Participants can view edit history"
  ON public.message_edit_history FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.conversation_participants cp
      WHERE cp.conversation_id = message_edit_history.conversation_id
        AND cp.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Message sender can write edit history" ON public.message_edit_history;
CREATE POLICY "Message sender can write edit history"
  ON public.message_edit_history FOR INSERT
  WITH CHECK (
    editor_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.messages m
      WHERE m.id = message_edit_history.message_id
        AND m.sender_id = auth.uid()
        AND m.conversation_id = message_edit_history.conversation_id
    )
  );

CREATE TABLE IF NOT EXISTS public.message_drafts (
  conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  content text NOT NULL DEFAULT '',
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (conversation_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_message_drafts_user_updated
  ON public.message_drafts(user_id, updated_at DESC);

ALTER TABLE public.message_drafts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can read own drafts" ON public.message_drafts;
CREATE POLICY "Users can read own drafts"
  ON public.message_drafts FOR SELECT
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can upsert own drafts in joined conversations" ON public.message_drafts;
CREATE POLICY "Users can upsert own drafts in joined conversations"
  ON public.message_drafts FOR INSERT
  WITH CHECK (
    user_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.conversation_participants cp
      WHERE cp.conversation_id = message_drafts.conversation_id
        AND cp.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Users can update own drafts" ON public.message_drafts;
CREATE POLICY "Users can update own drafts"
  ON public.message_drafts FOR UPDATE
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE TABLE IF NOT EXISTS public.link_previews (
  url text PRIMARY KEY,
  title text,
  description text,
  image_url text,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_link_previews_updated_at
  ON public.link_previews(updated_at DESC);

ALTER TABLE public.link_previews ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated users can read link previews" ON public.link_previews;
CREATE POLICY "Authenticated users can read link previews"
  ON public.link_previews FOR SELECT
  USING (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "Authenticated users can cache link previews" ON public.link_previews;
CREATE POLICY "Authenticated users can cache link previews"
  ON public.link_previews FOR INSERT
  WITH CHECK (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "Authenticated users can refresh link previews" ON public.link_previews;
CREATE POLICY "Authenticated users can refresh link previews"
  ON public.link_previews FOR UPDATE
  USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');

CREATE TABLE IF NOT EXISTS public.scheduled_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  sender_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  content text NOT NULL DEFAULT '',
  scheduled_for timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.scheduled_messages
  ADD COLUMN IF NOT EXISTS reply_to_id uuid REFERENCES public.messages(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS is_silent boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'scheduled',
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

CREATE INDEX IF NOT EXISTS idx_scheduled_messages_status_time
  ON public.scheduled_messages(status, scheduled_for);
CREATE INDEX IF NOT EXISTS idx_scheduled_messages_sender_time
  ON public.scheduled_messages(sender_id, scheduled_for);

DROP POLICY IF EXISTS "Participants can update message tombstones" ON public.messages;
CREATE POLICY "Participants can update message tombstones"
  ON public.messages FOR UPDATE
  USING (
    sender_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.conversation_participants cp
      WHERE cp.conversation_id = messages.conversation_id
        AND cp.user_id = auth.uid()
    )
  )
  WITH CHECK (
    sender_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.conversation_participants cp
      WHERE cp.conversation_id = messages.conversation_id
        AND cp.user_id = auth.uid()
    )
  );

-- Phase 3: realtime presence and read-state.
CREATE TABLE IF NOT EXISTS public.user_privacy_exceptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  target_user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  rule text NOT NULL CHECK (rule IN ('allow', 'deny')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, target_user_id)
);

CREATE INDEX IF NOT EXISTS idx_user_privacy_exceptions_user_target
  ON public.user_privacy_exceptions(user_id, target_user_id);
CREATE INDEX IF NOT EXISTS idx_user_privacy_exceptions_target
  ON public.user_privacy_exceptions(target_user_id);

ALTER TABLE public.user_privacy_exceptions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users manage own privacy exceptions" ON public.user_privacy_exceptions;
CREATE POLICY "Users manage own privacy exceptions"
  ON public.user_privacy_exceptions
  FOR ALL
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE INDEX IF NOT EXISTS idx_message_reads_message_read_at
  ON public.message_reads(message_id, read_at DESC);
CREATE INDEX IF NOT EXISTS idx_message_reads_user_read_at
  ON public.message_reads(user_id, read_at DESC);

DROP POLICY IF EXISTS "Users can mark as read" ON public.message_reads;
CREATE POLICY "Users can mark as read"
  ON public.message_reads FOR INSERT
  WITH CHECK (
    user_id = auth.uid()
    AND coalesce((
      SELECT us.read_receipts_enabled
      FROM public.user_settings us
      WHERE us.user_id = auth.uid()
    ), true)
    AND EXISTS (
      SELECT 1
      FROM public.messages m
      JOIN public.conversation_participants cp
        ON cp.conversation_id = m.conversation_id
      WHERE m.id = message_reads.message_id
        AND cp.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Users can update own read receipts" ON public.message_reads;
CREATE POLICY "Users can update own read receipts"
  ON public.message_reads FOR UPDATE
  USING (user_id = auth.uid())
  WITH CHECK (
    user_id = auth.uid()
    AND coalesce((
      SELECT us.read_receipts_enabled
      FROM public.user_settings us
      WHERE us.user_id = auth.uid()
    ), true)
    AND EXISTS (
      SELECT 1
      FROM public.messages m
      JOIN public.conversation_participants cp
        ON cp.conversation_id = m.conversation_id
      WHERE m.id = message_reads.message_id
        AND cp.user_id = auth.uid()
    )
  );

CREATE OR REPLACE FUNCTION public.are_contacts(a uuid, b uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.follows f1
    JOIN public.follows f2
      ON f2.follower_id = b AND f2.following_id = a
    WHERE f1.follower_id = a AND f1.following_id = b
  );
$$;

CREATE OR REPLACE FUNCTION public.can_view_presence(target_user_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  viewer uuid := auth.uid();
  visibility text;
  exception_rule text;
BEGIN
  IF viewer IS NULL THEN
    RETURN false;
  END IF;
  IF viewer = target_user_id THEN
    RETURN true;
  END IF;

  SELECT rule INTO exception_rule
  FROM public.user_privacy_exceptions
  WHERE user_id = target_user_id AND target_user_id = viewer
  LIMIT 1;

  IF exception_rule = 'allow' THEN
    RETURN true;
  ELSIF exception_rule = 'deny' THEN
    RETURN false;
  END IF;

  SELECT coalesce(last_seen_visibility, 'everyone') INTO visibility
  FROM public.user_settings
  WHERE user_id = target_user_id;

  visibility := coalesce(visibility, 'everyone');

  IF visibility = 'everyone' THEN
    RETURN true;
  ELSIF visibility = 'contacts' THEN
    RETURN public.are_contacts(target_user_id, viewer);
  END IF;

  RETURN false;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_visible_presence(target_user_id uuid)
RETURNS TABLE(user_id uuid, is_online boolean, last_seen timestamptz)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    p.id AS user_id,
    CASE WHEN public.can_view_presence(target_user_id) THEN coalesce(p.is_online, false) ELSE false END AS is_online,
    CASE WHEN public.can_view_presence(target_user_id) THEN p.last_seen ELSE null END AS last_seen
  FROM public.profiles p
  WHERE p.id = target_user_id
  LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.are_contacts(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_view_presence(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_visible_presence(uuid) TO authenticated;

DO $$
DECLARE
  table_names text[] := ARRAY[
    'message_reactions',
    'message_edit_history',
    'message_drafts',
    'message_reads',
    'typing_indicators',
    'profiles'
  ];
  table_name text;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    FOREACH table_name IN ARRAY table_names LOOP
      IF to_regclass(format('public.%I', table_name)) IS NOT NULL
         AND NOT EXISTS (
           SELECT 1
           FROM pg_publication_tables
           WHERE pubname = 'supabase_realtime'
             AND schemaname = 'public'
             AND tablename = table_name
         ) THEN
        EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', table_name);
      END IF;
    END LOOP;
  END IF;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';
