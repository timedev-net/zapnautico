-- Habilita extensões necessárias
create extension if not exists "pgcrypto" with schema extensions;

-- Função utilitária para atualizar automaticamente a coluna updated_at
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

-- ========================
-- Tabela de cotas de embarcações
-- ========================
create table if not exists public.boat_quotas (
  id uuid primary key default gen_random_uuid(),
  boat_name text not null,
  total_slots integer not null check (total_slots >= 0),
  reserved_slots integer not null default 0 check (reserved_slots >= 0),
  marina text not null,
  status text not null default 'ativo',
  next_departure timestamptz,
  notes text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint reserved_slots_within_limit check (reserved_slots <= total_slots)
);

drop trigger if exists boat_quotas_set_updated_at on public.boat_quotas;
create trigger boat_quotas_set_updated_at
before update on public.boat_quotas
for each row
execute function public.set_updated_at();

create index if not exists boat_quotas_next_departure_idx
  on public.boat_quotas (next_departure);

alter table public.boat_quotas
  enable row level security;

create policy "Authenticated users can view quotas"
  on public.boat_quotas
  for select
  to authenticated
  using (true);

-- ========================
-- Tabela de anúncios (marketplace)
-- ========================
create table if not exists public.marketplace_listings (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  type text not null check (type in ('venda', 'aluguel', 'acessorio')),
  status text not null default 'ativo' check (status in ('ativo', 'inativo')),
  owner_id uuid not null references auth.users (id) on delete cascade,
  price numeric(12,2),
  currency text check (char_length(currency) = 3),
  description text,
  media_url text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

drop trigger if exists marketplace_listings_set_updated_at on public.marketplace_listings;
create trigger marketplace_listings_set_updated_at
before update on public.marketplace_listings
for each row
execute function public.set_updated_at();

create index if not exists marketplace_listings_owner_idx
  on public.marketplace_listings (owner_id);

create index if not exists marketplace_listings_status_idx
  on public.marketplace_listings (status);

alter table public.marketplace_listings
  enable row level security;

create policy "Authenticated users can read listings"
  on public.marketplace_listings
  for select
  to authenticated
  using (true);

create policy "Users can insert own listings"
  on public.marketplace_listings
  for insert
  to authenticated
  with check (auth.uid() = owner_id);

create policy "Owners can update their listings"
  on public.marketplace_listings
  for update
  to authenticated
  using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

create policy "Owners can delete their listings"
  on public.marketplace_listings
  for delete
  to authenticated
  using (auth.uid() = owner_id);

-- ========================
-- Tabela de mensagens do chat
-- ========================
create table if not exists public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  channel_id text not null default 'geral',
  content text not null,
  sender_id uuid not null references auth.users (id) on delete cascade,
  sender_name text,
  created_at timestamptz not null default timezone('utc', now())
);

create index if not exists chat_messages_channel_created_idx
  on public.chat_messages (channel_id, created_at desc);

alter table public.chat_messages
  enable row level security;

create policy "Authenticated users can read chat messages"
  on public.chat_messages
  for select
  to authenticated
  using (true);

create policy "Authenticated users can insert chat messages"
  on public.chat_messages
  for insert
  to authenticated
  with check (auth.uid() = sender_id);

-- ========================
-- Funções RPC para gerenciamento de cotas
-- ========================

create or replace function public.reserve_quota_slot(quota_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  updated_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Somente usuários autenticados podem reservar cotas.';
  end if;

  update public.boat_quotas
  set reserved_slots = reserved_slots + 1,
      updated_at = timezone('utc', now())
  where id = quota_id
    and reserved_slots < total_slots
  returning id into updated_id;

  if not found then
    raise exception 'Nenhuma vaga disponível para esta cota.';
  end if;

  return true;
end;
$$;

create or replace function public.release_quota_slot(quota_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  updated_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Somente usuários autenticados podem liberar cotas.';
  end if;

  update public.boat_quotas
  set reserved_slots = reserved_slots - 1,
      updated_at = timezone('utc', now())
  where id = quota_id
    and reserved_slots > 0
  returning id into updated_id;

  if not found then
    raise exception 'Não há reservas para liberar.';
  end if;

  return true;
end;
$$;

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
-- superseded by later migrations adding avatar support
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

drop trigger if exists marinas_set_updated_at on public.marinas;
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

create or replace function public.is_admin(user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.user_profiles up
    join public.profile_types pt on pt.id = up.profile_type_id
    where up.user_id = coalesce(user_id, auth.uid())
      and pt.slug = 'administrador'
  );
$$;

drop policy if exists "Admins podem inserir fotos de marinas" on storage.objects;
drop policy if exists "Admins podem atualizar fotos de marinas" on storage.objects;
drop policy if exists "Admins podem remover fotos de marinas" on storage.objects;

create policy "Admins podem inserir fotos de marinas"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'marina_photos'
  and public.is_admin(auth.uid())
);

create policy "Admins podem atualizar fotos de marinas"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'marina_photos'
  and public.is_admin(auth.uid())
)
with check (
  bucket_id = 'marina_photos'
  and public.is_admin(auth.uid())
);

create policy "Admins podem remover fotos de marinas"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'marina_photos'
  and public.is_admin(auth.uid())
);

drop policy if exists "Admins podem visualizar fotos de marinas" on storage.objects;
drop policy if exists "Admins podem consultar bucket de marinas" on storage.buckets;

create policy "Admins podem visualizar fotos de marinas"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'marina_photos'
  and public.is_admin(auth.uid())
);

create policy "Admins podem consultar bucket de marinas"
on storage.buckets
for select
to authenticated
using (
  name = 'marina_photos'
  and public.is_admin(auth.uid())
);

drop function if exists public.admin_list_users();

create function public.admin_list_users()
returns table (
  id uuid,
  email text,
  full_name text,
  phone text,
  avatar_url text,
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
    u.email::text,
    coalesce(u.raw_user_meta_data->>'full_name', u.raw_user_meta_data->>'name')::text,
    u.phone::text,
    u.raw_user_meta_data->>'avatar_url' as avatar_url,
    u.created_at
  from auth.users u
  order by u.created_at;
end;
$$;

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
-- Linka o perfil "marina" a uma marina específica ao atribuir o perfil ao usuário.

do $$
begin
  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'user_profiles'
      and column_name = 'marina_id'
  ) then
    alter table public.user_profiles
      add column marina_id uuid references public.marinas (id);
  end if;
