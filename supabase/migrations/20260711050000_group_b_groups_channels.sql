BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

ALTER TABLE public.channels
  ADD COLUMN IF NOT EXISTS invite_code text UNIQUE DEFAULT encode(gen_random_bytes(8), 'hex'),
  ADD COLUMN IF NOT EXISTS linked_group_id uuid REFERENCES public.conversations(id),
  ADD COLUMN IF NOT EXISTS admin_permissions jsonb NOT NULL DEFAULT
    '{"post":true,"edit_info":true,"invite":true,"pin":true,"manage_members":true}'::jsonb,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS username text UNIQUE,
  ADD COLUMN IF NOT EXISTS invite_code text UNIQUE DEFAULT encode(gen_random_bytes(8), 'hex'),
  ADD COLUMN IF NOT EXISTS admin_permissions jsonb NOT NULL DEFAULT
    '{"post":true,"edit_info":true,"invite":true,"pin":true,"manage_members":true}'::jsonb;

CREATE INDEX IF NOT EXISTS idx_channels_invite_code ON public.channels(invite_code);
CREATE INDEX IF NOT EXISTS idx_channels_permissions ON public.channels USING gin(admin_permissions);
CREATE INDEX IF NOT EXISTS idx_conversations_username ON public.conversations(username);
CREATE INDEX IF NOT EXISTS idx_conversations_invite_code ON public.conversations(invite_code);

CREATE TABLE IF NOT EXISTS public.channel_invite_links (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  channel_id uuid NOT NULL REFERENCES public.channels(id) ON DELETE CASCADE,
  created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  code text UNIQUE NOT NULL DEFAULT encode(gen_random_bytes(6), 'hex'),
  max_uses integer,
  uses_count integer NOT NULL DEFAULT 0,
  expires_at timestamptz,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.channel_invite_links ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_channel_invite_links_channel_active
  ON public.channel_invite_links(channel_id, is_active, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_channel_invite_links_code
  ON public.channel_invite_links(code);

CREATE OR REPLACE FUNCTION public.is_channel_admin(_channel_id uuid, _user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.channel_members
    WHERE channel_id = _channel_id
      AND user_id = _user_id
      AND role IN ('owner', 'admin', 'moderator')
  )
$$;

CREATE OR REPLACE FUNCTION public.join_channel_by_invite(_code text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  link_row public.channel_invite_links%ROWTYPE;
BEGIN
  SELECT * INTO link_row
  FROM public.channel_invite_links
  WHERE code = _code
    AND is_active = true
    AND (expires_at IS NULL OR expires_at > now())
    AND (max_uses IS NULL OR uses_count < max_uses)
  LIMIT 1;

  IF link_row.id IS NULL THEN
    RAISE EXCEPTION 'Invite link is invalid or expired';
  END IF;

  INSERT INTO public.channel_members(channel_id, user_id, role)
  VALUES (link_row.channel_id, auth.uid(), 'member')
  ON CONFLICT (channel_id, user_id) DO NOTHING;

  UPDATE public.channel_invite_links
  SET uses_count = uses_count + 1
  WHERE id = link_row.id;

  RETURN link_row.channel_id;
END;
$$;

DROP POLICY IF EXISTS "Invite links viewable by admins" ON public.channel_invite_links;
CREATE POLICY "Invite links viewable by admins"
  ON public.channel_invite_links
  FOR SELECT
  USING (public.is_channel_admin(channel_id, auth.uid()));

DROP POLICY IF EXISTS "Admins can create invite links" ON public.channel_invite_links;
CREATE POLICY "Admins can create invite links"
  ON public.channel_invite_links
  FOR INSERT
  WITH CHECK (auth.uid() = created_by AND public.is_channel_admin(channel_id, auth.uid()));

DROP POLICY IF EXISTS "Admins can update invite links" ON public.channel_invite_links;
CREATE POLICY "Admins can update invite links"
  ON public.channel_invite_links
  FOR UPDATE
  USING (public.is_channel_admin(channel_id, auth.uid()))
  WITH CHECK (public.is_channel_admin(channel_id, auth.uid()));

DROP POLICY IF EXISTS "Admins can delete invite links" ON public.channel_invite_links;
CREATE POLICY "Admins can delete invite links"
  ON public.channel_invite_links
  FOR DELETE
  USING (public.is_channel_admin(channel_id, auth.uid()));

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'channels'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.channels;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'channel_members'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.channel_members;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'channel_invite_links'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.channel_invite_links;
  END IF;
END $$;

COMMENT ON TABLE public.channel_invite_links IS
  'RLS audit: invite links are visible and mutable only by channel admins; public joining uses join_channel_by_invite RPC.';

COMMIT;

NOTIFY pgrst, 'reload schema';
