BEGIN;

ALTER TABLE public.call_participants
  ADD COLUMN IF NOT EXISTS connection_state text NOT NULL DEFAULT 'connecting',
  ADD COLUMN IF NOT EXISTS network_quality text,
  ADD COLUMN IF NOT EXISTS last_seen_at timestamptz,
  ADD COLUMN IF NOT EXISTS device_info jsonb,
  ADD COLUMN IF NOT EXISTS screen_share_track_id text;

CREATE INDEX IF NOT EXISTS idx_call_participants_call_user
  ON public.call_participants(call_id, user_id);

CREATE INDEX IF NOT EXISTS idx_call_participants_call_state
  ON public.call_participants(call_id, connection_state, last_seen_at DESC);

CREATE TABLE IF NOT EXISTS public.call_room_members (
  call_id uuid NOT NULL REFERENCES public.video_calls(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  role text NOT NULL DEFAULT 'participant',
  connection_state text NOT NULL DEFAULT 'connecting',
  media_state jsonb NOT NULL DEFAULT '{}'::jsonb,
  joined_at timestamptz NOT NULL DEFAULT now(),
  left_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (call_id, user_id)
);

ALTER TABLE public.call_room_members ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_call_room_members_call_id
  ON public.call_room_members(call_id);

CREATE INDEX IF NOT EXISTS idx_call_room_members_user_id
  ON public.call_room_members(user_id);

CREATE OR REPLACE FUNCTION public.can_view_call(p_call_id uuid, p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.video_calls vc
    JOIN public.conversation_participants cp
      ON cp.conversation_id = vc.conversation_id
    WHERE vc.id = p_call_id
      AND (vc.host_id = p_user_id OR cp.user_id = p_user_id)
  );
$$;

CREATE OR REPLACE FUNCTION public.join_video_call(
  p_call_id uuid,
  p_is_video_on boolean DEFAULT true
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
    RAISE EXCEPTION 'not_call_participant';
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
    last_seen_at
  )
  VALUES (
    p_call_id,
    v_user_id,
    now(),
    NULL,
    false,
    p_is_video_on,
    false,
    false,
    'connecting',
    now()
  )
  ON CONFLICT (call_id, user_id) DO UPDATE SET
    joined_at = COALESCE(public.call_participants.joined_at, excluded.joined_at),
    left_at = NULL,
    is_video_on = excluded.is_video_on,
    connection_state = 'connecting',
    last_seen_at = now();
END;
$$;

CREATE OR REPLACE FUNCTION public.decline_video_call(p_call_id uuid)
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
    RAISE EXCEPTION 'not_call_participant';
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
    last_seen_at
  )
  VALUES (
    p_call_id,
    v_user_id,
    NULL,
    now(),
    false,
    false,
    false,
    false,
    'declined',
    now()
  )
  ON CONFLICT (call_id, user_id) DO UPDATE SET
    left_at = now(),
    connection_state = 'declined',
    last_seen_at = now();
END;
$$;

GRANT EXECUTE ON FUNCTION public.can_view_call(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.join_video_call(uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.decline_video_call(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.sync_call_participant_to_room_member()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
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
    NEW.call_id,
    NEW.user_id,
    COALESCE(
      (
        SELECT 'host'
        FROM public.video_calls
        WHERE id = NEW.call_id
          AND host_id = NEW.user_id
      ),
      'participant'
    ),
    COALESCE(NEW.connection_state, 'connecting'),
    jsonb_build_object(
      'is_muted', COALESCE(NEW.is_muted, false),
      'is_video_on', COALESCE(NEW.is_video_on, true),
      'is_screen_sharing', COALESCE(NEW.is_screen_sharing, false),
      'is_hand_raised', COALESCE(NEW.is_hand_raised, false)
    ),
    NEW.joined_at,
    NEW.left_at,
    now()
  )
  ON CONFLICT (call_id, user_id) DO UPDATE SET
    connection_state = EXCLUDED.connection_state,
    media_state = EXCLUDED.media_state,
    left_at = EXCLUDED.left_at,
    updated_at = now();

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS sync_call_participant_trigger ON public.call_participants;
CREATE TRIGGER sync_call_participant_trigger
  AFTER INSERT OR UPDATE ON public.call_participants
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_call_participant_to_room_member();

DROP POLICY IF EXISTS "Call participants viewable" ON public.call_participants;
CREATE POLICY "Call participants viewable"
  ON public.call_participants
  FOR SELECT
  TO authenticated
  USING (
    user_id = auth.uid()
    OR public.can_view_call(call_id, auth.uid())
  );

DROP POLICY IF EXISTS "Users can join calls" ON public.call_participants;
CREATE POLICY "Users can join calls"
  ON public.call_participants
  FOR INSERT
  TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    AND public.can_view_call(call_id, auth.uid())
  );

DROP POLICY IF EXISTS "Users can update own participation" ON public.call_participants;
CREATE POLICY "Users can update own participation"
  ON public.call_participants
  FOR UPDATE
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Call host can invite conversation participants" ON public.call_participants;
CREATE POLICY "Call host can invite conversation participants"
  ON public.call_participants
  FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.video_calls vc
      JOIN public.conversation_participants cp
        ON cp.conversation_id = vc.conversation_id
       AND cp.user_id = call_participants.user_id
      WHERE vc.id = call_participants.call_id
        AND vc.host_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Calls viewable by participants" ON public.video_calls;
CREATE POLICY "Calls viewable by participants"
  ON public.video_calls
  FOR SELECT
  TO authenticated
  USING (
    host_id = auth.uid()
    OR EXISTS (
      SELECT 1
      FROM public.conversation_participants cp
      WHERE cp.conversation_id = video_calls.conversation_id
        AND cp.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Call participants read room members" ON public.call_room_members;
CREATE POLICY "Call participants read room members"
  ON public.call_room_members
  FOR SELECT
  TO authenticated
  USING (
    user_id = auth.uid()
    OR public.can_view_call(call_id, auth.uid())
  );

DROP POLICY IF EXISTS "Users write own call room member state" ON public.call_room_members;
DROP POLICY IF EXISTS "Users insert own call room member state" ON public.call_room_members;
DROP POLICY IF EXISTS "Users update own call room member state" ON public.call_room_members;
DROP POLICY IF EXISTS "Users delete own call room member state" ON public.call_room_members;

CREATE POLICY "Users insert own call room member state"
  ON public.call_room_members
  FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users update own call room member state"
  ON public.call_room_members
  FOR UPDATE
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users delete own call room member state"
  ON public.call_room_members
  FOR DELETE
  TO authenticated
  USING (user_id = auth.uid());

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'video_calls'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.video_calls;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'call_participants'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.call_participants;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'call_room_members'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.call_room_members;
  END IF;
END $$;

COMMIT;
NOTIFY pgrst, 'reload schema';
