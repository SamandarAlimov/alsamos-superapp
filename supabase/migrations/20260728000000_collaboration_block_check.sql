BEGIN;

-- Strengthen the INSERT policy on post_collaborators to prevent inviting blocked users
DROP POLICY IF EXISTS "Post owners can invite collaborators" ON public.post_collaborators;
CREATE POLICY "Post owners can invite collaborators"
  ON public.post_collaborators
  FOR INSERT
  TO authenticated
  WITH CHECK (
    auth.uid() = invited_by
    AND EXISTS (
      SELECT 1
      FROM public.posts p
      WHERE p.id = post_collaborators.post_id
        AND p.user_id = auth.uid()
    )
    AND NOT EXISTS (
      SELECT 1
      FROM public.user_blocks ub
      WHERE (ub.blocker_id = auth.uid() AND ub.blocked_id = post_collaborators.user_id)
         OR (ub.blocker_id = post_collaborators.user_id AND ub.blocked_id = auth.uid())
    )
  );

-- Strengthen the UPDATE (respond) policy to prevent accepting if blocked since invite
DROP POLICY IF EXISTS "Users can respond to collaboration invites" ON public.post_collaborators;
CREATE POLICY "Users can respond to collaboration invites"
  ON public.post_collaborators
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (
    auth.uid() = user_id
    AND status IN ('accepted', 'declined')
    AND NOT EXISTS (
      SELECT 1
      FROM public.user_blocks ub
      WHERE (ub.blocker_id = auth.uid() AND ub.blocked_id = post_collaborators.invited_by)
         OR (ub.blocker_id = post_collaborators.invited_by AND ub.blocked_id = auth.uid())
    )
  );

COMMIT;

NOTIFY pgrst, 'reload schema';
