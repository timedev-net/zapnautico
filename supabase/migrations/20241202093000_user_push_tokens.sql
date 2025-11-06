-- Tokens de push notificações por usuário/dispositivo

create table if not exists public.user_push_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  device_id text not null,
  token text not null,
  platform text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (user_id, device_id)
);

create index if not exists user_push_tokens_user_idx
  on public.user_push_tokens (user_id);

create trigger user_push_tokens_set_updated_at
before update on public.user_push_tokens
for each row
execute function public.set_updated_at();

alter table public.user_push_tokens enable row level security;

drop policy if exists "Usuarios veem tokens proprios" on public.user_push_tokens;
create policy "Usuarios veem tokens proprios"
  on public.user_push_tokens
  for select
  to authenticated
  using (auth.uid() = user_id or public.is_admin());

drop policy if exists "Usuarios registram tokens" on public.user_push_tokens;
create policy "Usuarios registram tokens"
  on public.user_push_tokens
  for insert
  to authenticated
  with check (auth.uid() = user_id or public.is_admin());

drop policy if exists "Usuarios atualizam tokens proprios" on public.user_push_tokens;
create policy "Usuarios atualizam tokens proprios"
  on public.user_push_tokens
  for update
  to authenticated
  using (auth.uid() = user_id or public.is_admin())
  with check (auth.uid() = user_id or public.is_admin());

drop policy if exists "Usuarios removem tokens proprios" on public.user_push_tokens;
create policy "Usuarios removem tokens proprios"
  on public.user_push_tokens
  for delete
  to authenticated
  using (auth.uid() = user_id or public.is_admin());
