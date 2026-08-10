-- Phase 3 realtime/presence: privacy-filtered presence and read-state indexes.

create table if not exists public.user_privacy_exceptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  target_user_id uuid not null references public.profiles(id) on delete cascade,
  rule text not null check (rule in ('allow', 'deny')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, target_user_id)
);

create index if not exists idx_user_privacy_exceptions_user_target
  on public.user_privacy_exceptions(user_id, target_user_id);
create index if not exists idx_user_privacy_exceptions_target
  on public.user_privacy_exceptions(target_user_id);

alter table public.user_privacy_exceptions enable row level security;

drop policy if exists "Users manage own privacy exceptions" on public.user_privacy_exceptions;
create policy "Users manage own privacy exceptions"
  on public.user_privacy_exceptions
  for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create index if not exists idx_message_reads_message_read_at
  on public.message_reads(message_id, read_at desc);
create index if not exists idx_message_reads_user_read_at
  on public.message_reads(user_id, read_at desc);

drop policy if exists "Users can mark as read" on public.message_reads;
create policy "Users can mark as read"
  on public.message_reads for insert
  with check (
    user_id = auth.uid()
    and coalesce((
      select us.read_receipts_enabled
      from public.user_settings us
      where us.user_id = auth.uid()
    ), true)
    and exists (
      select 1
      from public.messages m
      join public.conversation_participants cp
        on cp.conversation_id = m.conversation_id
      where m.id = message_reads.message_id
        and cp.user_id = auth.uid()
    )
  );

drop policy if exists "Users can update own read receipts" on public.message_reads;
create policy "Users can update own read receipts"
  on public.message_reads for update
  using (user_id = auth.uid())
  with check (
    user_id = auth.uid()
    and coalesce((
      select us.read_receipts_enabled
      from public.user_settings us
      where us.user_id = auth.uid()
    ), true)
    and exists (
      select 1
      from public.messages m
      join public.conversation_participants cp
        on cp.conversation_id = m.conversation_id
      where m.id = message_reads.message_id
        and cp.user_id = auth.uid()
    )
  );

create or replace function public.are_contacts(a uuid, b uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.follows f1
    join public.follows f2
      on f2.follower_id = b and f2.following_id = a
    where f1.follower_id = a and f1.following_id = b
  );
$$;

create or replace function public.can_view_presence(target_user_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  viewer uuid := auth.uid();
  visibility text;
  exception_rule text;
begin
  if viewer is null then
    return false;
  end if;
  if viewer = target_user_id then
    return true;
  end if;

  select rule into exception_rule
  from public.user_privacy_exceptions
  where user_id = target_user_id and target_user_id = viewer
  limit 1;

  if exception_rule = 'allow' then
    return true;
  elsif exception_rule = 'deny' then
    return false;
  end if;

  select coalesce(last_seen_visibility, 'everyone') into visibility
  from public.user_settings
  where user_id = target_user_id;

  visibility := coalesce(visibility, 'everyone');

  if visibility = 'everyone' then
    return true;
  elsif visibility = 'contacts' then
    return public.are_contacts(target_user_id, viewer);
  end if;

  return false;
end;
$$;

create or replace function public.get_visible_presence(target_user_id uuid)
returns table(user_id uuid, is_online boolean, last_seen timestamptz)
language sql
security definer
set search_path = public
as $$
  select
    p.id as user_id,
    case when public.can_view_presence(target_user_id) then coalesce(p.is_online, false) else false end as is_online,
    case when public.can_view_presence(target_user_id) then p.last_seen else null end as last_seen
  from public.profiles p
  where p.id = target_user_id
  limit 1;
$$;

grant execute on function public.are_contacts(uuid, uuid) to authenticated;
grant execute on function public.can_view_presence(uuid) to authenticated;
grant execute on function public.get_visible_presence(uuid) to authenticated;

do $$
begin
  alter publication supabase_realtime add table public.message_reads;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.typing_indicators;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.profiles;
exception when duplicate_object then null;
end $$;