end;
$$;

create or replace view public.user_profiles_view as
select
  up.id,
  up.user_id,
  pt.slug as profile_slug,
  pt.name as profile_name,
  pt.description,
  up.assigned_by,
  up.created_at,
  up.marina_id,
  m.name as marina_name
from public.user_profiles up
join public.profile_types pt on pt.id = up.profile_type_id
left join public.marinas m on m.id = up.marina_id;

alter view public.user_profiles_view set (security_invoker = true);

drop function if exists public.admin_set_user_profiles(uuid, text[]);

create or replace function public.admin_set_user_profiles(
  target_user uuid,
  profile_payloads jsonb default '[]'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  payload jsonb;
  slug_value text;
  marina_value uuid;
  profile_type_id uuid;
  selected_profile_ids uuid[];
begin
  if not is_admin() then
    raise exception 'Insufficient privileges';
  end if;

  if target_user is null then
    raise exception 'Target user is required';
  end if;

  if profile_payloads is null
     or jsonb_typeof(profile_payloads) <> 'array'
     or jsonb_array_length(profile_payloads) = 0 then
    delete from public.user_profiles where user_id = target_user;
    return;
  end if;

  select coalesce(array_agg(distinct pt.id), array[]::uuid[])
  into selected_profile_ids
  from jsonb_array_elements(profile_payloads) as arr(elem)
  join public.profile_types pt on pt.slug = arr.elem->>'slug';

  if selected_profile_ids is null
     or array_length(selected_profile_ids, 1) is null then
    delete from public.user_profiles where user_id = target_user;
  else
    delete from public.user_profiles
    where user_id = target_user
      and profile_type_id <> all(selected_profile_ids);
  end if;

  for payload in select jsonb_array_elements(profile_payloads)
  loop
    slug_value := payload->>'slug';

    if slug_value is null then
      continue;
    end if;

    select id
    into profile_type_id
    from public.profile_types
    where slug = slug_value
    limit 1;

    if profile_type_id is null then
      raise exception 'Perfil "%" não encontrado.', slug_value;
    end if;

    marina_value := null;

    if slug_value = 'marina' then
      marina_value := (payload->>'marina_id')::uuid;

      if marina_value is null then
        raise exception 'Marina é obrigatória para o perfil "marina".';
      end if;
    end if;

    insert into public.user_profiles (user_id, profile_type_id, assigned_by, marina_id)
    values (target_user, profile_type_id, auth.uid(), marina_value)
    on conflict (user_id, profile_type_id) do update
      set marina_id = excluded.marina_id,
          assigned_by = excluded.assigned_by;
  end loop;
end;
$$;
-- Corrige ambiguidade de coluna na função admin_set_user_profiles.

create or replace function public.admin_set_user_profiles(
  target_user uuid,
  profile_payloads jsonb default '[]'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  payload jsonb;
  slug_value text;
  marina_value uuid;
  profile_type_uuid uuid;
  selected_profile_ids uuid[];
begin
  if not is_admin() then
    raise exception 'Insufficient privileges';
  end if;

  if target_user is null then
    raise exception 'Target user is required';
  end if;

  if profile_payloads is null
     or jsonb_typeof(profile_payloads) <> 'array'
     or jsonb_array_length(profile_payloads) = 0 then
    delete from public.user_profiles where user_id = target_user;
    return;
  end if;

  select coalesce(array_agg(distinct pt.id), array[]::uuid[])
  into selected_profile_ids
  from jsonb_array_elements(profile_payloads) as arr(elem)
  join public.profile_types pt on pt.slug = arr.elem->>'slug';

  if selected_profile_ids is null
     or array_length(selected_profile_ids, 1) is null then
    delete from public.user_profiles where user_id = target_user;
  else
    delete from public.user_profiles up
    where up.user_id = target_user
      and up.profile_type_id <> all(selected_profile_ids);
  end if;

  for payload in select jsonb_array_elements(profile_payloads)
  loop
    slug_value := payload->>'slug';

    if slug_value is null then
      continue;
    end if;

    select id
    into profile_type_uuid
    from public.profile_types
    where slug = slug_value
    limit 1;

    if profile_type_uuid is null then
      raise exception 'Perfil "%" não encontrado.', slug_value;
    end if;

    marina_value := null;

    if slug_value = 'marina' then
      marina_value := (payload->>'marina_id')::uuid;

      if marina_value is null then
        raise exception 'Marina é obrigatória para o perfil "marina".';
      end if;
    end if;

    insert into public.user_profiles (user_id, profile_type_id, assigned_by, marina_id)
    values (target_user, profile_type_uuid, auth.uid(), marina_value)
    on conflict (user_id, profile_type_id) do update
      set marina_id = excluded.marina_id,
          assigned_by = excluded.assigned_by;
  end loop;
end;
$$;
-- Embarcações, fotos e funções auxiliares

-- Funções utilitárias para checar perfis
create or replace function public.user_has_profile(target_user uuid, profile_slug text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(
    select 1
    from public.user_profiles up
    join public.profile_types pt on pt.id = up.profile_type_id
    where up.user_id = target_user
      and pt.slug = profile_slug
  );
$$;

create or replace function public.has_profile(profile_slug text, user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.user_has_profile(coalesce(user_id, auth.uid()), profile_slug);
$$;

create or replace function public.has_profile_for_marina(profile_slug text, target_marina uuid, user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(
    select 1
    from public.user_profiles up
    join public.profile_types pt on pt.id = up.profile_type_id
    where up.user_id = coalesce(user_id, auth.uid())
      and pt.slug = profile_slug
      and up.marina_id = target_marina
  );
$$;

create table if not exists public.boats (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  registration_number text,
  fabrication_year integer not null check (
    fabrication_year >= 1900
    and fabrication_year <= extract(year from now())::integer + 1
  ),
  propulsion_type text not null check (
    propulsion_type in (
      'vela',
      'remo',
      'mecanica',
      'sem_propulsao'
    )
  ),
  engine_count integer check (engine_count is null or engine_count >= 0),
  engine_brand text,
  engine_model text,
  engine_year integer,
  engine_power text,
  usage_type text not null check (
    usage_type in (
      'esporte_recreio',
      'comercial',
      'pesca',
      'militar_naval',
      'servico_publico'
    )
  ),
  boat_size text not null check (
    boat_size in ('miuda', 'medio', 'grande')
  ),
  description text,
  trailer_plate text,
  marina_id uuid references public.marinas (id),
  primary_owner_id uuid not null references auth.users (id) on delete restrict,
  secondary_owner_id uuid references auth.users (id) on delete set null,
  created_by uuid not null references auth.users (id),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint engine_required_when_mechanic check (
    propulsion_type <> 'mecanica'
    or (
      engine_count is not null and engine_count >= 1
      and engine_brand is not null and char_length(trim(engine_brand)) > 0
      and engine_model is not null and char_length(trim(engine_model)) > 0
      and engine_year is not null
      and engine_power is not null and char_length(trim(engine_power)) > 0
    )
  ),
  constraint engine_null_when_without_propulsion check (
    propulsion_type = 'mecanica'
    or (
      engine_count is null
      and engine_brand is null
      and engine_model is null
      and engine_year is null
      and engine_power is null
    )
  ),
  constraint engine_year_limits check (
    engine_year is null
    or (
      engine_year >= 1900
      and engine_year <= extract(year from now())::integer + 1
    )
  ),
  constraint primary_owner_is_proprietario check (
    public.user_has_profile(primary_owner_id, 'proprietario')
  ),
  constraint secondary_owner_is_proprietario check (
    secondary_owner_id is null
    or public.user_has_profile(secondary_owner_id, 'proprietario')
  )
);

create index if not exists boats_primary_owner_idx
  on public.boats (primary_owner_id);

create index if not exists boats_secondary_owner_idx
  on public.boats (secondary_owner_id);

create index if not exists boats_marina_idx
  on public.boats (marina_id);

create index if not exists boats_created_by_idx
  on public.boats (created_by);

drop trigger if exists boats_set_updated_at on public.boats;
create trigger boats_set_updated_at
before update on public.boats
for each row
execute function public.set_updated_at();

create table if not exists public.boat_photos (
  id uuid primary key default gen_random_uuid(),
  boat_id uuid not null references public.boats (id) on delete cascade,
  storage_path text not null,
  public_url text not null,
  position integer not null default 0,
  created_at timestamptz not null default timezone('utc', now()),
  unique (boat_id, position)
);

create index if not exists boat_photos_boat_idx
  on public.boat_photos (boat_id);

create unique index if not exists boat_photos_storage_path_idx
  on public.boat_photos (storage_path);

alter table public.boats enable row level security;
alter table public.boat_photos enable row level security;

create policy "Admins podem visualizar embarcacoes"
  on public.boats
  for select
  to authenticated
  using (public.is_admin());

create policy "Proprietarios veem embarcacoes vinculadas"
  on public.boats
  for select
  to authenticated
  using (
    auth.uid() = primary_owner_id
    or auth.uid() = secondary_owner_id
    or auth.uid() = created_by
  );

create policy "Marinas veem embarcacoes vinculadas"
  on public.boats
  for select
  to authenticated
  using (
    marina_id is not null
    and public.has_profile_for_marina('marina', marina_id)
  );

create policy "Admins inserem embarcacoes"
  on public.boats
  for insert
  to authenticated
  with check (public.is_admin());

create policy "Proprietario cadastra embarcacao propria"
  on public.boats
  for insert
  to authenticated
  with check (
    public.has_profile('proprietario')
    and auth.uid() = primary_owner_id
    and auth.uid() = created_by
  );

create policy "Admins atualizam embarcacoes"
  on public.boats
  for update
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

create policy "Proprietario atualiza embarcacao propria"
  on public.boats
  for update
  to authenticated
  using (auth.uid() = primary_owner_id)
  with check (
    public.has_profile('proprietario')
    and auth.uid() = primary_owner_id
  );

create policy "Admins removem embarcacoes"
  on public.boats
  for delete
  to authenticated
  using (public.is_admin());

create policy "Proprietario remove embarcacao propria"
  on public.boats
  for delete
  to authenticated
  using (
    public.has_profile('proprietario')
    and auth.uid() = primary_owner_id
  );

create policy "Acesso a fotos por perfis autorizados"
  on public.boat_photos
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.boats b
      where b.id = boat_id
        and (
          public.is_admin()
          or auth.uid() = b.primary_owner_id
          or auth.uid() = b.secondary_owner_id
          or auth.uid() = b.created_by
          or (
            b.marina_id is not null
            and public.has_profile_for_marina('marina', b.marina_id)
          )
        )
    )
  );

create policy "Admins gerenciam fotos de embarcacoes"
  on public.boat_photos
  for insert
  to authenticated
  with check (
    exists (
      select 1
      from public.boats b
      where b.id = boat_id
        and public.is_admin()
    )
  );

create policy "Proprietario envia fotos da embarcacao"
  on public.boat_photos
  for insert
  to authenticated
  with check (
    exists (
      select 1
      from public.boats b
      where b.id = boat_id
        and auth.uid() = b.primary_owner_id
        and public.has_profile('proprietario')
    )
  );

create policy "Admins atualizam fotos de embarcacoes"
  on public.boat_photos
  for update
  to authenticated
  using (
    exists (
      select 1
      from public.boats b
      where b.id = boat_id
        and public.is_admin()
    )
  )
  with check (
    exists (
      select 1
      from public.boats b
      where b.id = boat_id
        and public.is_admin()
    )
  );

create policy "Proprietario atualiza fotos da embarcacao"
  on public.boat_photos
  for update
  to authenticated
  using (
    exists (
      select 1
      from public.boats b
      where b.id = boat_id
        and auth.uid() = b.primary_owner_id
        and public.has_profile('proprietario')
    )
  )
  with check (
    exists (
      select 1
      from public.boats b
      where b.id = boat_id
        and auth.uid() = b.primary_owner_id
        and public.has_profile('proprietario')
    )
  );

create policy "Admins removem fotos de embarcacoes"
  on public.boat_photos
  for delete
  to authenticated
  using (
    exists (
      select 1
      from public.boats b
      where b.id = boat_id
        and public.is_admin()
    )
  );

create policy "Proprietario remove fotos da embarcacao"
  on public.boat_photos
  for delete
  to authenticated
  using (
    exists (
      select 1
      from public.boats b
      where b.id = boat_id
        and auth.uid() = b.primary_owner_id
        and public.has_profile('proprietario')
    )
  );

create or replace function public.storage_boat_id(name text)
returns uuid
language plpgsql
immutable
as $$
declare
  matches text[];
begin
  if name is null then
    return null;
  end if;
  matches := regexp_match(name, '^boats/([0-9a-fA-F-]+)/');
  if matches is null or array_length(matches, 1) = 0 then
    return null;
  end if;
  begin
    return matches[1]::uuid;
  exception when others then
    return null;
  end;
end;
$$;

insert into storage.buckets (id, name, public)
values ('boat_photos', 'boat_photos', true)
on conflict (id) do nothing;

drop policy if exists "Acesso a fotos de embarcacoes" on storage.objects;
drop policy if exists "Upload de fotos de embarcacoes" on storage.objects;
drop policy if exists "Atualiza fotos de embarcacoes" on storage.objects;
drop policy if exists "Remove fotos de embarcacoes" on storage.objects;
drop policy if exists "Consulta bucket de embarcacoes" on storage.buckets;

create policy "Acesso a fotos de embarcacoes"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'boat_photos'
  and (
    public.is_admin()
    or exists (
      select 1
      from public.boats b
      where b.id = public.storage_boat_id(name)
        and (
          auth.uid() = b.primary_owner_id
          or auth.uid() = b.secondary_owner_id
          or auth.uid() = b.created_by
          or (
            b.marina_id is not null
            and public.has_profile_for_marina('marina', b.marina_id)
          )
        )
    )
  )
);

create policy "Upload de fotos de embarcacoes"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'boat_photos'
  and exists (
    select 1
    from public.boats b
    where b.id = public.storage_boat_id(name)
      and (
        public.is_admin()
        or (
          auth.uid() = b.primary_owner_id
          and public.has_profile('proprietario')
        )
      )
  )
);

create policy "Atualiza fotos de embarcacoes"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'boat_photos'
  and exists (
    select 1
    from public.boats b
    where b.id = public.storage_boat_id(name)
      and (
        public.is_admin()
        or (
          auth.uid() = b.primary_owner_id
          and public.has_profile('proprietario')
        )
      )
  )
)
with check (
  bucket_id = 'boat_photos'
  and exists (
    select 1
    from public.boats b
    where b.id = public.storage_boat_id(name)
      and (
        public.is_admin()
        or (
          auth.uid() = b.primary_owner_id
          and public.has_profile('proprietario')
        )
      )
  )
);

