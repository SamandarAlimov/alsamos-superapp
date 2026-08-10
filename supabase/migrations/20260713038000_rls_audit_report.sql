BEGIN;

CREATE OR REPLACE FUNCTION public.get_rls_audit_report()
RETURNS TABLE (
  schema_name text,
  table_name text,
  rls_enabled boolean,
  rls_forced boolean,
  policy_count integer,
  audit_status text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_user_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Only admins can run the RLS audit report';
  END IF;

  RETURN QUERY
  SELECT
    n.nspname::text AS schema_name,
    c.relname::text AS table_name,
    c.relrowsecurity AS rls_enabled,
    c.relforcerowsecurity AS rls_forced,
    COUNT(p.polname)::integer AS policy_count,
    CASE
      WHEN NOT c.relrowsecurity THEN 'missing_rls'
      WHEN COUNT(p.polname) = 0 THEN 'missing_policy'
      ELSE 'ok'
    END AS audit_status
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  LEFT JOIN pg_policy p ON p.polrelid = c.oid
  WHERE n.nspname = 'public'
    AND c.relkind = 'r'
    AND c.relname NOT LIKE 'pg_%'
    AND c.relname NOT LIKE 'supabase_%'
  GROUP BY n.nspname, c.relname, c.relrowsecurity, c.relforcerowsecurity
  ORDER BY
    CASE
      WHEN NOT c.relrowsecurity THEN 0
      WHEN COUNT(p.polname) = 0 THEN 1
      ELSE 2
    END,
    c.relname;
END;
$$;

REVOKE ALL ON FUNCTION public.get_rls_audit_report() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_rls_audit_report() TO authenticated;

COMMIT;
NOTIFY pgrst, 'reload schema';
