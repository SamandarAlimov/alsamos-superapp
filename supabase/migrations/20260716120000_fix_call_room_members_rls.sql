-- Fix infinite recursion in call_room_members RLS policy
-- The previous policy referenced video_calls -> conversation_participants
-- which could trigger recursive policy evaluation.
-- Solution: use the SECURITY DEFINER helper function can_view_call() which
-- bypasses RLS internally, or simplify to direct user_id check.

BEGIN;

-- Drop the problematic SELECT policy that causes infinite recursion
DROP POLICY IF EXISTS "Call participants read room members" ON public.call_room_members;

-- Replace with a simple policy: users can read room members for calls they participate in
-- Uses the existing SECURITY DEFINER function to avoid RLS recursion
CREATE POLICY "Call participants read room members"
  ON public.call_room_members
  FOR SELECT
  TO authenticated
  USING (
    user_id = auth.uid()
    OR public.can_view_call(call_id, auth.uid())
  );

-- Also fix the FOR ALL policy — split into specific operations to be explicit
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

COMMIT;
NOTIFY pgrst, 'reload schema';
