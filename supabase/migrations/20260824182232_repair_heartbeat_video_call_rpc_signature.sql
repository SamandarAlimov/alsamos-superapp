-- Repair PostgREST RPC lookup for the WebRTC heartbeat call used by Flutter.
-- Some deployed databases still miss the latest heartbeat_video_call signature,
-- and the client sends named params in the order logged by PostgREST as:
-- p_call_id, p_device_info, p_is_hand_raised, p_is_muted,
-- p_is_screen_sharing, p_is_video_on.

CREATE OR REPLACE FUNCTION public.heartbeat_video_call(
  p_call_id uuid,
  p_device_info jsonb DEFAULT '{}'::jsonb,
  p_is_hand_raised boolean DEFAULT false,
  p_is_muted boolean DEFAULT false,
  p_is_screen_sharing boolean DEFAULT false,
  p_is_video_on boolean DEFAULT true
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

REVOKE ALL ON FUNCTION public.heartbeat_video_call(
  uuid,
  jsonb,
  boolean,
  boolean,
  boolean,
  boolean
) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.heartbeat_video_call(
  uuid,
  jsonb,
  boolean,
  boolean,
  boolean,
  boolean
) TO authenticated;

NOTIFY pgrst, 'reload schema';
