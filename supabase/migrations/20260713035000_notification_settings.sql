BEGIN;

ALTER TABLE public.user_settings
  ADD COLUMN IF NOT EXISTS notif_likes boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS notif_comments boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS notif_followers boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS notif_mentions boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS notif_messages boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS notif_sound text NOT NULL DEFAULT 'default',
  ADD COLUMN IF NOT EXISTS notif_vibration boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS notif_badge_count boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS dnd_start_time text,
  ADD COLUMN IF NOT EXISTS dnd_end_time text;

CREATE TABLE IF NOT EXISTS public.conversation_notification_settings (
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  muted_until timestamptz,
  mute_forever boolean NOT NULL DEFAULT false,
  mentions_only boolean NOT NULL DEFAULT false,
  preview_enabled boolean NOT NULL DEFAULT true,
  sound text NOT NULL DEFAULT 'default',
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, conversation_id)
);

ALTER TABLE public.conversation_notification_settings ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_conversation_notification_settings_conversation
  ON public.conversation_notification_settings(conversation_id, updated_at DESC);

DROP POLICY IF EXISTS "Users manage own conversation notification settings"
  ON public.conversation_notification_settings;
CREATE POLICY "Users manage own conversation notification settings"
  ON public.conversation_notification_settings
  FOR ALL
  USING (
    user_id = auth.uid()
    AND EXISTS (
      SELECT 1
      FROM public.conversation_participants cp
      WHERE cp.conversation_id = conversation_notification_settings.conversation_id
        AND cp.user_id = auth.uid()
    )
  )
  WITH CHECK (
    user_id = auth.uid()
    AND EXISTS (
      SELECT 1
      FROM public.conversation_participants cp
      WHERE cp.conversation_id = conversation_notification_settings.conversation_id
        AND cp.user_id = auth.uid()
    )
  );

CREATE OR REPLACE FUNCTION public.effective_conversation_notification_settings(
  p_conversation_id uuid,
  p_user_id uuid DEFAULT auth.uid()
)
RETURNS TABLE (
  muted_until timestamptz,
  mute_forever boolean,
  mentions_only boolean,
  preview_enabled boolean,
  sound text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    cns.muted_until,
    COALESCE(cns.mute_forever, false),
    COALESCE(cns.mentions_only, false),
    COALESCE(cns.preview_enabled, true),
    COALESCE(cns.sound, us.notif_sound, 'default')
  FROM public.conversation_participants cp
  LEFT JOIN public.conversation_notification_settings cns
    ON cns.conversation_id = cp.conversation_id
   AND cns.user_id = cp.user_id
  LEFT JOIN public.user_settings us ON us.user_id = cp.user_id
  WHERE cp.conversation_id = p_conversation_id
    AND cp.user_id = p_user_id;
$$;

GRANT EXECUTE ON FUNCTION public.effective_conversation_notification_settings(uuid, uuid)
  TO authenticated;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'conversation_notification_settings'
  ) THEN
    ALTER PUBLICATION supabase_realtime
      ADD TABLE public.conversation_notification_settings;
  END IF;
END $$;

COMMIT;
NOTIFY pgrst, 'reload schema';
