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

drop function if exists public.can_manage_boat(uuid, uuid);

create or replace function public.can_manage_boat(
  boat_id_input uuid,
  user_id_input uuid default auth.uid()
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  target_user uuid := coalesce(user_id_input, auth.uid());
begin
  if boat_id_input is null or target_user is null then
    return false;
  end if;

  return exists(
    select 1
    from public.boats b
    left join public.boat_coowners co
      on co.boat_id = b.id
      and co.user_id = target_user
    where b.id = boat_id_input
      and (
        public.is_admin(target_user)
        or b.primary_owner_id = target_user
        or b.created_by = target_user
        or co.user_id is not null
      )
  );
end;
$$;

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
  using (
    auth.uid() = primary_owner_id
    or auth.uid() = created_by
    or exists (
      select 1
      from public.boat_coowners co
      where co.boat_id = id
        and co.user_id = auth.uid()
    )
  );

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
