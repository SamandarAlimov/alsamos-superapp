-- =============================================================================
-- Sticker usage bridge
--
-- The web client calls a single RPC, touch_sticker_usage(file_url, kind,
-- sticker_id), whenever a sticker or GIF is sent. The canonical stores are
-- sticker_usage_events (event log, powers trending_stickers) and
-- recent_stickers (per-user recents, powers the Flutter picker).
--
-- Rather than introduce a third table, this bridge fans one call out to both
-- canonical stores. Nothing is created here except the function itself.
--
-- Deliberately defensive: the two target tables come from different migration
-- sets that may not both be applied yet, so every write is guarded with
-- to_regclass and issued through EXECUTE. A missing table degrades to a no-op
-- instead of aborting the caller's message send.
--
-- Idempotent.
-- =============================================================================

create or replace function public.touch_sticker_usage(
  p_file_url text,
  p_kind text default 'sticker',
  p_sticker_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_context text;
begin
  -- Anonymous or empty calls are ignored rather than raising: sending a
  -- message must never fail because analytics could not be recorded.
  if v_user is null or coalesce(nullif(trim(p_file_url), ''), null) is null then
    return;
  end if;

  v_context := case when p_kind = 'gif' then 'gif' else 'sticker' end;

  -- 1. Event log. Keyed by URL, so externally hosted GIFs are recorded even
  --    though they have no row in stickers.
  if to_regclass('public.sticker_usage_events') is not null then
    execute
      'insert into public.sticker_usage_events'
      || ' (sticker_id, sticker_key, user_id, context)'
      || ' values ($1, $2, $3, $4)'
      using p_sticker_id, trim(p_file_url), v_user, v_context;
  end if;

  -- 2. Lifetime counter on the sticker row, when there is one.
  if p_sticker_id is not null and to_regclass('public.stickers') is not null then
    begin
      execute
        'update public.stickers set usage_count = usage_count + 1 where id = $1'
        using p_sticker_id;
    exception
      when undefined_column then null;
    end;
  end if;

  -- 3. Per-user recents. Only real stickers qualify, because
  --    recent_stickers.sticker_id is a required foreign key.
  if p_sticker_id is not null and to_regclass('public.recent_stickers') is not null then
    begin
      execute
        'insert into public.recent_stickers (user_id, sticker_id, use_count, last_used)'
        || ' values ($1, $2, 1, now())'
        || ' on conflict (user_id, sticker_id) do update'
        || '   set use_count = recent_stickers.use_count + 1, last_used = now()'
        using v_user, p_sticker_id;
    exception
      when others then null;
    end;
  end if;
end $$;

comment on function public.touch_sticker_usage(text, text, uuid) is
  'Web entry point for sticker and GIF usage. Fans out to sticker_usage_events and recent_stickers; never raises.';

grant execute on function public.touch_sticker_usage(text, text, uuid) to authenticated;

notify pgrst, 'reload schema';