create policy "Remove fotos de embarcacoes"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'boat_photos'
  and exists (
    select 1
    from public.boats b
    where b.id = public.storage_boat_id(name)
      and (
        public.is_admin()
        or (
          auth.uid() = b.primary_owner_id
          and public.has_profile('proprietario')
        )
      )
  )
);

create policy "Consulta bucket de embarcacoes"
on storage.buckets
for select
to authenticated
using (name = 'boat_photos');

create or replace view public.boats_detailed as
select
  b.id,
  b.name,
  b.registration_number,
  b.fabrication_year,
  b.propulsion_type,
  b.engine_count,
  b.engine_brand,
  b.engine_model,
  b.engine_year,
  b.engine_power,
  b.usage_type,
  b.boat_size,
  b.description,
  b.trailer_plate,
  b.marina_id,
  m.name as marina_name,
  b.primary_owner_id,
  primary_user.email as primary_owner_email,
  coalesce(
    primary_user.raw_user_meta_data->>'full_name',
    primary_user.raw_user_meta_data->>'name',
    ''
  ) as primary_owner_name,
  b.secondary_owner_id,
  secondary_user.email as secondary_owner_email,
  coalesce(
    secondary_user.raw_user_meta_data->>'full_name',
    secondary_user.raw_user_meta_data->>'name',
    ''
  ) as secondary_owner_name,
  b.created_by,
  b.created_at,
  b.updated_at,
  coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', bp.id,
        'storage_path', bp.storage_path,
        'public_url', bp.public_url,
        'position', bp.position
      )
      order by bp.position
    ) filter (where bp.id is not null),
    '[]'::jsonb
  ) as photos
