-- User notifications persisted for push messages
create table if not exists public.user_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  title text not null,
  body text not null,
  data jsonb,
  status text not null default 'pending' check (status in ('pending', 'read')),
  created_at timestamptz not null default timezone('utc', now()),
  read_at timestamptz
);

create index if not exists user_notifications_user_status_idx
  on public.user_notifications (user_id, status, created_at desc);

alter table public.user_notifications enable row level security;

drop policy if exists "Ver proprias notificacoes" on public.user_notifications;
create policy "Ver proprias notificacoes"
  on public.user_notifications
  for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Atualizar proprias notificacoes" on public.user_notifications;
create policy "Atualizar proprias notificacoes"
  on public.user_notifications
  for update
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Inserir como service role" on public.user_notifications;
create policy "Inserir como service role"
  on public.user_notifications
  for insert
  to service_role
  with check (true);
