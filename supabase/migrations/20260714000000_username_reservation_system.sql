BEGIN;

CREATE EXTENSION IF NOT EXISTS citext WITH SCHEMA public;

-- ============================================================
-- 1. reserved_usernames table
-- ============================================================
CREATE TABLE IF NOT EXISTS public.reserved_usernames (
  username citext PRIMARY KEY,
  category text NOT NULL CHECK (category IN ('celebrity','brand','short','system','custom')),
  reason text,
  reserved_by uuid REFERENCES public.profiles(id),
  reserved_at timestamptz NOT NULL DEFAULT now(),
  released_to uuid REFERENCES public.profiles(id),
  released_by uuid REFERENCES public.profiles(id),
  released_at timestamptz
);

ALTER TABLE public.reserved_usernames ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can read reserved usernames" ON public.reserved_usernames;
CREATE POLICY "Anyone can read reserved usernames"
  ON public.reserved_usernames FOR SELECT
  USING (true);

DROP POLICY IF EXISTS "Admins can insert reserved usernames" ON public.reserved_usernames;
CREATE POLICY "Admins can insert reserved usernames"
  ON public.reserved_usernames FOR INSERT
  WITH CHECK (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_admin = true));

DROP POLICY IF EXISTS "Admins can update reserved usernames" ON public.reserved_usernames;
CREATE POLICY "Admins can update reserved usernames"
  ON public.reserved_usernames FOR UPDATE
  USING (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_admin = true));

DROP POLICY IF EXISTS "Admins can delete reserved usernames" ON public.reserved_usernames;
CREATE POLICY "Admins can delete reserved usernames"
  ON public.reserved_usernames FOR DELETE
  USING (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_admin = true));

-- ============================================================
-- 2. username_rules config table (single row)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.username_rules (
  id boolean PRIMARY KEY DEFAULT true,
  reserved_max_short_length int NOT NULL DEFAULT 4,
  min_username_length int NOT NULL DEFAULT 3,
  max_username_length int NOT NULL DEFAULT 32,
  allowed_pattern text NOT NULL DEFAULT '^[a-z0-9_]+$',
  CHECK (id)
);

INSERT INTO public.username_rules (id) VALUES (true) ON CONFLICT (id) DO NOTHING;

ALTER TABLE public.username_rules ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can read username rules" ON public.username_rules;
CREATE POLICY "Anyone can read username rules"
  ON public.username_rules FOR SELECT
  USING (true);

