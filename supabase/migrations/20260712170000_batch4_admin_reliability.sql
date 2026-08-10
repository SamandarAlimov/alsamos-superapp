-- Migration: Messaging moderation + analytics (ROBUST — handles pre-existing tables + fixes 42P13)
BEGIN;

-- Fix 42P13: drop functions whose parameter defaults changed, so recreation can't conflict.
-- (is_conversation_admin and can_send_message_to_conversation are used by RLS policies, so they
--  are intentionally NOT dropped — CREATE OR REPLACE below is safe for them.)
DROP FUNCTION IF EXISTS public.is_conversation_restricted(uuid, uuid, text);
DROP FUNCTION IF EXISTS public.check_rate_limit(text, text, integer, integer);
DROP FUNCTION IF EXISTS public.log_admin_action(uuid, text, uuid, jsonb);
DROP FUNCTION IF EXISTS public.create_message_report(uuid, uuid, text, text);
DROP FUNCTION IF EXISTS public.conversation_stats(uuid);

-- Core tables (verified: columns already exist / safe to add)
ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS slow_mode_seconds integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS stats_enabled boolean NOT NULL DEFAULT true;

ALTER TABLE public.conversation_participants
  ADD COLUMN IF NOT EXISTS role text NOT NULL DEFAULT 'member',
  ADD COLUMN IF NOT EXISTS joined_at timestamptz NOT NULL DEFAULT now();

ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS view_count integer NOT NULL DEFAULT 0;

-- conversation_admin_actions
CREATE TABLE IF NOT EXISTS public.conversation_admin_actions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  actor_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  target_user_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  action text NOT NULL,
  details jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.conversation_admin_actions
  ADD COLUMN IF NOT EXISTS conversation_id uuid,
  ADD COLUMN IF NOT EXISTS actor_id uuid,
  ADD COLUMN IF NOT EXISTS target_user_id uuid,
  ADD COLUMN IF NOT EXISTS action text,
  ADD COLUMN IF NOT EXISTS details jsonb DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now();
ALTER TABLE public.conversation_admin_actions ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_admin_actions_conversation_created
  ON public.conversation_admin_actions(conversation_id, created_at DESC);

-- conversation_restrictions
CREATE TABLE IF NOT EXISTS public.conversation_restrictions (
  conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  kind text NOT NULL CHECK (kind IN ('ban','restrict','mute')),
  reason text,
  until_at timestamptz,
  created_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (conversation_id, user_id, kind)
);
ALTER TABLE public.conversation_restrictions
  ADD COLUMN IF NOT EXISTS conversation_id uuid,
  ADD COLUMN IF NOT EXISTS user_id uuid,
  ADD COLUMN IF NOT EXISTS kind text,
  ADD COLUMN IF NOT EXISTS reason text,
  ADD COLUMN IF NOT EXISTS until_at timestamptz,
  ADD COLUMN IF NOT EXISTS created_by uuid,
  ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now(),
  ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();
ALTER TABLE public.conversation_restrictions ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_conversation_restrictions_user
  ON public.conversation_restrictions(user_id, updated_at DESC);

-- message_reports
CREATE TABLE IF NOT EXISTS public.message_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  message_id uuid REFERENCES public.messages(id) ON DELETE SET NULL,
  reporter_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  reason text NOT NULL,
  details text,
  status text NOT NULL DEFAULT 'open',
  resolved_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  resolved_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (message_id, reporter_id)
);
ALTER TABLE public.message_reports
  ADD COLUMN IF NOT EXISTS conversation_id uuid,
  ADD COLUMN IF NOT EXISTS message_id uuid,
  ADD COLUMN IF NOT EXISTS reporter_id uuid,
  ADD COLUMN IF NOT EXISTS reason text,
  ADD COLUMN IF NOT EXISTS details text,
  ADD COLUMN IF NOT EXISTS status text DEFAULT 'open',
  ADD COLUMN IF NOT EXISTS resolved_by uuid,
  ADD COLUMN IF NOT EXISTS resolved_at timestamptz,
  ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now();
