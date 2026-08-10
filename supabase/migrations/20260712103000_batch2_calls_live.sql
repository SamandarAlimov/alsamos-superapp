BEGIN;

CREATE TABLE IF NOT EXISTS public.call_webrtc_config (
  key text PRIMARY KEY,
  value jsonb NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.call_webrtc_config ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Authenticated users read call config" ON public.call_webrtc_config;
CREATE POLICY "Authenticated users read call config"
  ON public.call_webrtc_config FOR SELECT
  USING (auth.role() = 'authenticated');

ALTER TABLE public.call_participants
  ADD COLUMN IF NOT EXISTS connection_state text NOT NULL DEFAULT 'connecting',
  ADD COLUMN IF NOT EXISTS network_quality text,
  ADD COLUMN IF NOT EXISTS last_seen_at timestamptz,
  ADD COLUMN IF NOT EXISTS device_info jsonb,
  ADD COLUMN IF NOT EXISTS screen_share_track_id text;

CREATE INDEX IF NOT EXISTS idx_call_participants_call_state
  ON public.call_participants(call_id, connection_state, last_seen_at DESC);

CREATE TABLE IF NOT EXISTS public.call_quality_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  call_id uuid NOT NULL REFERENCES public.video_calls(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  rtt_ms integer NOT NULL DEFAULT 0,
  jitter_ms integer NOT NULL DEFAULT 0,
  packet_loss numeric NOT NULL DEFAULT 0,
  quality text NOT NULL DEFAULT 'disconnected',
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.call_quality_reports ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_call_quality_reports_call_created
  ON public.call_quality_reports(call_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_call_quality_reports_user_created
  ON public.call_quality_reports(user_id, created_at DESC);
DROP POLICY IF EXISTS "Call participants view quality reports" ON public.call_quality_reports;
CREATE POLICY "Call participants view quality reports"
  ON public.call_quality_reports FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.call_participants cp
      WHERE cp.call_id = call_quality_reports.call_id
        AND cp.user_id = auth.uid()
    )
  );
DROP POLICY IF EXISTS "Users write own quality reports" ON public.call_quality_reports;
CREATE POLICY "Users write own quality reports"
  ON public.call_quality_reports FOR INSERT
  WITH CHECK (
    user_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.call_participants cp
      WHERE cp.call_id = call_quality_reports.call_id
        AND cp.user_id = auth.uid()
    )
  );

CREATE TABLE IF NOT EXISTS public.call_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  call_id uuid NOT NULL REFERENCES public.video_calls(id) ON DELETE CASCADE,
  user_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  event_type text NOT NULL,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.call_events ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_call_events_call_created
  ON public.call_events(call_id, created_at DESC);
DROP POLICY IF EXISTS "Call participants view call events" ON public.call_events;
CREATE POLICY "Call participants view call events"
  ON public.call_events FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.call_participants cp
      WHERE cp.call_id = call_events.call_id
        AND cp.user_id = auth.uid()
    )
  );
DROP POLICY IF EXISTS "Call participants write own events" ON public.call_events;
CREATE POLICY "Call participants write own events"
  ON public.call_events FOR INSERT
  WITH CHECK (
    user_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.call_participants cp
      WHERE cp.call_id = call_events.call_id
        AND cp.user_id = auth.uid()
    )
  );

ALTER TABLE public.live_stream_viewers
  ADD COLUMN IF NOT EXISTS last_seen_at timestamptz NOT NULL DEFAULT now();
CREATE INDEX IF NOT EXISTS idx_live_stream_viewers_last_seen
  ON public.live_stream_viewers(stream_id, last_seen_at DESC);

CREATE TABLE IF NOT EXISTS public.live_stream_moderation_actions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  stream_id uuid NOT NULL REFERENCES public.live_streams(id) ON DELETE CASCADE,
  moderator_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  target_user_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  action_type text NOT NULL,
  reason text,
  expires_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.live_stream_moderation_actions ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_live_stream_mod_actions_stream
  ON public.live_stream_moderation_actions(stream_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_live_stream_mod_actions_target
  ON public.live_stream_moderation_actions(target_user_id, created_at DESC);

CREATE OR REPLACE FUNCTION public.can_moderate_live_stream(p_stream_id uuid, p_user_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.live_streams ls
    WHERE ls.id = p_stream_id
      AND ls.user_id = p_user_id
  );
$$;

DROP POLICY IF EXISTS "Live moderators write moderation actions" ON public.live_stream_moderation_actions;
CREATE POLICY "Live moderators write moderation actions"
  ON public.live_stream_moderation_actions FOR INSERT
  WITH CHECK (public.can_moderate_live_stream(stream_id, auth.uid()));
DROP POLICY IF EXISTS "Live participants view relevant moderation actions" ON public.live_stream_moderation_actions;
CREATE POLICY "Live participants view relevant moderation actions"
  ON public.live_stream_moderation_actions FOR SELECT
  USING (
    public.can_moderate_live_stream(stream_id, auth.uid())
    OR target_user_id = auth.uid()
  );

CREATE TABLE IF NOT EXISTS public.live_stream_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  stream_id uuid NOT NULL REFERENCES public.live_streams(id) ON DELETE CASCADE,
  reporter_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  target_user_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  reason text NOT NULL,
  status text NOT NULL DEFAULT 'open',
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.live_stream_reports ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_live_stream_reports_stream_status
  ON public.live_stream_reports(stream_id, status, created_at DESC);
DROP POLICY IF EXISTS "Users create own live reports" ON public.live_stream_reports;
CREATE POLICY "Users create own live reports"
  ON public.live_stream_reports FOR INSERT
  WITH CHECK (reporter_id = auth.uid());
DROP POLICY IF EXISTS "Moderators view live reports" ON public.live_stream_reports;
CREATE POLICY "Moderators view live reports"
  ON public.live_stream_reports FOR SELECT
  USING (public.can_moderate_live_stream(stream_id, auth.uid()));

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'call_quality_reports'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.call_quality_reports;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'call_events'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.call_events;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'live_stream_moderation_actions'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.live_stream_moderation_actions;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'live_stream_reports'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.live_stream_reports;
  END IF;
END $$;

COMMIT;
NOTIFY pgrst, 'reload schema';
