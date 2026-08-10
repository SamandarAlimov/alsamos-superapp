BEGIN;

-- Allow invited users to accept or decline collaboration invites
DROP POLICY IF EXISTS "Users can respond to collaboration invites" ON public.post_collaborators;
CREATE POLICY "Users can respond to collaboration invites"
  ON public.post_collaborators
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (
    auth.uid() = user_id
    AND status IN ('accepted', 'declined')
  );

-- Allow post owners to remove/cancel collaborators
DROP POLICY IF EXISTS "Post owners can remove collaborators" ON public.post_collaborators;
CREATE POLICY "Post owners can remove collaborators"
  ON public.post_collaborators
  FOR DELETE
  TO authenticated
  USING (
    auth.uid() = invited_by
    OR auth.uid() = user_id
    OR EXISTS (
      SELECT 1
      FROM public.posts p
      WHERE p.id = post_collaborators.post_id
        AND p.user_id = auth.uid()
    )
  );

-- RPC: respond to a collaboration invite (accept or decline)
CREATE OR REPLACE FUNCTION public.respond_collaboration_invite(
  p_collaboration_id uuid,
  p_response text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_collab record;
  v_post record;
BEGIN
  IF p_response NOT IN ('accepted', 'declined') THEN
    RAISE EXCEPTION 'invalid_response: must be accepted or declined';
  END IF;

  SELECT * INTO v_collab
  FROM post_collaborators
  WHERE id = p_collaboration_id AND user_id = auth.uid();

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found: collaboration invite not found';
  END IF;

  IF v_collab.status != 'pending' THEN
    RAISE EXCEPTION 'already_responded: invite already %', v_collab.status;
  END IF;

  UPDATE post_collaborators
  SET status = p_response, responded_at = now()
  WHERE id = p_collaboration_id;

  SELECT id, user_id INTO v_post
  FROM posts WHERE id = v_collab.post_id;

  -- Create notification for the post owner
  IF v_post.user_id IS NOT NULL THEN
    INSERT INTO notifications (user_id, type, actor_id, reference_id, reference_type, content)
    VALUES (
      v_post.user_id,
      CASE WHEN p_response = 'accepted' THEN 'collaboration_accepted' ELSE 'collaboration_declined' END,
      auth.uid(),
      v_collab.post_id::text,
      'post',
      CASE WHEN p_response = 'accepted'
        THEN 'Hamkorlik qabul qilindi'
        ELSE 'Hamkorlik rad etildi'
      END
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'status', p_response,
    'collaboration_id', p_collaboration_id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.respond_collaboration_invite(uuid, text) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';
