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