-- ============================================================
-- 3. check_username_availability — returns JSON with reason
-- ============================================================
CREATE OR REPLACE FUNCTION public.check_username_availability(
  p_username text,
  p_user_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_normalized text := lower(trim(p_username));
  v_rules public.username_rules;
  v_reserved public.reserved_usernames;
  v_count int;
BEGIN
  IF v_normalized = '' THEN
    RETURN jsonb_build_object('available', false, 'reason', 'empty');
  END IF;

  SELECT * INTO v_rules FROM public.username_rules WHERE id = true;

  IF length(v_normalized) < v_rules.min_username_length THEN
    RETURN jsonb_build_object('available', false, 'reason', 'too_short');
  END IF;

  IF length(v_normalized) > v_rules.max_username_length THEN
    RETURN jsonb_build_object('available', false, 'reason', 'too_long');
  END IF;

  IF NOT v_normalized ~ v_rules.allowed_pattern THEN
    RETURN jsonb_build_object('available', false, 'reason', 'invalid');
  END IF;

  SELECT count(*) INTO v_count FROM public.profiles p
  WHERE lower(p.username) = v_normalized
    AND (p_user_id IS NULL OR p.id <> p_user_id);

  IF v_count > 0 THEN
    RETURN jsonb_build_object('available', false, 'reason', 'taken');
  END IF;

  SELECT * INTO v_reserved FROM public.reserved_usernames
  WHERE username = v_normalized;

  IF FOUND THEN
    IF v_reserved.released_to IS NOT NULL AND v_reserved.released_to = p_user_id THEN
      RETURN jsonb_build_object('available', true, 'reason', 'ok');
    END IF;

    RETURN jsonb_build_object(
      'available', false,
      'reason', CASE v_reserved.category
        WHEN 'celebrity' THEN 'reserved_celebrity'
        WHEN 'brand' THEN 'reserved_brand'
        WHEN 'short' THEN 'reserved_short'
        WHEN 'system' THEN 'reserved_system'
        ELSE 'reserved'
      END,
      'category', v_reserved.category
    );
  END IF;

  IF length(v_normalized) <= v_rules.reserved_max_short_length THEN
    RETURN jsonb_build_object('available', false, 'reason', 'reserved_short');
  END IF;

  RETURN jsonb_build_object('available', true, 'reason', 'ok');
END;
$$;

-- ============================================================
-- 4. Updated is_reserved_username — queries table instead of hardcoded array
-- ============================================================
DROP FUNCTION IF EXISTS public.is_reserved_username(text);

CREATE OR REPLACE FUNCTION public.is_reserved_username(p_username text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.reserved_usernames
    WHERE username = lower(trim(p_username))
  );
$$;

-- ============================================================
-- 5. Updated is_username_available — delegates to check_username_availability
-- ============================================================
CREATE OR REPLACE FUNCTION public.is_username_available(
  p_username text,
  p_current_user_id uuid DEFAULT NULL
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (public.check_username_availability(p_username, p_current_user_id)->>'available')::boolean,
    false
  );
$$;

-- ============================================================
-- 6. Updated change_username — better error messages
-- ============================================================
CREATE OR REPLACE FUNCTION public.change_username(p_username text)
RETURNS public.profiles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_username text := lower(trim(p_username));
  v_old text;
  v_profile public.profiles;
  v_check jsonb;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'auth required';
  END IF;

  v_check := public.check_username_availability(v_username, v_user_id);

  IF NOT COALESCE((v_check->>'available')::boolean, false) THEN
    RAISE EXCEPTION 'username_unavailable: %', v_check->>'reason';
  END IF;

  SELECT username INTO v_old FROM public.profiles WHERE id = v_user_id;
  IF lower(coalesce(v_old, '')) = v_username THEN
    SELECT * INTO v_profile FROM public.profiles WHERE id = v_user_id;
    RETURN v_profile;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.username_change_history
    WHERE user_id = v_user_id
      AND changed_at > now() - interval '14 days'
  ) THEN
    RAISE EXCEPTION 'username_cooldown';
  END IF;

  UPDATE public.profiles
  SET username = v_username,
      updated_at = now()
  WHERE id = v_user_id
  RETURNING * INTO v_profile;

  INSERT INTO public.username_change_history(user_id, old_username, new_username)
  VALUES (v_user_id, v_old, v_username);

  RETURN v_profile;
END;
$$;

-- ============================================================
-- 7. Trigger — enforce reservation on profiles INSERT/UPDATE
-- ============================================================
CREATE OR REPLACE FUNCTION public.enforce_username_reservation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_check jsonb;
  v_is_admin boolean;
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.username IS NOT DISTINCT FROM OLD.username THEN
    RETURN NEW;
  END IF;

  IF NEW.username IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT is_admin INTO v_is_admin FROM public.profiles WHERE id = auth.uid();
  IF COALESCE(v_is_admin, false) THEN
    RETURN NEW;
  END IF;

  v_check := public.check_username_availability(NEW.username, NEW.id);

  IF NOT COALESCE((v_check->>'available')::boolean, false) THEN
    RAISE EXCEPTION 'username_reserved: %', v_check->>'reason';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enforce_username_reservation_trigger ON public.profiles;
CREATE TRIGGER enforce_username_reservation_trigger
  BEFORE INSERT OR UPDATE OF username
  ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_username_reservation();

-- ============================================================
-- 8. Admin functions
-- ============================================================

-- admin_reserve_username
CREATE OR REPLACE FUNCTION public.admin_reserve_username(
  p_username text,
  p_category text,
  p_reason text DEFAULT NULL
)
RETURNS public.reserved_usernames
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_reserved public.reserved_usernames;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_admin = true) THEN
    RAISE EXCEPTION 'not_admin';
  END IF;

  INSERT INTO public.reserved_usernames (username, category, reason, reserved_by)
  VALUES (lower(trim(p_username)), p_category, p_reason, auth.uid())
  ON CONFLICT (username) DO UPDATE SET
    category = EXCLUDED.category,
    reason = COALESCE(p_reason, public.reserved_usernames.reason),
    reserved_by = auth.uid(),
    reserved_at = now(),
    released_to = NULL,
    released_by = NULL,
    released_at = NULL
  RETURNING * INTO v_reserved;

  RETURN v_reserved;
END;
$$;

-- admin_bulk_reserve (drop first for safe idempotent recreate)
DROP FUNCTION IF EXISTS public.admin_bulk_reserve(text[], text, text);

