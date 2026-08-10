BEGIN;

-- Group G reliability adds client-side runtime config validation only.
-- No database schema changes are required.
NOTIFY pgrst, 'reload schema';

COMMIT;
