-- Phase 2 message interactions: reactions, forwards, edit history, drafts, tombstones, link previews.

alter table public.messages
  add column if not exists forwarded_from_message_id uuid references public.messages(id) on delete set null,
  add column if not exists forwarded_from_name text,
  add column if not exists is_silent boolean not null default false,
  add column if not exists deleted_at timestamptz,
  add column if not exists updated_at timestamptz not null default now();

create index if not exists idx_messages_forwarded_from_message_id
  on public.messages(forwarded_from_message_id);
create index if not exists idx_messages_deleted_at
  on public.messages(conversation_id, deleted_at);
create index if not exists idx_messages_updated_at
  on public.messages(conversation_id, updated_at desc);

alter table public.message_reactions
  add column if not exists updated_at timestamptz not null default now();

create index if not exists idx_message_reactions_message_id
  on public.message_reactions(message_id);
create index if not exists idx_message_reactions_user_id
  on public.message_reactions(user_id);
create index if not exists idx_message_reactions_updated_at
  on public.message_reactions(updated_at desc);

create table if not exists public.message_edit_history (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.messages(id) on delete cascade,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  editor_id uuid not null references public.profiles(id) on delete cascade,
  previous_content text,
  new_content text,
  edited_at timestamptz not null default now()
);

create index if not exists idx_message_edit_history_message_id
  on public.message_edit_history(message_id, edited_at desc);
create index if not exists idx_message_edit_history_conversation_id
  on public.message_edit_history(conversation_id, edited_at desc);

alter table public.message_edit_history enable row level security;

drop policy if exists "Participants can view edit history" on public.message_edit_history;
create policy "Participants can view edit history"
  on public.message_edit_history for select
  using (
    exists (
      select 1 from public.conversation_participants cp
      where cp.conversation_id = message_edit_history.conversation_id
        and cp.user_id = auth.uid()
    )
  );

drop policy if exists "Message sender can write edit history" on public.message_edit_history;
create policy "Message sender can write edit history"
  on public.message_edit_history for insert
  with check (
    editor_id = auth.uid()
    and exists (
      select 1 from public.messages m
      where m.id = message_edit_history.message_id
        and m.sender_id = auth.uid()
        and m.conversation_id = message_edit_history.conversation_id
    )
  );

create table if not exists public.message_drafts (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  content text not null default '',
  updated_at timestamptz not null default now(),
  primary key (conversation_id, user_id)
);

create index if not exists idx_message_drafts_user_updated
  on public.message_drafts(user_id, updated_at desc);

alter table public.message_drafts enable row level security;

drop policy if exists "Users can read own drafts" on public.message_drafts;
create policy "Users can read own drafts"
  on public.message_drafts for select
  using (user_id = auth.uid());

drop policy if exists "Users can upsert own drafts in joined conversations" on public.message_drafts;
create policy "Users can upsert own drafts in joined conversations"
  on public.message_drafts for insert
  with check (
    user_id = auth.uid()
    and exists (
      select 1 from public.conversation_participants cp
      where cp.conversation_id = message_drafts.conversation_id
        and cp.user_id = auth.uid()
    )
  );

drop policy if exists "Users can update own drafts" on public.message_drafts;
create policy "Users can update own drafts"
  on public.message_drafts for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create table if not exists public.link_previews (
  url text primary key,
  title text,
  description text,
  image_url text,
  updated_at timestamptz not null default now()
);

create index if not exists idx_link_previews_updated_at
  on public.link_previews(updated_at desc);

alter table public.link_previews enable row level security;

drop policy if exists "Authenticated users can read link previews" on public.link_previews;
create policy "Authenticated users can read link previews"
  on public.link_previews for select
  using (auth.role() = 'authenticated');

drop policy if exists "Authenticated users can cache link previews" on public.link_previews;
create policy "Authenticated users can cache link previews"
  on public.link_previews for insert
  with check (auth.role() = 'authenticated');

drop policy if exists "Authenticated users can refresh link previews" on public.link_previews;
create policy "Authenticated users can refresh link previews"
  on public.link_previews for update
  using (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');

alter table public.scheduled_messages
  add column if not exists reply_to_id uuid references public.messages(id) on delete set null,
  add column if not exists is_silent boolean not null default false,
  add column if not exists status text not null default 'scheduled',
  add column if not exists updated_at timestamptz not null default now();

create index if not exists idx_scheduled_messages_status_time
  on public.scheduled_messages(status, scheduled_for);
create index if not exists idx_scheduled_messages_sender_time
  on public.scheduled_messages(sender_id, scheduled_for);

drop policy if exists "Participants can update message tombstones" on public.messages;
create policy "Participants can update message tombstones"
  on public.messages for update
  using (
    sender_id = auth.uid()
    or exists (
      select 1 from public.conversation_participants cp
      where cp.conversation_id = messages.conversation_id
        and cp.user_id = auth.uid()
    )
  )
  with check (
    sender_id = auth.uid()
    or exists (
      select 1 from public.conversation_participants cp
      where cp.conversation_id = messages.conversation_id
        and cp.user_id = auth.uid()
    )
  );

do $$
begin
  alter publication supabase_realtime add table public.message_reactions;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.message_edit_history;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.message_drafts;
exception when duplicate_object then null;
end $$;
