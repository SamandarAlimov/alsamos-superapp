BEGIN;

ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS live_location_expires_at timestamptz,
  ADD COLUMN IF NOT EXISTS live_location_stopped_at timestamptz;

ALTER TABLE public.user_settings
  ADD COLUMN IF NOT EXISTS two_factor_recovery_hint text,
  ADD COLUMN IF NOT EXISTS two_factor_recovery_updated_at timestamptz;

CREATE INDEX IF NOT EXISTS idx_messages_live_location_active
  ON public.messages(conversation_id, live_location_expires_at)
  WHERE media_type = 'live_location' AND live_location_stopped_at IS NULL;

CREATE TABLE IF NOT EXISTS public.user_media_download_policy (
  user_id uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  images_wifi boolean NOT NULL DEFAULT true,
  images_mobile boolean NOT NULL DEFAULT true,
  videos_wifi boolean NOT NULL DEFAULT false,
  videos_mobile boolean NOT NULL DEFAULT false,
  files_wifi boolean NOT NULL DEFAULT false,
  files_mobile boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.user_media_download_policy ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users manage own media download policy" ON public.user_media_download_policy;
CREATE POLICY "Users manage own media download policy"
  ON public.user_media_download_policy FOR ALL
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE OR REPLACE FUNCTION public.is_conversation_restricted(
  p_conversation_id uuid,
  p_user_id uuid,
  p_kind text DEFAULT NULL
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.conversation_restrictions r
    WHERE r.conversation_id = p_conversation_id
      AND r.user_id = p_user_id
      AND (p_kind IS NULL OR r.kind = p_kind)
      AND (r.until_at IS NULL OR r.until_at > now())
  );
$$;

CREATE OR REPLACE FUNCTION public.can_read_conversation(
  p_conversation_id uuid,
  p_user_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.conversation_participants cp
    WHERE cp.conversation_id = p_conversation_id
      AND cp.user_id = p_user_id
  )
  AND NOT public.is_conversation_restricted(p_conversation_id, p_user_id, 'banned');
$$;

CREATE OR REPLACE FUNCTION public.can_join_conversation(
  p_conversation_id uuid,
  p_user_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT NOT public.is_conversation_restricted(p_conversation_id, p_user_id, 'banned')
  AND NOT public.is_conversation_restricted(p_conversation_id, p_user_id, 'join_blocked');
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
  v_blocked boolean;
BEGIN
  IF NOT public.can_read_conversation(p_conversation_id, p_sender_id) THEN
    RETURN false;
  END IF;
  IF public.is_conversation_restricted(p_conversation_id, p_sender_id, 'muted') THEN
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

DROP POLICY IF EXISTS "Participants can read messages" ON public.messages;
CREATE POLICY "Participants can read messages"
  ON public.messages FOR SELECT
  USING (public.can_read_conversation(conversation_id, auth.uid()));

DROP POLICY IF EXISTS "Users can send messages" ON public.messages;
CREATE POLICY "Users can send messages"
  ON public.messages FOR INSERT
  WITH CHECK (
    sender_id = auth.uid()
    AND public.can_send_message_to_conversation(conversation_id, auth.uid())
  );

DROP POLICY IF EXISTS "Participants can update own live location metadata" ON public.messages;
CREATE POLICY "Participants can update own live location metadata"
  ON public.messages FOR UPDATE
  USING (
    sender_id = auth.uid()
    AND media_type = 'live_location'
    AND public.can_read_conversation(conversation_id, auth.uid())
  )
  WITH CHECK (
    sender_id = auth.uid()
    AND media_type = 'live_location'
    AND public.can_read_conversation(conversation_id, auth.uid())
  );

DROP POLICY IF EXISTS "Participants can join when not restricted" ON public.conversation_participants;
CREATE POLICY "Participants can join when not restricted"
  ON public.conversation_participants FOR INSERT
  WITH CHECK (
    user_id = auth.uid()
    AND public.can_join_conversation(conversation_id, auth.uid())
  );

CREATE INDEX IF NOT EXISTS idx_conversation_restrictions_active
  ON public.conversation_restrictions(conversation_id, user_id, kind, until_at);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'user_media_download_policy'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.user_media_download_policy;
  END IF;
END $$;

COMMIT;
NOTIFY pgrst, 'reload schema';

-- RLS audit: read/send/join are now guarded by derived conversation restriction RPCs; user media policy is own-row only.
