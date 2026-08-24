BEGIN;

-- Runtime contract repair for the Flutter WebRTC caller.
-- This migration is intentionally additive/idempotent because some Lovable
-- databases already have earlier RTC patches applied while others only have
-- the base call tables.

CREATE OR REPLACE FUNCTION public._rtc_has_column(
  p_table text,
  p_column text
)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = p_table
      AND column_name = p_column
  );
$$;

CREATE OR REPLACE FUNCTION public._rtc_is_conversation_participant(
  p_conversation_id uuid,
  p_user_id uuid
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_allowed boolean := false;
  v_column text;
BEGIN
  IF p_conversation_id IS NULL OR p_user_id IS NULL THEN
    RETURN false;
  END IF;

  IF to_regclass('public.conversation_participants') IS NULL
     OR NOT public._rtc_has_column('conversation_participants', 'conversation_id') THEN
    RETURN false;
  END IF;

  FOREACH v_column IN ARRAY ARRAY['user_id', 'profile_id']
  LOOP
    IF public._rtc_has_column('conversation_participants', v_column) THEN
      EXECUTE format(
        'SELECT EXISTS (
           SELECT 1
           FROM public.conversation_participants
           WHERE conversation_id = $1
             AND %I = $2
         )',
        v_column
      )
      INTO v_allowed
      USING p_conversation_id, p_user_id;

      IF v_allowed THEN
        RETURN true;
      END IF;
    END IF;
  END LOOP;

  RETURN false;
END;
$$;

ALTER TABLE public.video_calls
  ADD COLUMN IF NOT EXISTS call_mode text NOT NULL DEFAULT 'direct',
  ADD COLUMN IF NOT EXISTS max_participants integer,
  ADD COLUMN IF NOT EXISTS started_at timestamptz,
  ADD COLUMN IF NOT EXISTS ended_at timestamptz,
  ADD COLUMN IF NOT EXISTS last_heartbeat_at timestamptz,
  ADD COLUMN IF NOT EXISTS metadata jsonb NOT NULL DEFAULT '{}'::jsonb;

ALTER TABLE public.video_calls
  DROP CONSTRAINT IF EXISTS video_calls_call_mode_check;

ALTER TABLE public.video_calls
  ADD CONSTRAINT video_calls_call_mode_check CHECK (
    call_mode IN ('direct', 'group', 'conference', 'channel_stream')
  ) NOT VALID;

ALTER TABLE public.video_calls
  DROP CONSTRAINT IF EXISTS video_calls_call_type_check;

ALTER TABLE public.video_calls
  ADD CONSTRAINT video_calls_call_type_check CHECK (
    call_type IN ('audio', 'video', 'screen', 'stream')
  ) NOT VALID;

ALTER TABLE public.call_participants
  ADD COLUMN IF NOT EXISTS role text NOT NULL DEFAULT 'member',
  ADD COLUMN IF NOT EXISTS connection_state text NOT NULL DEFAULT 'joining',
  ADD COLUMN IF NOT EXISTS last_seen_at timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS device_info jsonb NOT NULL DEFAULT '{}'::jsonb;

ALTER TABLE public.call_participants
  DROP CONSTRAINT IF EXISTS call_participants_connection_state_check;

ALTER TABLE public.call_participants
  DROP CONSTRAINT IF EXISTS call_participants_role_check;

ALTER TABLE public.call_participants
  ADD CONSTRAINT call_participants_role_check CHECK (
    role IN ('host', 'speaker', 'member', 'viewer')
  ) NOT VALID;

ALTER TABLE public.call_participants
  ADD CONSTRAINT call_participants_connection_state_check CHECK (
    connection_state IN (
      'invited',
      'ringing',
      'joining',
      'connecting',
      'connected',
      'reconnecting',
      'left',
      'declined',
      'kicked',
      'closed',
      'expired'
    )
  ) NOT VALID;

DO $$
BEGIN
  IF to_regclass('public.call_room_members') IS NOT NULL THEN
    ALTER TABLE public.call_room_members
      ADD COLUMN IF NOT EXISTS role text NOT NULL DEFAULT 'member',
      ADD COLUMN IF NOT EXISTS connection_state text NOT NULL DEFAULT 'joining',
      ADD COLUMN IF NOT EXISTS media_state jsonb NOT NULL DEFAULT '{}'::jsonb,
      ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

    ALTER TABLE public.call_room_members
      DROP CONSTRAINT IF EXISTS call_room_members_connection_state_check;

    ALTER TABLE public.call_room_members
      ADD CONSTRAINT call_room_members_connection_state_check CHECK (
        connection_state IN (
          'invited',
          'ringing',
          'joining',
          'connecting',
          'connected',
          'reconnecting',
          'left',
          'declined',
          'kicked',
          'closed',
          'expired'
        )
      ) NOT VALID;
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.call_signals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  call_id uuid NOT NULL REFERENCES public.video_calls(id) ON DELETE CASCADE,
  sender_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  target_user_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
  type text NOT NULL,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL DEFAULT (now() + interval '10 minutes')
);

