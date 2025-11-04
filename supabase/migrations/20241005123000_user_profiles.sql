-- Perfil de usuários e controle de permissões

create table if not exists public.profile_types (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  description text,
  created_at timestamptz not null default timezone('utc', now())
);

insert into public.profile_types (slug, name, description)
values
  ('administrador', 'Administrador', 'Acessa e gerencia todas as funcionalidades e usuários.'),
  ('cotista', 'Cotista', 'Participa de cotas de embarcações e realiza reservas.'),
  ('proprietario', 'Proprietário', 'Gerencia embarcações e cotas próprias.'),
  ('marina', 'Marina', 'Administra estruturas de marina e agenda serviços.'),
  ('visitante', 'Visitante', 'Possui acesso informativo e restrito.')
on conflict (slug) do nothing;

create table if not exists public.user_profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  profile_type_id uuid not null references public.profile_types (id) on delete cascade,
  assigned_by uuid references auth.users (id),
  created_at timestamptz not null default timezone('utc', now()),
  unique (user_id, profile_type_id)
);

alter table public.profile_types enable row level security;
alter table public.user_profiles enable row level security;

create or replace function public.is_admin(user_id uuid default auth.uid())
returns boolean
language sql
stable
as $$
  select exists (
    select 1
    from public.user_profiles up
    join public.profile_types pt on pt.id = up.profile_type_id
    where up.user_id = coalesce(user_id, auth.uid())
      and pt.slug = 'administrador'
  );
$$;

create policy "Perfis visíveis para autenticados" on public.profile_types
  for select
  to authenticated
  using (true);

create policy "Administradores podem inserir perfis" on public.profile_types
  for insert
  to authenticated
  with check (is_admin());

create policy "Administradores podem atualizar perfis" on public.profile_types
  for update
  to authenticated
  using (is_admin())
  with check (is_admin());

create policy "Administradores podem remover perfis" on public.profile_types
  for delete
  to authenticated
  using (is_admin());

create policy "Usuários veem seus perfis ou administradores veem todos"
  on public.user_profiles
  for select
  to authenticated
  using (user_id = auth.uid() or is_admin());

create policy "Somente administradores atribuem perfis"
  on public.user_profiles
  for insert
  to authenticated
  with check (is_admin());

create policy "Somente administradores removem perfis"
  on public.user_profiles
  for delete
  to authenticated
  using (is_admin());

create view public.user_profiles_view as
select
  up.id,
  up.user_id,
  pt.slug as profile_slug,
  pt.name as profile_name,
  pt.description,
  up.assigned_by,
  up.created_at
from public.user_profiles up
join public.profile_types pt on pt.id = up.profile_type_id;

alter view public.user_profiles_view set (security_invoker = true);

create or replace function public.admin_list_users()
returns table (
  id uuid,
  email text,
  full_name text,
  phone text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if not is_admin() then
    raise exception 'Insufficient privileges';
  end if;

  return query
  select
    u.id,
    u.email,
    coalesce(u.raw_user_meta_data->>'full_name', u.raw_user_meta_data->>'name') as full_name,
    u.phone,
    u.created_at
  from auth.users u
  order by u.created_at;
end;
$$;

create or replace function public.admin_set_user_profiles(target_user uuid, profile_slugs text[])
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  profile_ids uuid[];
begin
  if not is_admin() then
    raise exception 'Insufficient privileges';
  end if;

  if target_user is null then
    raise exception 'Target user is required';
  end if;

  if profile_slugs is null or array_length(profile_slugs, 1) is null then
    delete from public.user_profiles where user_id = target_user;
    return;
  end if;

  profile_ids := array(
    select id from public.profile_types where slug = any(profile_slugs)
  );

  delete from public.user_profiles
  where user_id = target_user
    and profile_type_id <> all(coalesce(profile_ids, array[]::uuid[]));

  insert into public.user_profiles (user_id, profile_type_id, assigned_by)
  select target_user, pt.id, auth.uid()
  from public.profile_types pt
  where pt.slug = any(profile_slugs)
    and not exists (
      select 1 from public.user_profiles up
      where up.user_id = target_user
        and up.profile_type_id = pt.id
    );
end;
$$;