from public.boats b
left join public.marinas m on m.id = b.marina_id
left join auth.users primary_user on primary_user.id = b.primary_owner_id
left join auth.users secondary_user on secondary_user.id = b.secondary_owner_id
left join public.boat_photos bp on bp.boat_id = b.id
group by
  b.id,
  m.name,
  primary_user.id,
  secondary_user.id;

alter view public.boats_detailed set (security_invoker = true);

create or replace function public.find_proprietario_by_email(search_email text)
returns table (
  user_id uuid,
  email text,
  full_name text
)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  normalized_email text;
begin
  if search_email is null or length(trim(search_email)) = 0 then
    return;
  end if;

  if not (public.is_admin() or public.has_profile('proprietario')) then
    raise exception 'Acesso negado';
  end if;

  normalized_email := lower(trim(search_email));

  return query
    select
      u.id,
      u.email,
      coalesce(
        u.raw_user_meta_data->>'full_name',
        u.raw_user_meta_data->>'name',
        ''
      ) as full_name
    from auth.users u
    where u.email is not null
      and lower(u.email) = normalized_email
      and public.user_has_profile(u.id, 'proprietario')
    limit 1;
end;
$$;
-- Ajusta visualização de embarcações para evitar erro de permissão ao acessar auth.users

create or replace function public.user_email(user_id uuid)
returns text
language sql
stable
security definer
set search_path = public, auth
as $$
  select u.email
  from auth.users u
  where u.id = user_id
  limit 1;
$$;

create or replace function public.user_full_name(user_id uuid)
returns text
language sql
stable
security definer
set search_path = public, auth
as $$
  select coalesce(
    u.raw_user_meta_data->>'full_name',
    u.raw_user_meta_data->>'name',
    ''
  )
  from auth.users u
  where u.id = user_id
  limit 1;
$$;

drop view if exists public.boats_detailed;

create view public.boats_detailed as
select
  b.id,
  b.name,
  b.registration_number,
  b.fabrication_year,
  b.propulsion_type,
  b.engine_count,
  b.engine_brand,
  b.engine_model,
  b.engine_year,
  b.engine_power,
  b.usage_type,
  b.boat_size,
  b.description,
  b.trailer_plate,
  b.marina_id,
  m.name as marina_name,
  b.primary_owner_id,
  public.user_email(b.primary_owner_id) as primary_owner_email,
  public.user_full_name(b.primary_owner_id) as primary_owner_name,
  b.secondary_owner_id,
  public.user_email(b.secondary_owner_id) as secondary_owner_email,
  public.user_full_name(b.secondary_owner_id) as secondary_owner_name,
  b.created_by,
  b.created_at,
  b.updated_at,
  coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', bp.id,
        'storage_path', bp.storage_path,
        'public_url', bp.public_url,
        'position', bp.position
      )
      order by bp.position
    ) filter (where bp.id is not null),
    '[]'::jsonb
  ) as photos
