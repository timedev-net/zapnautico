create table if not exists public.marinas (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  whatsapp text,
  instagram text,
  address text,
  latitude double precision not null,
  longitude double precision not null,
  photo_url text,
  photo_path text,
  created_by uuid references auth.users (id),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create trigger marinas_set_updated_at
before update on public.marinas
for each row
execute function public.set_updated_at();

alter table public.marinas enable row level security;

create policy "Admins podem visualizar marinas"
  on public.marinas
  for select
  to authenticated
  using (is_admin());

create policy "Admins podem inserir marinas"
  on public.marinas
  for insert
  to authenticated
  with check (is_admin());

create policy "Admins podem atualizar marinas"
  on public.marinas
  for update
  to authenticated
  using (is_admin())
  with check (is_admin());

create policy "Admins podem deletar marinas"
  on public.marinas
  for delete
  to authenticated
  using (is_admin());

