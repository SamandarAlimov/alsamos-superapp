BEGIN;

-- Professional RTC runtime hardening.
-- Additive/idempotent: this migration strengthens the already-created call
-- schema without renaming existing tables or invalidating older clients.

ALTER TABLE public.video_calls
  ADD COLUMN IF NOT EXISTS last_heartbeat_at timestamptz,
  ADD COLUMN IF NOT EXISTS ended_at timestamptz,
  ADD COLUMN IF NOT EXISTS metadata jsonb NOT NULL DEFAULT '{}'::jsonb;

ALTER TABLE public.call_participants
  ADD COLUMN IF NOT EXISTS connection_state text NOT NULL DEFAULT 'joining',
  ADD COLUMN IF NOT EXISTS last_seen_at timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS device_info jsonb NOT NULL DEFAULT '{}'::jsonb;

ALTER TABLE public.call_participants
  DROP CONSTRAINT IF EXISTS call_participants_connection_state_check;

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

CREATE INDEX IF NOT EXISTS idx_video_calls_runtime_active
  ON public.video_calls(status, last_heartbeat_at DESC, created_at DESC)
  WHERE ended_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_call_participants_runtime_seen
  ON public.call_participants(call_id, left_at, last_seen_at DESC);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'call_participants_call_user_unique'
      AND conrelid = 'public.call_participants'::regclass
  ) THEN
    ALTER TABLE public.call_participants
      ADD CONSTRAINT call_participants_call_user_unique
      UNIQUE (call_id, user_id);
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.heartbeat_video_call(
  p_call_id uuid,
  p_is_muted boolean DEFAULT false,
  p_is_video_on boolean DEFAULT true,
  p_is_screen_sharing boolean DEFAULT false,
  p_is_hand_raised boolean DEFAULT false,
  p_device_info jsonb DEFAULT '{}'::jsonb
)
RETURNS boolean
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT public.can_view_call(p_call_id, v_user_id) THEN
    RAISE EXCEPTION 'Not authorized to heartbeat this call';
  END IF;

  INSERT INTO public.call_participants (
    call_id,
    user_id,
    joined_at,
    left_at,
    is_muted,
    is_video_on,
    is_screen_sharing,
    is_hand_raised,
    connection_state,
    last_seen_at,
    device_info
  )
  VALUES (
    p_call_id,
    v_user_id,
    now(),
    NULL,
    COALESCE(p_is_muted, false),
    COALESCE(p_is_video_on, true),
    COALESCE(p_is_screen_sharing, false),
    COALESCE(p_is_hand_raised, false),
    'connected',
    now(),
    COALESCE(p_device_info, '{}'::jsonb)
  )
  ON CONFLICT (call_id, user_id) DO UPDATE
  SET left_at = NULL,
      is_muted = EXCLUDED.is_muted,
      is_video_on = EXCLUDED.is_video_on,
      is_screen_sharing = EXCLUDED.is_screen_sharing,
      is_hand_raised = EXCLUDED.is_hand_raised,
      connection_state = 'connected',
      last_seen_at = now(),
      device_info = COALESCE(EXCLUDED.device_info, public.call_participants.device_info);

  UPDATE public.video_calls
  SET last_heartbeat_at = now(),
      status = CASE
        WHEN status IN ('waiting', 'ringing', 'calling', 'connecting') THEN 'active'
        ELSE status
      END,
      started_at = COALESCE(started_at, now())
  WHERE id = p_call_id
    AND ended_at IS NULL;

  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.heartbeat_video_call(uuid, boolean, boolean, boolean, boolean, jsonb)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.heartbeat_video_call(uuid, boolean, boolean, boolean, boolean, jsonb)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.expire_stale_video_calls(
  p_stale_after interval DEFAULT interval '90 seconds'
)
RETURNS integer
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rows integer := 0;
BEGIN
  UPDATE public.call_participants cp
  SET left_at = COALESCE(cp.left_at, now()),
      connection_state = 'expired',
      last_seen_at = COALESCE(cp.last_seen_at, now())
  FROM public.video_calls vc
  WHERE cp.call_id = vc.id
    AND cp.left_at IS NULL
    AND COALESCE(cp.last_seen_at, vc.last_heartbeat_at, vc.created_at)
      < now() - COALESCE(p_stale_after, interval '90 seconds')
    AND vc.ended_at IS NULL;

  UPDATE public.video_calls vc
  SET status = 'ended',
      ended_at = COALESCE(vc.ended_at, now()),
      last_heartbeat_at = COALESCE(vc.last_heartbeat_at, now())
  WHERE vc.ended_at IS NULL
    AND vc.status IN ('waiting', 'ringing', 'calling', 'connecting', 'active')
    AND NOT EXISTS (
      SELECT 1
      FROM public.call_participants cp
      WHERE cp.call_id = vc.id
        AND cp.left_at IS NULL
        AND COALESCE(cp.last_seen_at, vc.last_heartbeat_at, vc.created_at)
          >= now() - COALESCE(p_stale_after, interval '90 seconds')
    );

  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_rows;
END;
$$;

REVOKE ALL ON FUNCTION public.expire_stale_video_calls(interval) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.expire_stale_video_calls(interval)
  TO authenticated, service_role;

DROP FUNCTION IF EXISTS public.cleanup_expired_call_signals();

CREATE FUNCTION public.cleanup_expired_call_signals()
RETURNS integer
LANGUAGE plpgsql
VOLATILE
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

REVOKE ALL ON FUNCTION public.cleanup_expired_call_signals() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cleanup_expired_call_signals()
  TO service_role;

DO $$
DECLARE
  v_table text;
BEGIN
  FOREACH v_table IN ARRAY ARRAY[
    'video_calls',
    'call_participants',
    'call_room_members',
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