from public.boats b
left join public.marinas m on m.id = b.marina_id
left join public.boat_photos bp on bp.boat_id = b.id
group by
  b.id,
  m.name;

alter view public.boats_detailed set (security_invoker = true);
-- Ajusta políticas de fotos de embarcações para permitir upload pelo proprietário e perfis autorizados

drop policy if exists "Proprietario envia fotos da embarcacao" on public.boat_photos;
drop policy if exists "Admins gerenciam fotos de embarcacoes" on public.boat_photos;
drop policy if exists "Proprietario atualiza fotos da embarcacao" on public.boat_photos;
drop policy if exists "Admins atualizam fotos de embarcacoes" on public.boat_photos;
drop policy if exists "Proprietario remove fotos da embarcacao" on public.boat_photos;
drop policy if exists "Admins removem fotos de embarcacoes" on public.boat_photos;

create policy "Usuarios autorizados inserem fotos de embarcacoes"
on public.boat_photos
for insert
to authenticated
with check (
  exists (
    select 1
    from public.boats b
    where b.id = boat_id
      and (
        public.is_admin()
        or auth.uid() = b.primary_owner_id
        or auth.uid() = b.secondary_owner_id
        or auth.uid() = b.created_by
      )
  )
);

create policy "Usuarios autorizados atualizam fotos de embarcacoes"
on public.boat_photos
for update
to authenticated
using (
  exists (
    select 1
    from public.boats b
    where b.id = boat_id
      and (
        public.is_admin()
        or auth.uid() = b.primary_owner_id
        or auth.uid() = b.secondary_owner_id
        or auth.uid() = b.created_by
      )
  )
)
with check (
  exists (
    select 1
    from public.boats b
    where b.id = boat_id
      and (
        public.is_admin()
        or auth.uid() = b.primary_owner_id
        or auth.uid() = b.secondary_owner_id
        or auth.uid() = b.created_by
      )
  )
);

create policy "Usuarios autorizados removem fotos de embarcacoes"
on public.boat_photos
for delete
to authenticated
using (
  exists (
    select 1
    from public.boats b
    where b.id = boat_id
      and (
        public.is_admin()
        or auth.uid() = b.primary_owner_id
        or auth.uid() = b.secondary_owner_id
        or auth.uid() = b.created_by
      )
  )
);

drop policy if exists "Upload de fotos de embarcacoes" on storage.objects;
drop policy if exists "Atualiza fotos de embarcacoes" on storage.objects;
drop policy if exists "Remove fotos de embarcacoes" on storage.objects;

create policy "Upload de fotos de embarcacoes"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'boat_photos'
  and exists (
    select 1
    from public.boats b
    where b.id = public.storage_boat_id(name)
      and (
        public.is_admin()
        or auth.uid() = b.primary_owner_id
        or auth.uid() = b.secondary_owner_id
        or auth.uid() = b.created_by
      )
  )
);

create policy "Atualiza fotos de embarcacoes"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'boat_photos'
  and exists (
    select 1
    from public.boats b
    where b.id = public.storage_boat_id(name)
      and (
        public.is_admin()
        or auth.uid() = b.primary_owner_id
        or auth.uid() = b.secondary_owner_id
        or auth.uid() = b.created_by
      )
  )
)
with check (
  bucket_id = 'boat_photos'
  and exists (
    select 1
    from public.boats b
    where b.id = public.storage_boat_id(name)
      and (
        public.is_admin()
        or auth.uid() = b.primary_owner_id
        or auth.uid() = b.secondary_owner_id
        or auth.uid() = b.created_by
      )
  )
);

create policy "Remove fotos de embarcacoes"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'boat_photos'
  and exists (
    select 1
    from public.boats b
    where b.id = public.storage_boat_id(name)
      and (
        public.is_admin()
        or auth.uid() = b.primary_owner_id
        or auth.uid() = b.secondary_owner_id
        or auth.uid() = b.created_by
      )
  )
);
-- Função auxiliar para validar se o usuário pode gerenciar uma embarcação

create or replace function public.can_manage_boat(
  boat_id uuid,
  user_id uuid default auth.uid()
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if boat_id is null then
    return false;
  end if;

  return exists(
    select 1
    from public.boats b
    where b.id = boat_id
      and (
        public.is_admin(user_id)
        or b.primary_owner_id = coalesce(user_id, auth.uid())
        or b.secondary_owner_id = coalesce(user_id, auth.uid())
        or b.created_by = coalesce(user_id, auth.uid())
      )
  );
end;
$$;

-- Recria políticas utilizando a função de autorização

drop policy if exists "Usuarios autorizados inserem fotos de embarcacoes" on public.boat_photos;
drop policy if exists "Usuarios autorizados atualizam fotos de embarcacoes" on public.boat_photos;
drop policy if exists "Usuarios autorizados removem fotos de embarcacoes" on public.boat_photos;

create policy "Usuarios autorizados inserem fotos de embarcacoes"
on public.boat_photos
for insert
to authenticated
with check (public.can_manage_boat(boat_id));

create policy "Usuarios autorizados atualizam fotos de embarcacoes"
on public.boat_photos
for update
to authenticated
using (public.can_manage_boat(boat_id))
with check (public.can_manage_boat(boat_id));

create policy "Usuarios autorizados removem fotos de embarcacoes"
on public.boat_photos
for delete
to authenticated
using (public.can_manage_boat(boat_id));

drop policy if exists "Upload de fotos de embarcacoes" on storage.objects;
drop policy if exists "Atualiza fotos de embarcacoes" on storage.objects;
drop policy if exists "Remove fotos de embarcacoes" on storage.objects;

create policy "Upload de fotos de embarcacoes"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'boat_photos'
  and public.can_manage_boat(public.storage_boat_id(name))
);

create policy "Atualiza fotos de embarcacoes"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'boat_photos'
  and public.can_manage_boat(public.storage_boat_id(name))
)
with check (
  bucket_id = 'boat_photos'
  and public.can_manage_boat(public.storage_boat_id(name))
);