ALTER TABLE public.message_reports ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_message_reports_conversation_status
  ON public.message_reports(conversation_id, status, created_at DESC);

-- app_analytics_events
CREATE TABLE IF NOT EXISTS public.app_analytics_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  event_name text NOT NULL,
  properties jsonb NOT NULL DEFAULT '{}'::jsonb,
  platform text,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.app_analytics_events
  ADD COLUMN IF NOT EXISTS user_id uuid,
  ADD COLUMN IF NOT EXISTS event_name text,
  ADD COLUMN IF NOT EXISTS properties jsonb DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS platform text,
  ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now();
ALTER TABLE public.app_analytics_events ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_app_analytics_user_created
  ON public.app_analytics_events(user_id, created_at DESC);

-- crash_logs
CREATE TABLE IF NOT EXISTS public.crash_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  context text,
  error text NOT NULL,
  stack text,
  platform text,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.crash_logs
  ADD COLUMN IF NOT EXISTS user_id uuid,
  ADD COLUMN IF NOT EXISTS context text,
  ADD COLUMN IF NOT EXISTS error text,
  ADD COLUMN IF NOT EXISTS stack text,
  ADD COLUMN IF NOT EXISTS platform text,
  ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now();
ALTER TABLE public.crash_logs ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_crash_logs_created ON public.crash_logs(created_at DESC);

-- rate_limit_events
CREATE TABLE IF NOT EXISTS public.rate_limit_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
  scope text NOT NULL,
  key text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.rate_limit_events
  ADD COLUMN IF NOT EXISTS user_id uuid,
  ADD COLUMN IF NOT EXISTS scope text,
  ADD COLUMN IF NOT EXISTS key text,
  ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now();
ALTER TABLE public.rate_limit_events ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_rate_limit_events_scope_key_created
  ON public.rate_limit_events(scope, key, created_at DESC);

-- user_data_exports
CREATE TABLE IF NOT EXISTS public.user_data_exports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'ready',
  manifest jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL DEFAULT (now() + interval '7 days')
);
ALTER TABLE public.user_data_exports
  ADD COLUMN IF NOT EXISTS user_id uuid,
  ADD COLUMN IF NOT EXISTS status text DEFAULT 'ready',
  ADD COLUMN IF NOT EXISTS manifest jsonb DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now(),
  ADD COLUMN IF NOT EXISTS expires_at timestamptz DEFAULT (now() + interval '7 days');
ALTER TABLE public.user_data_exports ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_user_data_exports_user_created
  ON public.user_data_exports(user_id, created_at DESC);

-- call_room_members
CREATE TABLE IF NOT EXISTS public.call_room_members (
  call_id uuid NOT NULL,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  role text NOT NULL DEFAULT 'participant',
  connection_state text NOT NULL DEFAULT 'connecting',
  media_state jsonb NOT NULL DEFAULT '{}'::jsonb,
  joined_at timestamptz NOT NULL DEFAULT now(),
  left_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (call_id, user_id)
);
ALTER TABLE public.call_room_members
  ADD COLUMN IF NOT EXISTS call_id uuid,
  ADD COLUMN IF NOT EXISTS user_id uuid,
  ADD COLUMN IF NOT EXISTS role text DEFAULT 'participant',
  ADD COLUMN IF NOT EXISTS connection_state text DEFAULT 'connecting',
  ADD COLUMN IF NOT EXISTS media_state jsonb DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS joined_at timestamptz DEFAULT now(),
  ADD COLUMN IF NOT EXISTS left_at timestamptz,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();
ALTER TABLE public.call_room_members ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_call_room_members_call
  ON public.call_room_members(call_id, updated_at DESC);

-- Functions (columns they read are now guaranteed to exist)
CREATE OR REPLACE FUNCTION public.is_conversation_admin(p_conversation_id uuid, p_user_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.conversation_participants
    WHERE conversation_id = p_conversation_id AND user_id = p_user_id
      AND COALESCE(role, 'member') IN ('owner','admin','moderator')
  );
