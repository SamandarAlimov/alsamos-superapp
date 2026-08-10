BEGIN;

ALTER TABLE public.user_settings
  ADD COLUMN IF NOT EXISTS app_theme_mode text NOT NULL DEFAULT 'system';

CREATE INDEX IF NOT EXISTS idx_user_settings_theme_mode
  ON public.user_settings(user_id, app_theme_mode);

-- RLS audit: app_theme_mode is stored on user_settings and remains protected by existing per-user user_settings RLS policies.
NOTIFY pgrst, 'reload schema';

COMMIT;