create policy "Remove fotos de embarcacoes"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'boat_photos'
  and public.can_manage_boat(public.storage_boat_id(name))
);
-- Atualiza função para evitar erro de permissão e normaliza e-mail

create or replace function public.find_proprietario_by_email(search_email text)
returns table (
  user_id uuid,
  email text,
  full_name text
)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  normalized_email text;
begin
  if search_email is null or length(trim(search_email)) = 0 then
    return;
  end if;

  normalized_email := lower(trim(search_email));

  if not (public.is_admin() or public.has_profile('proprietario')) then
    return;
  end if;

  return query
    select
      u.id,
      u.email,
      coalesce(
        u.raw_user_meta_data->>'full_name',
        u.raw_user_meta_data->>'name',
        ''
      ) as full_name
    from auth.users u
    where u.email is not null
      and lower(u.email) = normalized_email
      and public.user_has_profile(u.id, 'proprietario')
    limit 1;
end;
$$;
create or replace function public.find_proprietario_by_email(search_email text)
returns table (
  user_id uuid,
  email text,
  full_name text
)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  normalized_email text;
begin
  if search_email is null or length(trim(search_email)) = 0 then
    return;
  end if;

  normalized_email := lower(trim(search_email));

  if not (public.is_admin() or public.has_profile('proprietario')) then
    return;
  end if;

  return query
    select
      u.id,
      u.email::text,
      coalesce(
        u.raw_user_meta_data->>'full_name',
        u.raw_user_meta_data->>'name',
        ''
      )::text as full_name
    from auth.users u
    where u.email is not null
      and lower(u.email) = normalized_email
      and public.user_has_profile(u.id, 'proprietario')
    limit 1;
end;
$$;
-- Suporte a múltiplos coproprietários

drop view if exists public.boats_detailed;

drop policy if exists "Proprietarios veem embarcacoes vinculadas" on public.boats;

drop policy if exists "Acesso a fotos por perfis autorizados" on public.boat_photos;
drop policy if exists "Usuarios autorizados inserem fotos de embarcacoes" on public.boat_photos;
drop policy if exists "Usuarios autorizados atualizam fotos de embarcacoes" on public.boat_photos;
drop policy if exists "Usuarios autorizados removem fotos de embarcacoes" on public.boat_photos;

drop policy if exists "Acesso a fotos de embarcacoes" on storage.objects;
drop policy if exists "Upload de fotos de embarcacoes" on storage.objects;
drop policy if exists "Atualiza fotos de embarcacoes" on storage.objects;
drop policy if exists "Remove fotos de embarcacoes" on storage.objects;

create table if not exists public.boat_coowners (
  id uuid primary key default gen_random_uuid(),
  boat_id uuid not null references public.boats (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  created_by uuid references auth.users (id),
  created_at timestamptz not null default timezone('utc', now()),
  unique (boat_id, user_id)
);

insert into public.boat_coowners (boat_id, user_id, created_by)
select id, secondary_owner_id, primary_owner_id
from public.boats
where secondary_owner_id is not null;

drop index if exists boats_secondary_owner_idx;
alter table public.boats drop constraint if exists secondary_owner_is_proprietario;
alter table public.boats drop column if exists secondary_owner_id;

alter table public.boat_coowners enable row level security;

create view public.boats_detailed as
with coowners as (
  select
    boat_id,
    coalesce(
      array_agg(user_id order by created_at)
        filter (where user_id is not null),
      array[]::uuid[]
    ) as co_owner_ids,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'user_id', user_id,
          'email', public.user_email(user_id),
          'full_name', public.user_full_name(user_id)
        )
        order by created_at
      ) filter (where user_id is not null),
      '[]'::jsonb
    ) as co_owners
  from public.boat_coowners
  group by boat_id
),
photos as (
  select
    boat_id,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', id,
          'storage_path', storage_path,
          'public_url', public_url,
          'position', position
        )
        order by position
      ) filter (where id is not null),
      '[]'::jsonb
    ) as photos
  from public.boat_photos
  group by boat_id
)
select
  b.id,
  b.name,
  b.registration_number,
  b.fabrication_year,
  b.propulsion_type,
  b.engine_count,
  b.engine_brand,
  b.engine_model,
  b.engine_year,
  b.engine_power,
  b.usage_type,
  b.boat_size,
  b.description,
  b.trailer_plate,
  b.marina_id,
  m.name as marina_name,
  b.primary_owner_id,
  public.user_email(b.primary_owner_id) as primary_owner_email,
  public.user_full_name(b.primary_owner_id) as primary_owner_name,
  b.created_by,
  b.created_at,
  b.updated_at,
  coalesce(co.co_owner_ids, array[]::uuid[]) as co_owner_ids,
  coalesce(co.co_owners, '[]'::jsonb) as co_owners,
  coalesce(ph.photos, '[]'::jsonb) as photos
from public.boats b
left join public.marinas m on m.id = b.marina_id
left join coowners co on co.boat_id = b.id
left join photos ph on ph.boat_id = b.id;

alter view public.boats_detailed set (security_invoker = true);


alter table public.boat_coowners enable row level security;

-- Policies do storage

drop policy if exists "Acesso a fotos de embarcacoes" on storage.objects;
drop policy if exists "Upload de fotos de embarcacoes" on storage.objects;
drop policy if exists "Atualiza fotos de embarcacoes" on storage.objects;
drop policy if exists "Remove fotos de embarcacoes" on storage.objects;

create policy "Acesso a fotos de embarcacoes"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'boat_photos'
    and public.can_manage_boat(public.storage_boat_id(name))
  );

create policy "Upload de fotos de embarcacoes"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'boat_photos'
    and public.can_manage_boat(public.storage_boat_id(name))
  );

create policy "Atualiza fotos de embarcacoes"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'boat_photos'
    and public.can_manage_boat(public.storage_boat_id(name))
  )
  with check (
    bucket_id = 'boat_photos'
    and public.can_manage_boat(public.storage_boat_id(name))
  );

create policy "Remove fotos de embarcacoes"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'boat_photos'
    and public.can_manage_boat(public.storage_boat_id(name))
  );

-- Atualiza view

drop view if exists public.boats_detailed;