CREATE OR REPLACE FUNCTION public.admin_bulk_reserve(
  p_usernames text[],
  p_category text,
  p_reason text DEFAULT NULL
)
RETURNS TABLE(inserted int, skipped int)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_username text;
  v_inserted int := 0;
  v_skipped int := 0;
  v_is_admin boolean;
BEGIN
  SELECT is_admin INTO v_is_admin FROM public.profiles WHERE id = auth.uid();
  IF NOT COALESCE(v_is_admin, false) THEN
    RAISE EXCEPTION 'not_admin';
  END IF;

  FOREACH v_username IN ARRAY p_usernames
  LOOP
    BEGIN
      INSERT INTO public.reserved_usernames (username, category, reason, reserved_by)
      VALUES (lower(trim(v_username)), p_category, p_reason, auth.uid())
      ON CONFLICT (username) DO NOTHING;

      IF FOUND THEN
        v_inserted := v_inserted + 1;
      ELSE
        v_skipped := v_skipped + 1;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      v_skipped := v_skipped + 1;
    END;
  END LOOP;

  RETURN QUERY SELECT v_inserted, v_skipped;
END;
$$;

-- admin_release_username_to_user
CREATE OR REPLACE FUNCTION public.admin_release_username_to_user(
  p_username text,
  p_target_user_id uuid
)
RETURNS public.reserved_usernames
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_reserved public.reserved_usernames;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_admin = true) THEN
    RAISE EXCEPTION 'not_admin';
  END IF;

  UPDATE public.reserved_usernames
  SET released_to = p_target_user_id,
      released_by = auth.uid(),
      released_at = now()
  WHERE username = lower(trim(p_username))
  RETURNING * INTO v_reserved;

  IF NOT FOUND THEN
    INSERT INTO public.reserved_usernames (username, category, reason, reserved_by, released_to, released_by, released_at)
    VALUES (lower(trim(p_username)), 'custom', 'Released to specific user', auth.uid(), p_target_user_id, auth.uid(), now())
    RETURNING * INTO v_reserved;
  END IF;

  RETURN v_reserved;
END;
$$;

-- admin_unreserve_username
CREATE OR REPLACE FUNCTION public.admin_unreserve_username(p_username text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_admin = true) THEN
    RAISE EXCEPTION 'not_admin';
  END IF;

  DELETE FROM public.reserved_usernames WHERE username = lower(trim(p_username));
  RETURN FOUND;
END;
$$;

-- ============================================================
-- 9. Seed system reserved usernames
-- ============================================================
INSERT INTO public.reserved_usernames (username, category, reason) VALUES
  ('admin', 'system', 'System reserved'),
  ('administrator', 'system', 'System reserved'),
  ('root', 'system', 'System reserved'),
  ('support', 'system', 'System reserved'),
  ('help', 'system', 'System reserved'),
  ('official', 'system', 'System reserved'),
  ('alsamos', 'system', 'System reserved'),
  ('api', 'system', 'System reserved'),
  ('auth', 'system', 'System reserved'),
  ('login', 'system', 'System reserved'),
  ('signup', 'system', 'System reserved'),
  ('settings', 'system', 'System reserved'),
  ('profile', 'system', 'System reserved'),
  ('user', 'system', 'System reserved'),
  ('channel', 'system', 'System reserved'),
  ('group', 'system', 'System reserved'),
  ('messages', 'system', 'System reserved'),
  ('market', 'system', 'System reserved'),
  ('payment', 'system', 'System reserved'),
  ('wallet', 'system', 'System reserved'),
  ('security', 'system', 'System reserved'),
  ('null', 'system', 'System reserved'),
  ('everyone', 'system', 'System reserved'),
  ('all', 'system', 'System reserved'),
  ('moderator', 'system', 'System reserved'),
  ('staff', 'system', 'System reserved'),
  ('test', 'system', 'System reserved')
ON CONFLICT (username) DO NOTHING;

-- ============================================================
-- 10. Grant permissions
-- ============================================================
GRANT EXECUTE ON FUNCTION public.check_username_availability(text, uuid) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.is_username_available(text, uuid) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.change_username(text) TO authenticated;
GRANT SELECT ON TABLE public.reserved_usernames TO authenticated, anon;
GRANT SELECT ON TABLE public.username_rules TO authenticated, anon;

COMMIT;

NOTIFY pgrst, 'reload schema';
