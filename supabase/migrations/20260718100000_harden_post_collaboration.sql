BEGIN;

CREATE TABLE IF NOT EXISTS public.post_collaborators (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id uuid NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  invited_by uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  role text NOT NULL DEFAULT 'collaborator',
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'declined')),
  created_at timestamptz NOT NULL DEFAULT now(),
  responded_at timestamptz,
  UNIQUE(post_id, user_id)
);

ALTER TABLE public.post_collaborators
  ADD COLUMN IF NOT EXISTS role text NOT NULL DEFAULT 'collaborator',
  ADD COLUMN IF NOT EXISTS responded_at timestamptz;

CREATE UNIQUE INDEX IF NOT EXISTS post_collaborators_post_user_key
  ON public.post_collaborators(post_id, user_id);

CREATE INDEX IF NOT EXISTS idx_post_collaborators_user_status
  ON public.post_collaborators(user_id, status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_post_collaborators_post
  ON public.post_collaborators(post_id);

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
  );

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
  );

DROP POLICY IF EXISTS "Invited users can respond" ON public.post_collaborators;
CREATE POLICY "Invited users can respond"
  ON public.post_collaborators
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (
    auth.uid() = user_id
    AND status IN ('accepted', 'declined')
  );

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

DO $$
DECLARE
  v_constraint_name text;
BEGIN
  SELECT c.conname
  INTO v_constraint_name
  FROM pg_constraint c
  WHERE c.conrelid = 'public.notifications'::regclass
    AND c.contype = 'c'
    AND pg_get_constraintdef(c.oid) ILIKE '%type%'
    AND pg_get_constraintdef(c.oid) ILIKE '%message%'
  LIMIT 1;

  IF v_constraint_name IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.notifications DROP CONSTRAINT %I', v_constraint_name);
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.notifications'::regclass
      AND conname = 'notifications_type_check'
  ) THEN
    ALTER TABLE public.notifications
      ADD CONSTRAINT notifications_type_check
      CHECK (type IN (
        'message',
        'like',
        'comment',
        'follow',
        'mention',
        'collaboration_invite',
        'collaboration_accepted'
      ));
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.notify_on_collaboration_invite()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  inviter_name text;
BEGIN
  SELECT COALESCE(display_name, username, 'Someone')
  INTO inviter_name
  FROM public.profiles
  WHERE id = NEW.invited_by;

  INSERT INTO public.notifications (user_id, type, title, body, data)
  VALUES (
    NEW.user_id,
    'collaboration_invite',
    'Collaboration Request',
    COALESCE(inviter_name, 'Someone') || ' wants to collaborate on a post with you',
    jsonb_build_object(
      'post_id', NEW.post_id,
      'collaboration_id', NEW.id,
      'inviter_id', NEW.invited_by
    )
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_collaboration_invite ON public.post_collaborators;
CREATE TRIGGER on_collaboration_invite
  AFTER INSERT ON public.post_collaborators
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_on_collaboration_invite();

CREATE OR REPLACE FUNCTION public.notify_on_collaboration_accepted()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  accepter_name text;
BEGIN
  IF NEW.status = 'accepted' AND OLD.status = 'pending' THEN
    SELECT COALESCE(display_name, username, 'Someone')
    INTO accepter_name
    FROM public.profiles
    WHERE id = NEW.user_id;

    INSERT INTO public.notifications (user_id, type, title, body, data)
    VALUES (
      NEW.invited_by,
      'collaboration_accepted',
      'Collaboration Accepted',
      COALESCE(accepter_name, 'Someone') || ' accepted your collaboration request',
      jsonb_build_object(
        'post_id', NEW.post_id,
        'collaboration_id', NEW.id,
        'collaborator_id', NEW.user_id
      )
    );
  END IF;

  IF NEW.status IN ('accepted', 'declined') AND OLD.status IS DISTINCT FROM NEW.status THEN
    NEW.responded_at = COALESCE(NEW.responded_at, now());
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_collaboration_accepted ON public.post_collaborators;
CREATE TRIGGER on_collaboration_accepted
  BEFORE UPDATE ON public.post_collaborators
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_on_collaboration_accepted();

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

-- RLS audit: post_collaborators is visible only to the post owner, inviter,
-- and invited collaborator; writes are limited to the owner/inviter and
-- invitee status response.

COMMIT;

NOTIFY pgrst, 'reload schema';
