BEGIN;

ALTER TABLE public.post_collaborators ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their collaborations" ON public.post_collaborators;
CREATE POLICY "Users can view their collaborations"
  ON public.post_collaborators
  FOR SELECT
  TO authenticated
  USING (
    auth.uid() = user_id
    OR auth.uid() = invited_by
    OR EXISTS (
      SELECT 1
      FROM public.posts p
      WHERE p.id = post_collaborators.post_id
        AND p.user_id = auth.uid()
    )
    OR (
      status = 'accepted'
      AND EXISTS (
        SELECT 1
        FROM public.posts p
        WHERE p.id = post_collaborators.post_id
          AND (
            p.visibility = 'public'
            OR p.user_id = auth.uid()
          )
      )
    )
  );

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'post_collaborators'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.post_collaborators;
  END IF;
END $$;

-- RLS audit: pending/declined collaboration invites stay visible only to the
-- involved users, while accepted collaborator metadata is readable through
-- public/readable parent posts for feed and profile display.

COMMIT;

NOTIFY pgrst, 'reload schema';
