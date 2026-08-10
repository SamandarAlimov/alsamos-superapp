BEGIN;

ALTER TABLE public.user_settings
  ADD COLUMN IF NOT EXISTS phone_visibility text NOT NULL DEFAULT 'contacts',
  ADD COLUMN IF NOT EXISTS profile_photo_visibility text NOT NULL DEFAULT 'everyone',
  ADD COLUMN IF NOT EXISTS forwards_visibility text NOT NULL DEFAULT 'everyone',
  ADD COLUMN IF NOT EXISTS private_account boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION public.can_view_profile_field(
  target_user_id uuid,
  field_name text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  visibility text;
BEGIN
  IF auth.uid() IS NULL THEN RETURN false; END IF;
  IF auth.uid() = target_user_id THEN RETURN true; END IF;
  IF public.is_blocked_between(auth.uid(), target_user_id) THEN RETURN false; END IF;

  SELECT CASE field_name
    WHEN 'phone' THEN coalesce(phone_visibility, 'contacts')
    WHEN 'photo' THEN coalesce(profile_photo_visibility, 'everyone')
    WHEN 'forwards' THEN coalesce(forwards_visibility, 'everyone')
    WHEN 'calls' THEN coalesce(call_permissions, 'everyone')
    WHEN 'group_invites' THEN coalesce(group_invite_permissions, 'everyone')
    ELSE 'nobody'
  END INTO visibility
  FROM public.user_settings
  WHERE user_id = target_user_id;

  visibility := coalesce(visibility, 'everyone');
  IF visibility = 'nobody' THEN RETURN false; END IF;
  IF visibility = 'contacts' THEN RETURN public.are_contacts(auth.uid(), target_user_id); END IF;
  RETURN true;
END;
$$;

GRANT EXECUTE ON FUNCTION public.can_view_profile_field(uuid, text) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- RLS audit: privacy values remain owner-only in user_settings; cross-user checks are exposed only via can_view_profile_field RPC.
