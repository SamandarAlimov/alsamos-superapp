-- =============================================================================
-- place_reviews upsert key
--
-- The web client calls:
--   upsert(payload, { onConflict: 'user_id,place_key' })
--
-- PostgREST turns that into ON CONFLICT (user_id, place_key), and Postgres can
-- only infer that target from a NON-PARTIAL unique index on exactly those
-- columns. The earlier reconciliation created a partial unique index
-- (WHERE place_key IS NOT NULL) plus a plain btree index, so the upsert would
-- have failed with:
--   42P10: there is no unique or exclusion constraint matching the ON CONFLICT
--
-- A full unique index is safe here: rows whose place_key is still NULL do not
-- collide, because Postgres treats NULLs as distinct in unique indexes.
--
-- Duplicate (user_id, place_key) pairs cannot pre-exist, because place_key is
-- backfilled from place_id and the canonical table already enforces
-- UNIQUE (user_id, place_id).
--
-- Idempotent.
-- =============================================================================

create unique index if not exists place_reviews_user_place_key_uidx
  on public.place_reviews (user_id, place_key);

-- Superseded by the unique index above.
drop index if exists public.place_reviews_user_place_idx;

-- Kept: supports "all reviews for this place" lookups.
create index if not exists place_reviews_place_key_idx
  on public.place_reviews (place_key);

notify pgrst, 'reload schema';
