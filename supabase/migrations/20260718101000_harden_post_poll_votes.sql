BEGIN;

CREATE TABLE IF NOT EXISTS public.poll_votes (
  post_id uuid NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  option_id text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (post_id, user_id)
);

ALTER TABLE public.poll_votes
  ADD COLUMN IF NOT EXISTS post_id uuid,
  ADD COLUMN IF NOT EXISTS user_id uuid,
  ADD COLUMN IF NOT EXISTS option_id text,
  ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

CREATE INDEX IF NOT EXISTS idx_poll_votes_post ON public.poll_votes(post_id);
CREATE INDEX IF NOT EXISTS idx_poll_votes_user ON public.poll_votes(user_id);
CREATE INDEX IF NOT EXISTS idx_poll_votes_updated ON public.poll_votes(updated_at DESC);

CREATE OR REPLACE FUNCTION public.is_post_poll_expired(p_post_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_content text;
  v_poll_json text;
  v_expires_at timestamptz;
BEGIN
  SELECT content INTO v_content
  FROM public.posts
  WHERE id = p_post_id;

  IF v_content IS NULL OR position('[POLL]' in v_content) = 0 THEN
    RETURN false;
  END IF;

  v_poll_json := substring(v_content from '\[POLL\](.*?)\[/POLL\]');
  IF v_poll_json IS NULL OR trim(v_poll_json) = '' THEN
    RETURN false;
  END IF;

  BEGIN
    v_expires_at := (v_poll_json::jsonb ->> 'expiresAt')::timestamptz;
  EXCEPTION WHEN OTHERS THEN
    RETURN false;
  END;

  RETURN v_expires_at IS NOT NULL AND now() > v_expires_at;
END;
$$;

CREATE OR REPLACE FUNCTION public.enforce_post_poll_vote()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF public.is_post_poll_expired(NEW.post_id) THEN
    RAISE EXCEPTION 'poll_expired';
  END IF;

  NEW.updated_at := now();
  IF TG_OP = 'INSERT' THEN
    NEW.created_at := COALESCE(NEW.created_at, now());
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enforce_post_poll_vote_trigger ON public.poll_votes;
CREATE TRIGGER enforce_post_poll_vote_trigger
  BEFORE INSERT OR UPDATE ON public.poll_votes
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_post_poll_vote();

ALTER TABLE public.poll_votes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can read poll votes" ON public.poll_votes;
CREATE POLICY "Users can read poll votes"
  ON public.poll_votes
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.posts p
      WHERE p.id = poll_votes.post_id
        AND (p.visibility = 'public' OR p.user_id = auth.uid())
    )
  );

DROP POLICY IF EXISTS "Users can vote on polls" ON public.poll_votes;
CREATE POLICY "Users can vote on polls"
  ON public.poll_votes
  FOR INSERT
  TO authenticated
  WITH CHECK (
    auth.uid() = user_id
    AND NOT public.is_post_poll_expired(post_id)
    AND EXISTS (
      SELECT 1
      FROM public.posts p
      WHERE p.id = poll_votes.post_id
        AND (p.visibility = 'public' OR p.user_id = auth.uid())
    )
  );

DROP POLICY IF EXISTS "Users can change their vote" ON public.poll_votes;
CREATE POLICY "Users can change their vote"
  ON public.poll_votes
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (
    auth.uid() = user_id
    AND NOT public.is_post_poll_expired(post_id)
  );

DROP POLICY IF EXISTS "Users can delete their vote" ON public.poll_votes;
CREATE POLICY "Users can delete their vote"
  ON public.poll_votes
  FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'poll_votes'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.poll_votes;
  END IF;
END $$;

GRANT EXECUTE ON FUNCTION public.is_post_poll_expired(uuid) TO authenticated, anon;

-- RLS audit: poll_votes are readable only through readable parent posts, while
-- writes are limited to the authenticated user's own vote and blocked after
-- the poll expires.

COMMIT;

NOTIFY pgrst, 'reload schema';