create view public.boats_detailed as
with coowners as (
  select
    boat_id,
    coalesce(
      array_agg(user_id order by created_at)
        filter (where user_id is not null),
      array[]::uuid[]
    ) as co_owner_ids,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'user_id', user_id,
          'email', public.user_email(user_id),
          'full_name', public.user_full_name(user_id)
        )
        order by created_at
      ) filter (where user_id is not null),
      '[]'::jsonb
    ) as co_owners
  from public.boat_coowners
  group by boat_id
),
photos as (
  select
    boat_id,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', id,
          'storage_path', storage_path,
          'public_url', public_url,
          'position', position
        )
        order by position
      ) filter (where id is not null),
      '[]'::jsonb
    ) as photos
  from public.boat_photos
  group by boat_id
)
select
  b.id,
  b.name,
  b.registration_number,
  b.fabrication_year,
  b.propulsion_type,
  b.engine_count,
  b.engine_brand,
  b.engine_model,
  b.engine_year,
  b.engine_power,
  b.usage_type,
  b.boat_size,
  b.description,
  b.trailer_plate,
  b.marina_id,
  m.name as marina_name,
  b.primary_owner_id,
  public.user_email(b.primary_owner_id) as primary_owner_email,
  public.user_full_name(b.primary_owner_id) as primary_owner_name,
  b.created_by,
  b.created_at,
  b.updated_at,
  coalesce(co.co_owner_ids, array[]::uuid[]) as co_owner_ids,
  coalesce(co.co_owners, '[]'::jsonb) as co_owners,
  coalesce(ph.photos, '[]'::jsonb) as photos
from public.boats b
left join public.marinas m on m.id = b.marina_id
left join coowners co on co.boat_id = b.id
left join photos ph on ph.boat_id = b.id;

alter view public.boats_detailed set (security_invoker = true);
-- Reinicia função can_manage_boat e policies dependentes

drop policy if exists "Visualizar coproprietarios autorizados" on public.boat_coowners;
drop policy if exists "Administradores gerenciam coproprietarios" on public.boat_coowners;
drop policy if exists "Proprietario adiciona coproprietarios" on public.boat_coowners;
drop policy if exists "Proprietario remove coproprietarios" on public.boat_coowners;

drop policy if exists "Proprietarios veem embarcacoes vinculadas" on public.boats;

drop policy if exists "Acesso a fotos por perfis autorizados" on public.boat_photos;
drop policy if exists "Usuarios autorizados inserem fotos de embarcacoes" on public.boat_photos;
drop policy if exists "Usuarios autorizados atualizam fotos de embarcacoes" on public.boat_photos;
drop policy if exists "Usuarios autorizados removem fotos de embarcacoes" on public.boat_photos;

drop policy if exists "Acesso a fotos de embarcacoes" on storage.objects;
drop policy if exists "Upload de fotos de embarcacoes" on storage.objects;
drop policy if exists "Atualiza fotos de embarcacoes" on storage.objects;
drop policy if exists "Remove fotos de embarcacoes" on storage.objects;

-- Remove qualquer definição anterior

drop function if exists public.can_manage_boat(uuid, uuid);
drop function if exists public.can_manage_boat(uuid);

create or replace function public.can_manage_boat(
  p_boat_id uuid,
  p_user_id uuid default auth.uid()
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $func$
declare
  target_user uuid := coalesce(p_user_id, auth.uid());
begin
  if p_boat_id is null or target_user is null then
    return false;
  end if;

  return exists(
    select 1
    from public.boats b
    left join public.boat_coowners co
      on co.boat_id = b.id
      and co.user_id = target_user
    where b.id = p_boat_id
      and (
        public.is_admin(target_user)
        or b.primary_owner_id = target_user
        or b.created_by = target_user
        or co.user_id is not null
      )
  );
end;
$func$;

-- Recria policies com a nova função

create policy "Visualizar coproprietarios autorizados"
  on public.boat_coowners
  for select
  to authenticated
  using (public.can_manage_boat(boat_id));

create policy "Administradores gerenciam coproprietarios"
  on public.boat_coowners
  for all
  to authenticated
  using (public.is_admin());

create policy "Proprietario adiciona coproprietarios"
  on public.boat_coowners
  for insert
  to authenticated
  with check (
    public.is_admin() or exists (
      select 1 from public.boats b
      where b.id = boat_id
        and b.primary_owner_id = auth.uid()
    )
  );

create policy "Proprietario remove coproprietarios"
  on public.boat_coowners
  for delete
  to authenticated
  using (
    public.is_admin() or exists (
      select 1 from public.boats b
      where b.id = boat_id
        and b.primary_owner_id = auth.uid()
    )
  );

create policy "Proprietarios veem embarcacoes vinculadas"
  on public.boats
  for select
  to authenticated
  using (public.can_manage_boat(id));

create policy "Acesso a fotos por perfis autorizados"
  on public.boat_photos
  for select
  to authenticated
  using (public.can_manage_boat(boat_id));

create policy "Usuarios autorizados inserem fotos de embarcacoes"
  on public.boat_photos
  for insert
  to authenticated
  with check (public.can_manage_boat(boat_id));

create policy "Usuarios autorizados atualizam fotos de embarcacoes"
  on public.boat_photos
  for update
  to authenticated
  using (public.can_manage_boat(boat_id))
  with check (public.can_manage_boat(boat_id));

create policy "Usuarios autorizados removem fotos de embarcacoes"
  on public.boat_photos
  for delete
  to authenticated
  using (public.can_manage_boat(boat_id));

create policy "Acesso a fotos de embarcacoes"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'boat_photos'
    and public.can_manage_boat(public.storage_boat_id(name))
  );

create policy "Upload de fotos de embarcacoes"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'boat_photos'
    and public.can_manage_boat(public.storage_boat_id(name))
  );

create policy "Atualiza fotos de embarcacoes"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'boat_photos'
    and public.can_manage_boat(public.storage_boat_id(name))
  )
  with check (
    bucket_id = 'boat_photos'
    and public.can_manage_boat(public.storage_boat_id(name))
  );

create policy "Remove fotos de embarcacoes"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'boat_photos'
    and public.can_manage_boat(public.storage_boat_id(name))
  );
-- Fila de descida de embarcações

create table if not exists public.boat_launch_queue (
  id uuid primary key default gen_random_uuid(),
  boat_id uuid not null references public.boats (id) on delete cascade,
  marina_id uuid not null references public.marinas (id) on delete cascade,
  requested_by uuid not null default auth.uid() references auth.users (id),
  status text not null default 'pending' check (
    status in ('pending', 'completed', 'cancelled')
  ),
  requested_at timestamptz not null default timezone('utc', now()),
  processed_at timestamptz,
  notes text
);

