# Supabase Migration Playbook

The Supabase project is shared with Lovable. The remote database is source of
truth, and the user normally applies SQL manually.

## Rules

- Additive and idempotent only.
- Never drop/rename/alter existing columns.
- Use `CREATE TABLE IF NOT EXISTS`.
- Use `ADD COLUMN IF NOT EXISTS`.
- Use `CREATE INDEX IF NOT EXISTS`.
- Use `DROP POLICY IF EXISTS <name> ON <table>;` before `CREATE POLICY`.
- Use `CREATE OR REPLACE FUNCTION` unless changing parameter defaults requires
  a safe explicit `DROP FUNCTION IF EXISTS`.
- Guard realtime publication changes with `pg_publication_tables` checks.
- End every block with:

```sql
NOTIFY pgrst, 'reload schema';
```

## Worker Output

- Migration filename.
- Full copy-paste SQL block.
- One-line RLS audit note.
- Manual verification SQL when useful.

