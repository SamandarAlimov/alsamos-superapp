BEGIN;

-- Close the remaining production contract gaps found during call runtime audit.
-- This migration is additive/idempotent and safe to run after the earlier RTC
-- repair migrations.

CREATE OR REPLACE FUNCTION public._rtc_has_column(
  p_table text,
  p_column text
)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = p_table
      AND column_name = p_column
  );
$$;

DO $$
BEGIN
  IF to_regclass('public.call_invites') IS NOT NULL THEN
    IF public._rtc_has_column('call_invites', 'call_id')
       AND public._rtc_has_column('call_invites', 'invitee_id') THEN
      -- Older databases may already have duplicate fallback-created invite rows.
      -- Keep the newest row per call/invitee so PostgREST upsert can use the
      -- unique contract reliably.
      IF public._rtc_has_column('call_invites', 'created_at') THEN
        DELETE FROM public.call_invites old_invite
        USING public.call_invites keep_invite
        WHERE old_invite.call_id = keep_invite.call_id
          AND old_invite.invitee_id = keep_invite.invitee_id
          AND old_invite.id <> keep_invite.id
          AND (
            old_invite.created_at < keep_invite.created_at
            OR (
              old_invite.created_at = keep_invite.created_at
              AND old_invite.id::text < keep_invite.id::text
            )
          );
      ELSE
        DELETE FROM public.call_invites old_invite
        USING public.call_invites keep_invite
        WHERE old_invite.call_id = keep_invite.call_id
          AND old_invite.invitee_id = keep_invite.invitee_id
          AND old_invite.id::text < keep_invite.id::text;
      END IF;

      IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'public.call_invites'::regclass
          AND conname = 'call_invites_call_invitee_unique'
      ) THEN
        ALTER TABLE public.call_invites
          ADD CONSTRAINT call_invites_call_invitee_unique
          UNIQUE (call_id, invitee_id);
      END IF;
    END IF;
  END IF;
END $$;

DO $$
BEGIN
  IF to_regclass('public.call_webrtc_config') IS NOT NULL THEN
    EXECUTE 'ALTER TABLE public.call_webrtc_config ENABLE ROW LEVEL SECURITY';

    EXECUTE
      'DROP POLICY IF EXISTS "Authenticated users read call config" ON public.call_webrtc_config';
    EXECUTE
      'DROP POLICY IF EXISTS "RTC config readable by authenticated users" ON public.call_webrtc_config';
    EXECUTE
      'CREATE POLICY "RTC config readable by authenticated users"
         ON public.call_webrtc_config
         FOR SELECT
         TO authenticated
         USING (true)';

    EXECUTE 'GRANT SELECT ON TABLE public.call_webrtc_config TO authenticated';
  END IF;
END $$;

DO $$
BEGIN
  IF to_regclass('public.call_participants') IS NOT NULL THEN
    IF public._rtc_has_column('call_participants', 'call_id')
       AND public._rtc_has_column('call_participants', 'user_id')
       AND public._rtc_has_column('call_participants', 'id') THEN
      DELETE FROM public.call_participants old_participant
      USING public.call_participants keep_participant
      WHERE old_participant.call_id = keep_participant.call_id
        AND old_participant.user_id = keep_participant.user_id
        AND old_participant.id::text < keep_participant.id::text;
    END IF;

    IF public._rtc_has_column('call_participants', 'call_id')
       AND public._rtc_has_column('call_participants', 'user_id')
       AND NOT EXISTS (
         SELECT 1
         FROM pg_constraint
         WHERE conrelid = 'public.call_participants'::regclass
           AND conname = 'call_participants_call_user_unique'
       ) THEN
      ALTER TABLE public.call_participants
        ADD CONSTRAINT call_participants_call_user_unique
        UNIQUE (call_id, user_id);
    END IF;
  END IF;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';