create index if not exists boat_launch_queue_marina_idx
  on public.boat_launch_queue (marina_id, status, requested_at);

create index if not exists boat_launch_queue_boat_idx
  on public.boat_launch_queue (boat_id);

create index if not exists boat_launch_queue_requested_by_idx
  on public.boat_launch_queue (requested_by);

create unique index if not exists boat_launch_queue_unique_pending
  on public.boat_launch_queue (boat_id)
  where status = 'pending';

alter table public.boat_launch_queue enable row level security;

drop policy if exists "Visualizar fila por autorizados" on public.boat_launch_queue;
create policy "Visualizar fila por autorizados"
  on public.boat_launch_queue
  for select
  to authenticated
  using (
    public.can_manage_boat(boat_id)
    or public.has_profile_for_marina('marina', marina_id)
    or public.is_admin()
  );

drop policy if exists "Inserir solicitacao de descida" on public.boat_launch_queue;
create policy "Inserir solicitacao de descida"
  on public.boat_launch_queue
  for insert
  to authenticated
  with check (
    status = 'pending'
    and requested_by = auth.uid()
    and public.can_manage_boat(boat_id)
  );

drop policy if exists "Atualizar solicitacao de descida" on public.boat_launch_queue;
create policy "Atualizar solicitacao de descida"
  on public.boat_launch_queue
  for update
  to authenticated
  using (
    public.has_profile_for_marina('marina', marina_id)
    or public.is_admin()
  )
  with check (
    public.has_profile_for_marina('marina', marina_id)
    or public.is_admin()
  );

drop policy if exists "Remover solicitacao de descida" on public.boat_launch_queue;
create policy "Remover solicitacao de descida"
  on public.boat_launch_queue
  for delete
  to authenticated
  using (
    requested_by = auth.uid()
    or public.has_profile_for_marina('marina', marina_id)
    or public.is_admin()
  );

drop view if exists public.boat_launch_queue_view;

create view public.boat_launch_queue_view as
select
  q.id,
  q.boat_id,
  q.marina_id,
  m.name as marina_name,
  q.requested_by,
  public.user_email(q.requested_by) as requested_by_email,
  public.user_full_name(q.requested_by) as requested_by_name,
  q.status,
  q.requested_at,
  row_number() over (partition by q.marina_id order by q.requested_at) as queue_position,
  case
    when public.can_manage_boat(q.boat_id)
      or public.has_profile_for_marina('marina', q.marina_id)
      or public.is_admin()
    then b.name
    else null
  end as visible_boat_name,
  case
    when public.can_manage_boat(q.boat_id)
      or public.has_profile_for_marina('marina', q.marina_id)
      or public.is_admin()
    then b.primary_owner_name
    else null
  end as visible_owner_name,
  public.can_manage_boat(q.boat_id) as is_own_boat,
  public.has_profile_for_marina('marina', q.marina_id) as is_marina_user
from public.boat_launch_queue q
join public.boats_detailed b on b.id = q.boat_id
left join public.marinas m on m.id = q.marina_id
where q.status = 'pending';

alter view public.boat_launch_queue_view set (security_invoker = true);
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

drop trigger if exists user_push_tokens_set_updated_at on public.user_push_tokens;
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
-- Permite entradas genéricas na fila de descida

alter table public.boat_launch_queue
  alter column boat_id drop not null;

do $$
begin
  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'boat_launch_queue'
      and column_name = 'generic_boat_name'
  ) then
    alter table public.boat_launch_queue
      add column generic_boat_name text;
  end if;
end;
$$;

alter table public.boat_launch_queue
  drop constraint if exists boat_launch_queue_has_target;

alter table public.boat_launch_queue
  add constraint boat_launch_queue_has_target check (
    boat_id is not null
    or (generic_boat_name is not null and char_length(trim(generic_boat_name)) > 0)
  );

drop policy if exists "Inserir solicitacao de descida" on public.boat_launch_queue;
create policy "Inserir solicitacao de descida"
  on public.boat_launch_queue
  for insert
  to authenticated
  with check (
    status = 'pending'
    and requested_by = auth.uid()
    and (
      (boat_id is not null and public.can_manage_boat(boat_id))
      or (boat_id is null and public.has_profile_for_marina('marina', marina_id))
    )
  );

drop policy if exists "Atualizar solicitacao de descida" on public.boat_launch_queue;
create policy "Atualizar solicitacao de descida"
  on public.boat_launch_queue
  for update
  to authenticated
  using (
    public.has_profile_for_marina('marina', marina_id)
    or public.is_admin()
  )
  with check (
    public.has_profile_for_marina('marina', marina_id)
    or public.is_admin()
  );

drop policy if exists "Remover solicitacao de descida" on public.boat_launch_queue;
create policy "Remover solicitacao de descida"
  on public.boat_launch_queue
  for delete
  to authenticated
  using (
    requested_by = auth.uid()
    or public.has_profile_for_marina('marina', marina_id)
    or public.is_admin()
  );

drop view if exists public.boat_launch_queue_view;

create view public.boat_launch_queue_view as
select
  q.id,
  q.boat_id,
  q.generic_boat_name,
  q.marina_id,
  m.name as marina_name,
  q.requested_by,
  public.user_email(q.requested_by) as requested_by_email,
  public.user_full_name(q.requested_by) as requested_by_name,
  q.status,
  q.requested_at,
  row_number() over (partition by q.marina_id order by q.requested_at) as queue_position,
  b.name as boat_name,
  case
    when q.boat_id is null then q.generic_boat_name
    when public.can_manage_boat(q.boat_id)
      or public.has_profile_for_marina('marina', q.marina_id)
      or public.is_admin()
    then b.name
    else null
  end as visible_boat_name,
  case
    when q.boat_id is null then null
    when public.can_manage_boat(q.boat_id)
      or public.has_profile_for_marina('marina', q.marina_id)
      or public.is_admin()
    then b.primary_owner_name
    else null
  end as visible_owner_name,
  coalesce(
    case when q.boat_id is not null then public.can_manage_boat(q.boat_id) end,
    false
  ) as is_own_boat,
  public.has_profile_for_marina('marina', q.marina_id) as is_marina_user
from public.boat_launch_queue q
left join public.boats_detailed b on b.id = q.boat_id
left join public.marinas m on m.id = q.marina_id
where q.status = 'pending';

alter view public.boat_launch_queue_view set (security_invoker = true);
