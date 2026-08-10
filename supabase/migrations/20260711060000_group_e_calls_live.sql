BEGIN;

CREATE INDEX IF NOT EXISTS idx_video_calls_conversation_status
  ON public.video_calls(conversation_id, status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_call_participants_call_user
  ON public.call_participants(call_id, user_id);

DROP POLICY IF EXISTS "Users can join calls" ON public.call_participants;
CREATE POLICY "Users can join calls"
  ON public.call_participants
  FOR INSERT
  TO authenticated
  WITH CHECK (
    auth.uid() = user_id
    AND EXISTS (
      SELECT 1
      FROM public.video_calls vc
      JOIN public.conversation_participants cp
        ON cp.conversation_id = vc.conversation_id
      WHERE vc.id = call_participants.call_id
        AND cp.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Users can update own participation" ON public.call_participants;
CREATE POLICY "Users can update own participation"
  ON public.call_participants
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

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
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  IF p_call_type NOT IN ('audio', 'video', 'screen') THEN
    RAISE EXCEPTION 'invalid_call_type';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.conversation_participants cp
    WHERE cp.conversation_id = p_conversation_id
      AND cp.user_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'not_conversation_participant';
  END IF;

  INSERT INTO public.video_calls (
    conversation_id,
    host_id,
    call_type,
    status,
    started_at
  )
  VALUES (
    p_conversation_id,
    v_user_id,
    p_call_type,
    'active',
    now()
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
    is_hand_raised
  )
  VALUES (
    v_call_id,
    v_user_id,
    now(),
    NULL,
    false,
    p_is_video_on,
    false,
    false
  )
  ON CONFLICT (call_id, user_id) DO UPDATE SET
    joined_at = excluded.joined_at,
    left_at = NULL,
    is_video_on = excluded.is_video_on;

  RETURN v_call_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_video_call(uuid, text, boolean)
  TO authenticated;

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
END $$;

-- RLS audit: create_video_call validates auth.uid() membership before privileged inserts; participant rows remain readable/updatable only by call/conversation participants.
NOTIFY pgrst, 'reload schema';

COMMIT;
