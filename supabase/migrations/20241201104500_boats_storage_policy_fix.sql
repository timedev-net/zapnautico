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
