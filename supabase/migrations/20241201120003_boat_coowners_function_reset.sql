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
