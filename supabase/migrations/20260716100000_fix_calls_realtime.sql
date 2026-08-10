-- Fix video/audio calls realtime issues
-- 1. Add missing foreign key for call_room_members
-- 2. Add missing error handling and logging
-- 3. Ensure all RLS policies are correct
-- 4. Add realtime publication for critical tables

BEGIN;

-- Fix call_room_members foreign key (missing in previous migration)
DO $$
BEGIN
  -- Check if constraint already exists
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'call_room_members_call_id_fkey'
  ) THEN
    ALTER TABLE public.call_room_members
      ADD CONSTRAINT call_room_members_call_id_fkey
      FOREIGN KEY (call_id)
      REFERENCES public.video_calls(id)
      ON DELETE CASCADE;
  END IF;
END $$;

-- Ensure call_room_members has proper indexes
CREATE INDEX IF NOT EXISTS idx_call_room_members_call_id
  ON public.call_room_members(call_id);

CREATE INDEX IF NOT EXISTS idx_call_room_members_user_id
  ON public.call_room_members(user_id);

-- Fix RLS policies for call_room_members
DROP POLICY IF EXISTS "Users write own call room member state" ON public.call_room_members;
CREATE POLICY "Users write own call room member state"
  ON public.call_room_members
  FOR ALL
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Call participants read room members" ON public.call_room_members;
CREATE POLICY "Call participants read room members"
  ON public.call_room_members
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.video_calls vc
      JOIN public.conversation_participants cp
        ON cp.conversation_id = vc.conversation_id
      WHERE vc.id = call_room_members.call_id
        AND cp.user_id = auth.uid()
    )
  );

-- Ensure call_participants has proper RLS for SELECT
DROP POLICY IF EXISTS "Call participants viewable" ON public.call_participants;
CREATE POLICY "Call participants viewable"
  ON public.call_participants
  FOR SELECT
  TO authenticated
  USING (
    user_id = auth.uid()
    OR EXISTS (
      SELECT 1
      FROM public.video_calls vc
      JOIN public.conversation_participants cp
        ON cp.conversation_id = vc.conversation_id
      WHERE vc.id = call_participants.call_id
        AND cp.user_id = auth.uid()
    )
  );

-- Fix video_calls RLS policy
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

-- Ensure video_calls can be updated by host
DROP POLICY IF EXISTS "Call host can update call" ON public.video_calls;
CREATE POLICY "Call host can update call"
  ON public.video_calls
  FOR UPDATE
  TO authenticated
  USING (host_id = auth.uid())
  WITH CHECK (host_id = auth.uid());

-- Add realtime publication for call_room_members if not exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'call_room_members'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.call_room_members;
  END IF;
END $$;

-- Create helper function to check if user can view call
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

GRANT EXECUTE ON FUNCTION public.can_view_call(uuid, uuid) TO authenticated;

-- Improve create_video_call function with better error handling
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
  -- Validate user is authenticated
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING HINT = 'User must be logged in to create a call';
  END IF;

  -- Validate call type
  IF p_call_type NOT IN ('audio', 'video', 'screen') THEN
    RAISE EXCEPTION 'invalid_call_type' USING HINT = 'Call type must be audio, video, or screen';
  END IF;

  -- Validate user is conversation participant
  IF NOT EXISTS (
    SELECT 1
    FROM public.conversation_participants cp
    WHERE cp.conversation_id = p_conversation_id
      AND cp.user_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'not_conversation_participant' USING HINT = 'User must be a participant in the conversation';
  END IF;

  -- Create video call
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

  -- Add host as participant
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
    v_call_id,
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
    joined_at = excluded.joined_at,
    left_at = NULL,
    is_video_on = excluded.is_video_on,
    connection_state = 'connecting',
    last_seen_at = now();

  -- Add to call_room_members
  INSERT INTO public.call_room_members (
    call_id,
    user_id,
    role,
    connection_state,
    media_state,
    joined_at,
    updated_at
  )
  VALUES (
    v_call_id,
    v_user_id,
    'host',
    'connecting',
    jsonb_build_object(
      'is_muted', false,
      'is_video_on', p_is_video_on,
      'is_screen_sharing', false,
      'is_hand_raised', false
    ),
    now(),
    now()
  )
  ON CONFLICT (call_id, user_id) DO UPDATE SET
    connection_state = 'connecting',
    left_at = NULL,
    updated_at = now();

  RETURN v_call_id;
END;
$$;

-- Add trigger to sync call_participants to call_room_members
CREATE OR REPLACE FUNCTION public.sync_call_participant_to_room_member()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN
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
        (SELECT 'host' FROM public.video_calls WHERE id = NEW.call_id AND host_id = NEW.user_id),
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
      connection_state = COALESCE(NEW.connection_state, call_room_members.connection_state),
      media_state = jsonb_build_object(
        'is_muted', COALESCE(NEW.is_muted, false),
        'is_video_on', COALESCE(NEW.is_video_on, true),
        'is_screen_sharing', COALESCE(NEW.is_screen_sharing, false),
        'is_hand_raised', COALESCE(NEW.is_hand_raised, false)
      ),
      left_at = NEW.left_at,
      updated_at = now();
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS sync_call_participant_trigger ON public.call_participants;
CREATE TRIGGER sync_call_participant_trigger
  AFTER INSERT OR UPDATE ON public.call_participants
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_call_participant_to_room_member();

COMMIT;
NOTIFY pgrst, 'reload schema';
