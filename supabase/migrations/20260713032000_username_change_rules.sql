BEGIN;

CREATE TABLE IF NOT EXISTS public.username_change_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  old_username text,
  new_username text NOT NULL,
  changed_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.username_change_history ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_username_change_history_user_changed
  ON public.username_change_history(user_id, changed_at DESC);

CREATE UNIQUE INDEX IF NOT EXISTS idx_profiles_username_lower_unique
  ON public.profiles (lower(username))
  WHERE username IS NOT NULL;

DROP POLICY IF EXISTS "Users view own username changes" ON public.username_change_history;
CREATE POLICY "Users view own username changes"
  ON public.username_change_history FOR SELECT
  USING (user_id = auth.uid());

CREATE OR REPLACE FUNCTION public.is_reserved_username(p_username text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT lower(trim(p_username)) = ANY (ARRAY[
    'admin','administrator','root','support','help','system','official',
    'alsamos','api','auth','login','signup','settings','profile','user',
    'channel','group','messages','market','payment','wallet','security'
  ]);
$$;

CREATE OR REPLACE FUNCTION public.is_username_available(
  p_username text,
  p_current_user_id uuid DEFAULT NULL
)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p_username ~ '^[a-z0-9_]{3,20}$'
    AND NOT public.is_reserved_username(p_username)
    AND NOT EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE lower(p.username) = lower(p_username)
        AND (p_current_user_id IS NULL OR p.id <> p_current_user_id)
    );
$$;

CREATE OR REPLACE FUNCTION public.change_username(p_username text)
RETURNS public.profiles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_username text := lower(trim(p_username));
  v_old text;
  v_profile public.profiles;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'auth required';
  END IF;
  IF NOT public.is_username_available(v_username, v_user_id) THEN
    RAISE EXCEPTION 'username unavailable';
  END IF;
  SELECT username INTO v_old FROM public.profiles WHERE id = v_user_id;
  IF lower(coalesce(v_old, '')) = v_username THEN
    SELECT * INTO v_profile FROM public.profiles WHERE id = v_user_id;
    RETURN v_profile;
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.username_change_history
    WHERE user_id = v_user_id
      AND changed_at > now() - interval '14 days'
  ) THEN
    RAISE EXCEPTION 'username can be changed once every 14 days';
  END IF;

  UPDATE public.profiles
  SET username = v_username,
      updated_at = now()
  WHERE id = v_user_id
  RETURNING * INTO v_profile;

  INSERT INTO public.username_change_history(user_id, old_username, new_username)
  VALUES (v_user_id, v_old, v_username);

  RETURN v_profile;
END;
$$;

GRANT EXECUTE ON FUNCTION public.is_username_available(text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.change_username(text) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- RLS audit: username history is owner-readable only; username changes execute through RPC as auth.uid() with uniqueness, reserved-name and cooldown checks.
