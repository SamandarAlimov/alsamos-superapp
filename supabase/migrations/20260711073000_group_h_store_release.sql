BEGIN;

-- Group H store release changes are client/build metadata only.
-- No database schema changes are required.
NOTIFY pgrst, 'reload schema';

COMMIT;