ALTER TABLE public.call_signals
  ADD COLUMN IF NOT EXISTS target_user_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS expires_at timestamptz NOT NULL DEFAULT (now() + interval '10 minutes');

ALTER TABLE public.call_signals
  DROP CONSTRAINT IF EXISTS call_signals_type_check;

ALTER TABLE public.call_signals
  ADD CONSTRAINT call_signals_type_check CHECK (
    type IN (
      'offer',
      'answer',
      'ice',
      'ice-candidate',
      'media',
      'media-state',
      'leave',
      'resync'
    )
  ) NOT VALID;

CREATE INDEX IF NOT EXISTS idx_call_signals_call_created
  ON public.call_signals(call_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_call_signals_target_created
  ON public.call_signals(target_user_id, created_at DESC)
  WHERE target_user_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_call_signals_expires_at
  ON public.call_signals(expires_at);

CREATE OR REPLACE FUNCTION public.can_view_call(
  p_call_id uuid,
  p_user_id uuid
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_allowed boolean := false;
  v_conversation_id uuid;
BEGIN
  IF p_call_id IS NULL OR p_user_id IS NULL THEN
    RETURN false;
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.call_participants cp
    WHERE cp.call_id = p_call_id
      AND cp.user_id = p_user_id
  )
  INTO v_allowed;

  IF v_allowed THEN
    RETURN true;
  END IF;

  SELECT vc.conversation_id
  INTO v_conversation_id
  FROM public.video_calls vc
  WHERE vc.id = p_call_id;

  RETURN public._rtc_is_conversation_participant(v_conversation_id, p_user_id);
END;
$$;

DROP FUNCTION IF EXISTS public.cleanup_expired_call_signals();

CREATE FUNCTION public.cleanup_expired_call_signals()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_deleted integer := 0;
BEGIN
  DELETE FROM public.call_signals
  WHERE expires_at < now()
     OR created_at < now() - interval '1 hour';

  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$$;

ALTER TABLE public.call_signals ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "RTC call signals readable by members" ON public.call_signals;
CREATE POLICY "RTC call signals readable by members"
  ON public.call_signals
  FOR SELECT
  TO authenticated
  USING (
    public.can_view_call(call_id, (SELECT auth.uid()))
    AND (
      target_user_id IS NULL
      OR target_user_id = (SELECT auth.uid())
      OR sender_id = (SELECT auth.uid())
    )
  );

DROP POLICY IF EXISTS "RTC call members can insert signals" ON public.call_signals;
CREATE POLICY "RTC call members can insert signals"
  ON public.call_signals
  FOR INSERT
  TO authenticated
  WITH CHECK (
    sender_id = (SELECT auth.uid())
    AND public.can_view_call(call_id, (SELECT auth.uid()))
  );

DROP POLICY IF EXISTS "RTC users can delete own expired signals" ON public.call_signals;
CREATE POLICY "RTC users can delete own expired signals"
  ON public.call_signals
  FOR DELETE
  TO authenticated
  USING (
    sender_id = (SELECT auth.uid())
    OR expires_at < now()
  );

GRANT EXECUTE ON FUNCTION public._rtc_has_column(text, text)
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public._rtc_is_conversation_participant(uuid, uuid)
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.can_view_call(uuid, uuid)
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.cleanup_expired_call_signals()
  TO service_role;

GRANT SELECT, INSERT, DELETE ON TABLE public.call_signals
  TO authenticated, service_role;
GRANT SELECT, INSERT, UPDATE ON TABLE public.call_participants
  TO authenticated, service_role;

DO $$
DECLARE
  v_table text;
BEGIN
  FOREACH v_table IN ARRAY ARRAY[
    'video_calls',
    'call_participants',
    'call_signals',
    'call_invites'
  ]
  LOOP
    IF to_regclass(format('public.%I', v_table)) IS NOT NULL THEN
      EXECUTE format('ALTER TABLE public.%I REPLICA IDENTITY FULL', v_table);

      IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime')
         AND NOT EXISTS (
           SELECT 1
           FROM pg_publication_tables
           WHERE pubname = 'supabase_realtime'
             AND schemaname = 'public'
             AND tablename = v_table
         ) THEN
        EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', v_table);
      END IF;
    END IF;
  END LOOP;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';
