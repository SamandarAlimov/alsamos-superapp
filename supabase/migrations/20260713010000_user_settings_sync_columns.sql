-- Migration: Add chat background + font size sync columns to user_settings.
BEGIN;

ALTER TABLE public.user_settings
  ADD COLUMN IF NOT EXISTS chat_background TEXT,
  ADD COLUMN IF NOT EXISTS font_size TEXT DEFAULT 'medium',
  ADD COLUMN IF NOT EXISTS msg_text_size DOUBLE PRECISION DEFAULT 16.0;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- RLS audit: no new table; existing user_settings owner-only policies cover chat_background/font_size/msg_text_size.
