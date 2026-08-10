BEGIN;

ALTER TABLE public.user_settings
  ADD COLUMN IF NOT EXISTS show_deleted_messages boolean NOT NULL DEFAULT false;

COMMIT;
NOTIFY pgrst, 'reload schema';