$$;

CREATE OR REPLACE FUNCTION public.is_conversation_restricted(p_conversation_id uuid, p_user_id uuid, p_kind text)
RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.conversation_restrictions
    WHERE conversation_id = p_conversation_id AND user_id = p_user_id AND kind = p_kind
      AND (until_at IS NULL OR until_at > now())
  );
$$;

CREATE OR REPLACE FUNCTION public.check_rate_limit(p_scope text, p_key text, p_limit integer, p_window_seconds integer)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_count integer;
BEGIN
  DELETE FROM public.rate_limit_events
  WHERE created_at < now() - make_interval(secs => greatest(p_window_seconds, 1));
  SELECT count(*) INTO v_count FROM public.rate_limit_events
  WHERE scope = p_scope AND key = p_key
    AND created_at >= now() - make_interval(secs => greatest(p_window_seconds, 1));
  IF v_count >= p_limit THEN RETURN false; END IF;
  INSERT INTO public.rate_limit_events(user_id, scope, key) VALUES (auth.uid(), p_scope, p_key);
  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.can_send_message_to_conversation(p_conversation_id uuid, p_sender_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_slow integer := 0; v_last_sent timestamptz;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.conversation_participants
    WHERE conversation_id = p_conversation_id AND user_id = p_sender_id) THEN RETURN false; END IF;
  IF public.is_conversation_restricted(p_conversation_id, p_sender_id, 'ban')
     OR public.is_conversation_restricted(p_conversation_id, p_sender_id, 'restrict') THEN RETURN false; END IF;
  IF EXISTS (SELECT 1 FROM public.conversation_participants cp
    WHERE cp.conversation_id = p_conversation_id AND cp.user_id <> p_sender_id
      AND public.is_blocked_between(cp.user_id, p_sender_id)) THEN RETURN false; END IF;
  SELECT COALESCE(slow_mode_seconds, 0) INTO v_slow FROM public.conversations WHERE id = p_conversation_id;
  IF COALESCE(v_slow, 0) > 0 AND NOT public.is_conversation_admin(p_conversation_id, p_sender_id) THEN
    SELECT max(created_at) INTO v_last_sent FROM public.messages
    WHERE conversation_id = p_conversation_id AND sender_id = p_sender_id;
    IF v_last_sent IS NOT NULL AND v_last_sent > now() - make_interval(secs => v_slow) THEN RETURN false; END IF;
  END IF;
  RETURN public.check_rate_limit('message_send', p_sender_id::text || ':' || p_conversation_id::text, 40, 60);
END;
$$;

CREATE OR REPLACE FUNCTION public.log_admin_action(p_conversation_id uuid, p_action text, p_target_user_id uuid DEFAULT NULL, p_details jsonb DEFAULT '{}'::jsonb)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id uuid;
BEGIN
  IF NOT public.is_conversation_admin(p_conversation_id, auth.uid()) THEN RAISE EXCEPTION 'not_admin'; END IF;
  INSERT INTO public.conversation_admin_actions(conversation_id, actor_id, target_user_id, action, details)
  VALUES (p_conversation_id, auth.uid(), p_target_user_id, p_action, COALESCE(p_details, '{}'::jsonb))
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_message_report(p_conversation_id uuid, p_message_id uuid, p_reason text, p_details text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id uuid;
BEGIN
  IF NOT public.check_rate_limit('message_report', auth.uid()::text, 10, 3600) THEN RAISE EXCEPTION 'rate_limited'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.conversation_participants
    WHERE conversation_id = p_conversation_id AND user_id = auth.uid()) THEN RAISE EXCEPTION 'not_participant'; END IF;
  INSERT INTO public.message_reports(conversation_id, message_id, reporter_id, reason, details)
  VALUES (p_conversation_id, p_message_id, auth.uid(), p_reason, p_details)
  ON CONFLICT (message_id, reporter_id)
  DO UPDATE SET reason = EXCLUDED.reason, details = EXCLUDED.details, status = 'open'
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.conversation_stats(p_conversation_id uuid)
RETURNS TABLE(members integer, messages integer, views integer, reports integer, growth_7d integer)
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT
    (SELECT count(*)::integer FROM public.conversation_participants WHERE conversation_id = p_conversation_id),
    (SELECT count(*)::integer FROM public.messages WHERE conversation_id = p_conversation_id AND COALESCE(is_deleted, false) = false),
    (SELECT COALESCE(sum(view_count), 0)::integer FROM public.messages WHERE conversation_id = p_conversation_id),
    (SELECT count(*)::integer FROM public.message_reports WHERE conversation_id = p_conversation_id AND status = 'open'),
    (SELECT count(*)::integer FROM public.conversation_participants WHERE conversation_id = p_conversation_id AND joined_at >= now() - interval '7 days');
