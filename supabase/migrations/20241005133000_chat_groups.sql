create table if not exists public.chat_groups (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create or replace trigger chat_groups_set_updated_at
before update on public.chat_groups
for each row execute function public.set_updated_at();

alter table public.chat_groups enable row level security;

drop policy if exists "Chat groups readable" on public.chat_groups;
create policy "Chat groups readable"
  on public.chat_groups
  for select
  to authenticated
  using (true);

drop policy if exists "Chat groups admin write" on public.chat_groups;
create policy "Chat groups admin write"
  on public.chat_groups
  for all
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

create table if not exists public.chat_group_members (
  group_id uuid not null references public.chat_groups (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  joined_at timestamptz not null default timezone('utc', now()),
  primary key (group_id, user_id)
);

alter table public.chat_group_members enable row level security;

drop policy if exists "Members can view groups" on public.chat_group_members;
create policy "Members can view groups"
  on public.chat_group_members
  for select
  to authenticated
  using (user_id = auth.uid() or public.is_admin());

drop policy if exists "Members can join groups" on public.chat_group_members;
create policy "Members can join groups"
  on public.chat_group_members
  for insert
  to authenticated
  with check ((user_id = auth.uid()) or public.is_admin());

drop policy if exists "Members can leave groups" on public.chat_group_members;
create policy "Members can leave groups"
  on public.chat_group_members
  for delete
  to authenticated
  using ((user_id = auth.uid()) or public.is_admin());

insert into public.chat_groups (id, name, description)
values ('00000000-0000-0000-0000-000000000001', 'Geral', 'Canal padrão do ZapNáutico')
on conflict (id) do nothing;

insert into public.chat_group_members (group_id, user_id)
select '00000000-0000-0000-0000-000000000001', id
from auth.users
on conflict do nothing;

alter table public.chat_messages
  add column if not exists group_id uuid references public.chat_groups (id) on delete cascade,
  add column if not exists sender_avatar_url text;

update public.chat_messages m
set group_id = coalesce(m.group_id, '00000000-0000-0000-0000-000000000001'),
    sender_name = coalesce(m.sender_name, u.raw_user_meta_data->>'full_name', u.raw_user_meta_data->>'name', u.email),
    sender_avatar_url = coalesce(m.sender_avatar_url, u.raw_user_meta_data->>'avatar_url')
from auth.users u
where m.sender_id = u.id;

alter table public.chat_messages
  alter column group_id set default '00000000-0000-0000-0000-000000000001';

create index if not exists chat_messages_group_created_idx
  on public.chat_messages (group_id, created_at asc);

drop policy if exists "Members read chat messages" on public.chat_messages;
create policy "Members read chat messages"
  on public.chat_messages
  for select
  to authenticated
  using (
    public.is_admin() or
    group_id in (
      select group_id from public.chat_group_members where user_id = auth.uid()
    )
  );

drop policy if exists "Members insert chat messages" on public.chat_messages;
create policy "Members insert chat messages"
  on public.chat_messages
  for insert
  to authenticated
  with check (
    sender_id = auth.uid() and (
      public.is_admin() or
      group_id in (
        select group_id from public.chat_group_members where user_id = auth.uid()
      )
    )
  );
