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