$$;

-- Policies
DROP POLICY IF EXISTS "Admins read admin actions" ON public.conversation_admin_actions;
CREATE POLICY "Admins read admin actions" ON public.conversation_admin_actions
  FOR SELECT USING (public.is_conversation_admin(conversation_id, auth.uid()));

DROP POLICY IF EXISTS "Admins create admin actions" ON public.conversation_admin_actions;
CREATE POLICY "Admins create admin actions" ON public.conversation_admin_actions
  FOR INSERT WITH CHECK (public.is_conversation_admin(conversation_id, auth.uid()) AND actor_id = auth.uid());

DROP POLICY IF EXISTS "Admins manage restrictions" ON public.conversation_restrictions;
CREATE POLICY "Admins manage restrictions" ON public.conversation_restrictions
  FOR ALL USING (public.is_conversation_admin(conversation_id, auth.uid()))
  WITH CHECK (public.is_conversation_admin(conversation_id, auth.uid()));

DROP POLICY IF EXISTS "Participants create own reports" ON public.message_reports;
CREATE POLICY "Participants create own reports" ON public.message_reports
  FOR INSERT WITH CHECK (reporter_id = auth.uid());

DROP POLICY IF EXISTS "Reporter or admins read reports" ON public.message_reports;
CREATE POLICY "Reporter or admins read reports" ON public.message_reports
  FOR SELECT USING (reporter_id = auth.uid() OR public.is_conversation_admin(conversation_id, auth.uid()));

DROP POLICY IF EXISTS "Admins update reports" ON public.message_reports;
CREATE POLICY "Admins update reports" ON public.message_reports
  FOR UPDATE USING (public.is_conversation_admin(conversation_id, auth.uid()))
  WITH CHECK (public.is_conversation_admin(conversation_id, auth.uid()));

DROP POLICY IF EXISTS "Users insert own analytics" ON public.app_analytics_events;
CREATE POLICY "Users insert own analytics" ON public.app_analytics_events
  FOR INSERT WITH CHECK (user_id IS NULL OR user_id = auth.uid());

DROP POLICY IF EXISTS "Users insert own crash logs" ON public.crash_logs;
CREATE POLICY "Users insert own crash logs" ON public.crash_logs
  FOR INSERT WITH CHECK (user_id IS NULL OR user_id = auth.uid());

DROP POLICY IF EXISTS "Users read own exports" ON public.user_data_exports;
CREATE POLICY "Users read own exports" ON public.user_data_exports
  FOR SELECT USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Users create own exports" ON public.user_data_exports;
CREATE POLICY "Users create own exports" ON public.user_data_exports
  FOR INSERT WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Users write own call room member state" ON public.call_room_members;
CREATE POLICY "Users write own call room member state" ON public.call_room_members
  FOR ALL USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Call participants read room members" ON public.call_room_members;
CREATE POLICY "Call participants read room members" ON public.call_room_members
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.call_room_members crm
      WHERE crm.call_id = call_room_members.call_id AND crm.user_id = auth.uid())
  );

-- Realtime publication
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['conversation_admin_actions','conversation_restrictions','message_reports','call_room_members'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = t) THEN
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', t);
    END IF;
  END LOOP;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';