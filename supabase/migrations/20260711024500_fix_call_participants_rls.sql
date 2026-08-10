drop policy if exists "Users can join calls" on public.call_participants;

create policy "Users can join calls"
on public.call_participants
for insert
to authenticated
with check (
  auth.uid() = user_id
  and exists (
    select 1
    from public.video_calls vc
    join public.conversation_participants cp
      on cp.conversation_id = vc.conversation_id
    where vc.id = call_participants.call_id
      and cp.user_id = auth.uid()
  )
);

drop policy if exists "Users can update own participation" on public.call_participants;

create policy "Users can update own participation"
on public.call_participants
for update
to authenticated
using (
  auth.uid() = user_id
)
with check (
  auth.uid() = user_id
);

drop policy if exists "Call host can invite conversation participants" on public.call_participants;

create policy "Call host can invite conversation participants"
on public.call_participants
for insert
to authenticated
with check (
  exists (
    select 1
    from public.video_calls vc
    join public.conversation_participants cp
      on cp.conversation_id = vc.conversation_id
     and cp.user_id = call_participants.user_id
    where vc.id = call_participants.call_id
      and vc.host_id = auth.uid()
  )
);
