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

