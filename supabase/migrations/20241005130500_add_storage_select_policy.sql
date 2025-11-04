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

