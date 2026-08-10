BEGIN;

ALTER TABLE public.user_sessions
  ADD COLUMN IF NOT EXISTS platform text,
  ADD COLUMN IF NOT EXISTS device_model text,
  ADD COLUMN IF NOT EXISTS os_version text,
  ADD COLUMN IF NOT EXISTS app_name text DEFAULT 'Alsamos',
  ADD COLUMN IF NOT EXISTS app_version text,
  ADD COLUMN IF NOT EXISTS location_city text,
  ADD COLUMN IF NOT EXISTS location_country text,
  ADD COLUMN IF NOT EXISTS accept_secret_chats boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS accept_incoming_calls boolean NOT NULL DEFAULT true;

ALTER TABLE public.user_settings
  ADD COLUMN IF NOT EXISTS session_autoterminate_days integer NOT NULL DEFAULT 180;

CREATE INDEX IF NOT EXISTS idx_user_sessions_user_active
  ON public.user_sessions(user_id, last_active_at DESC);

CREATE OR REPLACE FUNCTION public.terminate_old_user_sessions()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  deleted_count integer;
BEGIN
  DELETE FROM public.user_sessions s
  USING public.user_settings us
  WHERE us.user_id = s.user_id
    AND s.is_current IS NOT TRUE
    AND s.last_active_at < now() - make_interval(days => coalesce(us.session_autoterminate_days, 180));
  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.terminate_old_user_sessions() TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- RLS audit: user_sessions remains protected by existing owner-only policies; new metadata columns are writable only by the owning authenticated user.
