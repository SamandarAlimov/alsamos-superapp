BEGIN;

CREATE TABLE IF NOT EXISTS public.message_delivery_receipts (
  message_id uuid NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  delivered_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (message_id, user_id)
);
ALTER TABLE public.message_delivery_receipts ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_message_delivery_receipts_message
  ON public.message_delivery_receipts(message_id, delivered_at DESC);
CREATE INDEX IF NOT EXISTS idx_message_delivery_receipts_user
  ON public.message_delivery_receipts(user_id, delivered_at DESC);
DROP POLICY IF EXISTS "Participants view delivery receipts" ON public.message_delivery_receipts;
CREATE POLICY "Participants view delivery receipts"
  ON public.message_delivery_receipts FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.messages m
      JOIN public.conversation_participants cp
        ON cp.conversation_id = m.conversation_id
      WHERE m.id = message_delivery_receipts.message_id
        AND cp.user_id = auth.uid()
    )
  );
DROP POLICY IF EXISTS "Users mark own delivery receipts" ON public.message_delivery_receipts;
CREATE POLICY "Users mark own delivery receipts"
  ON public.message_delivery_receipts FOR INSERT
  WITH CHECK (
    user_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.messages m
      JOIN public.conversation_participants cp
        ON cp.conversation_id = m.conversation_id
      WHERE m.id = message_delivery_receipts.message_id
        AND cp.user_id = auth.uid()
        AND m.sender_id <> auth.uid()
    )
  );
DROP POLICY IF EXISTS "Users update own delivery receipts" ON public.message_delivery_receipts;
CREATE POLICY "Users update own delivery receipts"
  ON public.message_delivery_receipts FOR UPDATE
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE TABLE IF NOT EXISTS public.user_blocks (
  blocker_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  blocked_user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (blocker_id, blocked_user_id),
  CHECK (blocker_id <> blocked_user_id)
);
ALTER TABLE public.user_blocks ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_user_blocks_blocked ON public.user_blocks(blocked_user_id);
DROP POLICY IF EXISTS "Users manage own blocks" ON public.user_blocks;
CREATE POLICY "Users manage own blocks"
  ON public.user_blocks FOR ALL
  USING (blocker_id = auth.uid())
  WITH CHECK (blocker_id = auth.uid());

CREATE TABLE IF NOT EXISTS public.user_push_tokens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  token text NOT NULL UNIQUE,
  platform text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.user_push_tokens ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_user_push_tokens_user ON public.user_push_tokens(user_id);
DROP POLICY IF EXISTS "Users manage own push tokens" ON public.user_push_tokens;
CREATE POLICY "Users manage own push tokens"
  ON public.user_push_tokens FOR ALL
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE TABLE IF NOT EXISTS public.download_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  url text NOT NULL,
  file_name text,
  status text NOT NULL DEFAULT 'completed',
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.download_events ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_download_events_user_created
  ON public.download_events(user_id, created_at DESC);
DROP POLICY IF EXISTS "Users manage own download events" ON public.download_events;
CREATE POLICY "Users manage own download events"
  ON public.download_events FOR ALL
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE OR REPLACE FUNCTION public.is_blocked_between(a uuid, b uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_blocks
    WHERE (blocker_id = a AND blocked_user_id = b)
       OR (blocker_id = b AND blocked_user_id = a)
  );
$$;

CREATE OR REPLACE FUNCTION public.can_dm_user(p_sender_id uuid, p_recipient_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT NOT public.is_blocked_between(p_sender_id, p_recipient_id);
$$;

CREATE OR REPLACE FUNCTION public.can_send_message_to_conversation(
  p_conversation_id uuid,
  p_sender_id uuid
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_type text;
  v_blocked boolean;
BEGIN
  SELECT type INTO v_type FROM public.conversations WHERE id = p_conversation_id;
  IF v_type IS NULL THEN
    RETURN false;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.conversation_participants
    WHERE conversation_id = p_conversation_id AND user_id = p_sender_id
  ) THEN
    RETURN false;
  END IF;
  SELECT EXISTS (
    SELECT 1
    FROM public.conversation_participants cp
    JOIN public.user_blocks b
      ON (b.blocker_id = p_sender_id AND b.blocked_user_id = cp.user_id)
      OR (b.blocker_id = cp.user_id AND b.blocked_user_id = p_sender_id)
    WHERE cp.conversation_id = p_conversation_id
      AND cp.user_id <> p_sender_id
  ) INTO v_blocked;
  RETURN NOT COALESCE(v_blocked, false);
END;
$$;

GRANT EXECUTE ON FUNCTION public.is_blocked_between(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_dm_user(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_send_message_to_conversation(uuid, uuid) TO authenticated;

DROP POLICY IF EXISTS "Users can send messages" ON public.messages;
CREATE POLICY "Users can send messages"
  ON public.messages FOR INSERT
  WITH CHECK (
    sender_id = auth.uid()
    AND public.can_send_message_to_conversation(conversation_id, auth.uid())
  );

DROP POLICY IF EXISTS "Users can create calls" ON public.video_calls;
CREATE POLICY "Users can create calls"
  ON public.video_calls FOR INSERT
  WITH CHECK (
    host_id = auth.uid()
    AND public.can_send_message_to_conversation(conversation_id, auth.uid())
  );

CREATE OR REPLACE FUNCTION public.can_view_presence(target_user_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  visibility text;
BEGIN
  IF auth.uid() IS NULL THEN RETURN false; END IF;
  IF auth.uid() = target_user_id THEN RETURN true; END IF;
  IF public.is_blocked_between(auth.uid(), target_user_id) THEN RETURN false; END IF;
  SELECT coalesce(last_seen_visibility, 'everyone') INTO visibility
  FROM public.user_settings WHERE user_id = target_user_id;
  visibility := coalesce(visibility, 'everyone');
  IF visibility = 'nobody' THEN RETURN false; END IF;
  IF visibility = 'contacts' THEN RETURN public.are_contacts(auth.uid(), target_user_id); END IF;
  RETURN true;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'message_delivery_receipts'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.message_delivery_receipts;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'user_blocks'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.user_blocks;
  END IF;
END $$;

COMMIT;
NOTIFY pgrst, 'reload schema';
