BEGIN;

ALTER TABLE public.video_calls
  ADD COLUMN IF NOT EXISTS call_mode text NOT NULL DEFAULT 'direct',
  ADD COLUMN IF NOT EXISTS title text,
  ADD COLUMN IF NOT EXISTS metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS last_heartbeat_at timestamptz;

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
  DROP CONSTRAINT IF EXISTS call_participants_role_check;

ALTER TABLE public.call_participants
  ADD CONSTRAINT call_participants_role_check CHECK (
    role IN ('host', 'speaker', 'member', 'viewer')
  ) NOT VALID;

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

ALTER TABLE public.call_room_members
  ADD COLUMN IF NOT EXISTS role text NOT NULL DEFAULT 'member',
  ADD COLUMN IF NOT EXISTS media_state jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

ALTER TABLE public.call_signals
  ADD COLUMN IF NOT EXISTS expires_at timestamptz NOT NULL DEFAULT (now() + interval '10 minutes');

CREATE INDEX IF NOT EXISTS idx_video_calls_mode_status_created
  ON public.video_calls(call_mode, status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_video_calls_conversation_open
  ON public.video_calls(conversation_id, status, created_at DESC)
  WHERE ended_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_call_participants_active_call
  ON public.call_participants(call_id, left_at, last_seen_at DESC);

CREATE INDEX IF NOT EXISTS idx_call_signals_expires_at
  ON public.call_signals(expires_at);

CREATE TABLE IF NOT EXISTS public.call_quality_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  call_id uuid NOT NULL REFERENCES public.video_calls(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  peer_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  quality text NOT NULL DEFAULT 'unknown',
  rtt_ms integer,
  jitter_ms integer,
  packets_lost integer,
  bitrate_kbps integer,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_call_quality_events_call_created
  ON public.call_quality_events(call_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_call_quality_events_user_created
  ON public.call_quality_events(user_id, created_at DESC);

ALTER TABLE public.call_quality_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "RTC quality readable by call members" ON public.call_quality_events;
CREATE POLICY "RTC quality readable by call members"
  ON public.call_quality_events
  FOR SELECT
  TO authenticated
  USING (public.can_view_call(call_id, (SELECT auth.uid())));

DROP POLICY IF EXISTS "RTC users insert own quality" ON public.call_quality_events;
CREATE POLICY "RTC users insert own quality"
  ON public.call_quality_events
  FOR INSERT
  TO authenticated
  WITH CHECK (
    user_id = (SELECT auth.uid())
    AND public.can_view_call(call_id, (SELECT auth.uid()))
  );

CREATE OR REPLACE FUNCTION public._rtc_has_column(
  p_table text,
  p_column text
)
RETURNS boolean
LANGUAGE sql
STABLE
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

REVOKE ALL ON FUNCTION public._rtc_has_column(text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._rtc_is_conversation_participant(uuid, uuid)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._rtc_has_column(text, text)
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public._rtc_is_conversation_participant(uuid, uuid)
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public._rtc_conversation_type(p_conversation_id uuid)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_type text;
BEGIN
  SELECT lower(COALESCE(c.type, 'direct'))
  INTO v_type
  FROM public.conversations c
  WHERE c.id = p_conversation_id;

  RETURN COALESCE(v_type, 'direct');
END;
$$;

REVOKE ALL ON FUNCTION public._rtc_conversation_type(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._rtc_conversation_type(uuid)
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public._rtc_default_call_mode(p_conversation_id uuid)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_type text := public._rtc_conversation_type(p_conversation_id);
BEGIN
  RETURN CASE
    WHEN v_type IN ('channel', 'public_channel', 'private_channel') THEN 'channel_stream'
    WHEN v_type IN ('group', 'supergroup') THEN 'group'
    WHEN v_type IN ('conference', 'room') THEN 'conference'
    ELSE 'direct'
  END;
END;
$$;

REVOKE ALL ON FUNCTION public._rtc_default_call_mode(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._rtc_default_call_mode(uuid)
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public._rtc_capacity_for_mode(p_call_mode text)
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE COALESCE(p_call_mode, 'direct')
    WHEN 'direct' THEN 2
    WHEN 'group' THEN 16
    WHEN 'conference' THEN 64
    WHEN 'channel_stream' THEN 200
    ELSE 8
  END;
$$;

CREATE OR REPLACE FUNCTION public.create_video_call(
  p_conversation_id uuid,
  p_call_type text DEFAULT 'video',
  p_is_video_on boolean DEFAULT true
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_call_id uuid;
  v_call_type text := COALESCE(NULLIF(lower(trim(p_call_type)), ''), 'video');
  v_call_mode text;
  v_max_participants integer;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated'
      USING HINT = 'User must be logged in to create a call';
  END IF;

  IF p_conversation_id IS NULL THEN
    RAISE EXCEPTION 'conversation_required';
  END IF;

  IF v_call_type NOT IN ('audio', 'video', 'screen', 'stream') THEN
    RAISE EXCEPTION 'invalid_call_type'
      USING HINT = 'Call type must be audio, video, screen, or stream';
  END IF;

  IF NOT public._rtc_is_conversation_participant(p_conversation_id, v_user_id) THEN
    RAISE EXCEPTION 'not_conversation_participant'
      USING HINT = 'User must be a participant in the conversation';
  END IF;

  v_call_mode := public._rtc_default_call_mode(p_conversation_id);
  IF v_call_type = 'stream' THEN
    v_call_mode := 'channel_stream';
  END IF;
  v_max_participants := public._rtc_capacity_for_mode(v_call_mode);

  PERFORM pg_advisory_xact_lock(hashtextextended(p_conversation_id::text, 0));

  UPDATE public.video_calls
  SET status = 'ended',
      ended_at = COALESCE(ended_at, now()),
      last_heartbeat_at = now()
  WHERE conversation_id = p_conversation_id
    AND status IN ('waiting', 'ringing', 'calling', 'connecting', 'active')
    AND ended_at IS NULL
    AND (
      v_call_mode IN ('direct', 'group')
      OR started_at IS NULL
    );

  INSERT INTO public.video_calls (
    conversation_id,
    host_id,
    status,
    call_type,
    call_mode,
    is_group_call,
    max_participants,
    started_at,
    created_at,
    last_heartbeat_at,
    metadata
  )
  VALUES (
    p_conversation_id,
    v_user_id,
    'ringing',
    v_call_type,
    v_call_mode,
    v_call_mode <> 'direct',
    v_max_participants,
    CASE WHEN v_call_mode = 'channel_stream' THEN now() ELSE NULL END,
    now(),
    now(),
    jsonb_build_object('created_by_rpc', true)
  )
  RETURNING id INTO v_call_id;

  INSERT INTO public.call_participants (
    call_id,
    user_id,
    joined_at,
    left_at,
    is_muted,
    is_video_on,
    is_screen_sharing,
    is_hand_raised,
    role,
    connection_state,
    last_seen_at
  )
  VALUES (
    v_call_id,
    v_user_id,
    now(),
    NULL,
    false,
    COALESCE(p_is_video_on, v_call_type <> 'audio'),
    false,
    false,
    'host',
    'joining',
    now()
  )
  ON CONFLICT (call_id, user_id) DO UPDATE SET
    left_at = NULL,
    is_video_on = EXCLUDED.is_video_on,
    role = 'host',
    connection_state = 'joining',
    last_seen_at = now();

  INSERT INTO public.call_room_members (
    call_id,
    user_id,
    role,
    connection_state,
    media_state,
    joined_at,
    left_at,
    updated_at
  )
  VALUES (
    v_call_id,
    v_user_id,
    'host',
    'joining',
    jsonb_build_object(
      'isMuted', false,
      'isVideoOn', COALESCE(p_is_video_on, v_call_type <> 'audio'),
      'isScreenSharing', false,
      'isHandRaised', false
    ),
    now(),
    NULL,
    now()
  )
  ON CONFLICT (call_id, user_id) DO UPDATE SET
    role = 'host',
    connection_state = 'joining',
    media_state = EXCLUDED.media_state,
    left_at = NULL,
    updated_at = now();

  INSERT INTO public.call_invites (
    call_id,
    inviter_id,
    invitee_id,
    conversation_id,
    call_type,
    status,
    created_at,
    updated_at
  )
  SELECT
    v_call_id,
    v_user_id,
    cp.user_id,
    p_conversation_id,
    v_call_type,
    'pending',
    now(),
    now()
  FROM public.conversation_participants cp
  WHERE cp.conversation_id = p_conversation_id
    AND cp.user_id <> v_user_id
  ON CONFLICT DO NOTHING;

  RETURN v_call_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.join_video_call_guarded(
  p_call_id uuid,
  p_is_video_on boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_call public.video_calls;
  v_active_count integer := 0;
  v_already_joined boolean := false;
  v_cap integer := 8;
  v_role text := 'member';
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(p_call_id::text, 0));

  SELECT *
  INTO v_call
  FROM public.video_calls
  WHERE id = p_call_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('joined', false, 'reason', 'call_not_found');
  END IF;

  IF NOT public.can_view_call(p_call_id, v_user_id) THEN
    RAISE EXCEPTION 'call_access_denied';
  END IF;

  IF v_call.status IN ('ended', 'declined', 'missed', 'cancelled')
     OR v_call.ended_at IS NOT NULL THEN
    RETURN jsonb_build_object('joined', false, 'reason', 'call_ended');
  END IF;

  v_cap := COALESCE(NULLIF(v_call.max_participants, 0), public._rtc_capacity_for_mode(v_call.call_mode));

  SELECT EXISTS (
    SELECT 1
    FROM public.call_participants
    WHERE call_id = p_call_id
      AND user_id = v_user_id
      AND left_at IS NULL
  )
  INTO v_already_joined;

  SELECT COUNT(*)::integer
  INTO v_active_count
  FROM public.call_participants
  WHERE call_id = p_call_id
    AND left_at IS NULL;

  IF NOT v_already_joined AND v_active_count >= v_cap THEN
    RETURN jsonb_build_object(
      'joined', false,
      'reason', 'call_full',
      'active_count', v_active_count,
      'max_participants', v_cap
    );
  END IF;

  v_role := CASE
    WHEN v_call.host_id = v_user_id THEN 'host'
    WHEN v_call.call_mode = 'channel_stream' THEN 'viewer'
    ELSE 'member'
  END;

  INSERT INTO public.call_participants (
    call_id,
    user_id,
    joined_at,
    left_at,
    is_muted,
    is_video_on,
    is_screen_sharing,
    is_hand_raised,
    role,
    connection_state,
    last_seen_at
  )
  VALUES (
    p_call_id,
    v_user_id,
    now(),
    NULL,
    false,
    COALESCE(p_is_video_on, true),
    false,
    false,
    v_role,
    'joining',
    now()
  )
  ON CONFLICT (call_id, user_id) DO UPDATE SET
    left_at = NULL,
    is_video_on = EXCLUDED.is_video_on,
    role = EXCLUDED.role,
    connection_state = 'joining',
    last_seen_at = now();

  INSERT INTO public.call_room_members (
    call_id,
    user_id,
    role,
    connection_state,
    media_state,
    joined_at,
    left_at,
    updated_at
  )
  VALUES (
    p_call_id,
    v_user_id,
    v_role,
    'joining',
    jsonb_build_object(
      'isMuted', false,
      'isVideoOn', COALESCE(p_is_video_on, true),
      'isScreenSharing', false,
      'isHandRaised', false
    ),
    now(),
    NULL,
    now()
  )
  ON CONFLICT (call_id, user_id) DO UPDATE SET
    role = EXCLUDED.role,
    connection_state = 'joining',
    media_state = EXCLUDED.media_state,
    left_at = NULL,
    updated_at = now();

  UPDATE public.call_invites
  SET status = 'accepted',
      updated_at = now()
  WHERE call_id = p_call_id
    AND invitee_id = v_user_id
    AND status IN ('pending', 'ringing');

  UPDATE public.video_calls
  SET status = 'active',
      started_at = COALESCE(started_at, now()),
      last_heartbeat_at = now()
  WHERE id = p_call_id
    AND status IN ('waiting', 'ringing', 'calling', 'connecting');

  RETURN jsonb_build_object(
    'joined', true,
    'call_id', p_call_id,
    'role', v_role,
    'active_count', v_active_count + CASE WHEN v_already_joined THEN 0 ELSE 1 END,
    'max_participants', v_cap
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.leave_video_call(p_call_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_call public.video_calls;
  v_active_count integer := 0;
  v_should_end boolean := false;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(p_call_id::text, 0));

  SELECT *
  INTO v_call
  FROM public.video_calls
  WHERE id = p_call_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('left', false, 'reason', 'call_not_found');
  END IF;

  IF NOT public.can_view_call(p_call_id, v_user_id) THEN
    RAISE EXCEPTION 'call_access_denied';
  END IF;

  UPDATE public.call_participants
  SET left_at = now(),
      connection_state = 'left',
      last_seen_at = now()
  WHERE call_id = p_call_id
    AND user_id = v_user_id;

  UPDATE public.call_room_members
  SET left_at = now(),
      connection_state = 'left',
      updated_at = now()
  WHERE call_id = p_call_id
    AND user_id = v_user_id;

  SELECT COUNT(*)::integer
  INTO v_active_count
  FROM public.call_participants
  WHERE call_id = p_call_id
    AND left_at IS NULL;

  v_should_end :=
    v_active_count = 0
    OR v_call.call_mode = 'direct'
    OR (v_call.call_mode = 'channel_stream' AND v_call.host_id = v_user_id);

  IF v_should_end THEN
    UPDATE public.video_calls
    SET status = 'ended',
        ended_at = COALESCE(ended_at, now()),
        last_heartbeat_at = now()
    WHERE id = p_call_id;

    UPDATE public.call_invites
    SET status = CASE
          WHEN status IN ('accepted') THEN status
          ELSE 'cancelled'
        END,
        updated_at = now()
    WHERE call_id = p_call_id
      AND status IN ('pending', 'ringing');

    DELETE FROM public.call_signals
    WHERE call_id = p_call_id;
  ELSE
    UPDATE public.video_calls
    SET last_heartbeat_at = now()
    WHERE id = p_call_id;
  END IF;

  RETURN jsonb_build_object(
    'left', true,
    'ended', v_should_end,
    'active_count', v_active_count
  );
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

CREATE OR REPLACE FUNCTION public.record_call_quality(
  p_call_id uuid,
  p_peer_id uuid DEFAULT NULL,
  p_quality text DEFAULT 'unknown',
  p_rtt_ms integer DEFAULT NULL,
  p_jitter_ms integer DEFAULT NULL,
  p_packets_lost integer DEFAULT NULL,
  p_bitrate_kbps integer DEFAULT NULL,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  IF NOT public.can_view_call(p_call_id, v_user_id) THEN
    RAISE EXCEPTION 'call_access_denied';
  END IF;

  INSERT INTO public.call_quality_events (
    call_id,
    user_id,
    peer_id,
    quality,
    rtt_ms,
    jitter_ms,
    packets_lost,
    bitrate_kbps,
    metadata
  )
  VALUES (
    p_call_id,
    v_user_id,
    p_peer_id,
    COALESCE(NULLIF(p_quality, ''), 'unknown'),
    p_rtt_ms,
    p_jitter_ms,
    p_packets_lost,
    p_bitrate_kbps,
    COALESCE(p_metadata, '{}'::jsonb)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.create_video_call(uuid, text, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.join_video_call_guarded(uuid, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.leave_video_call(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.cleanup_expired_call_signals() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.record_call_quality(uuid, uuid, text, integer, integer, integer, integer, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.create_video_call(uuid, text, boolean)
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.join_video_call_guarded(uuid, boolean)
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.leave_video_call(uuid)
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.cleanup_expired_call_signals()
  TO service_role;
GRANT EXECUTE ON FUNCTION public.record_call_quality(uuid, uuid, text, integer, integer, integer, integer, jsonb)
  TO authenticated, service_role;

GRANT SELECT, INSERT ON TABLE public.call_quality_events
  TO authenticated, service_role;

DO $$
DECLARE
  v_table text;
BEGIN
  FOREACH v_table IN ARRAY ARRAY[
    'video_calls',
    'call_participants',
    'call_room_members',
    'call_signals',
    'call_invites',
    'call_quality_events'
  ]
  LOOP
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
  END LOOP;
END $$;

COMMENT ON COLUMN public.video_calls.call_mode IS
  'RTC mode: direct 1:1, group calls, conference rooms, or channel livestreams.';
COMMENT ON TABLE public.call_quality_events IS
  'Best-effort WebRTC quality telemetry for call diagnostics and future adaptive routing.';
COMMENT ON FUNCTION public.create_video_call(uuid, text, boolean) IS
  'Creates Telegram-grade RTC calls for direct, group, conference, and channel stream conversations.';

COMMIT;

NOTIFY pgrst, 'reload schema';
