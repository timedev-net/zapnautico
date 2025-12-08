-- Bucket and table for launch queue photos

-- Storage bucket (public for serving photos via public URL)
insert into storage.buckets (id, name, public)
values ('boat_launch_queue_photos', 'boat_launch_queue_photos', true)
on conflict (id) do nothing;

-- Basic storage policies for the bucket
drop policy if exists "Upload fotos fila" on storage.objects;
drop policy if exists "Atualiza fotos fila" on storage.objects;
drop policy if exists "Remove fotos fila" on storage.objects;
drop policy if exists "Ler fotos fila" on storage.objects;

create policy "Upload fotos fila"
on storage.objects
for insert
to authenticated
with check (bucket_id = 'boat_launch_queue_photos');

create policy "Atualiza fotos fila"
on storage.objects
for update
to authenticated
using (bucket_id = 'boat_launch_queue_photos')
with check (bucket_id = 'boat_launch_queue_photos');

create policy "Remove fotos fila"
on storage.objects
for delete
to authenticated
using (bucket_id = 'boat_launch_queue_photos');

create policy "Ler fotos fila"
on storage.objects
for select
to authenticated
using (bucket_id = 'boat_launch_queue_photos');

-- Table to track uploaded photos per queue entry
create table if not exists public.boat_launch_queue_photos (
  id uuid primary key default gen_random_uuid(),
  queue_entry_id uuid not null references public.boat_launch_queue (id) on delete cascade,
  storage_path text not null,
  public_url text not null,
  created_at timestamptz not null default timezone('utc', now())
);

create index if not exists boat_launch_queue_photos_entry_idx
  on public.boat_launch_queue_photos (queue_entry_id);

create unique index if not exists boat_launch_queue_photos_storage_idx
  on public.boat_launch_queue_photos (storage_path);

alter table public.boat_launch_queue_photos enable row level security;

-- Policies aligned with queue visibility
drop policy if exists "Visualizar fotos da fila" on public.boat_launch_queue_photos;
drop policy if exists "Inserir fotos da fila" on public.boat_launch_queue_photos;
drop policy if exists "Remover fotos da fila" on public.boat_launch_queue_photos;

create policy "Visualizar fotos da fila"
on public.boat_launch_queue_photos
for select
to authenticated
using (
  exists (
    select 1
    from public.boat_launch_queue q
    where q.id = queue_entry_id
      and (
        q.requested_by = auth.uid()
        or public.has_profile_for_marina('marina', q.marina_id)
        or public.can_manage_boat(q.boat_id)
        or public.is_admin()
      )
  )
);

create policy "Inserir fotos da fila"
on public.boat_launch_queue_photos
for insert
to authenticated
with check (
  exists (
    select 1
    from public.boat_launch_queue q
    where q.id = queue_entry_id
      and (
        q.requested_by = auth.uid()
        or public.has_profile_for_marina('marina', q.marina_id)
        or public.can_manage_boat(q.boat_id)
        or public.is_admin()
      )
  )
);

create policy "Remover fotos da fila"
on public.boat_launch_queue_photos
for delete
to authenticated
using (
  exists (
    select 1
    from public.boat_launch_queue q
    where q.id = queue_entry_id
      and (
        q.requested_by = auth.uid()
        or public.has_profile_for_marina('marina', q.marina_id)
        or public.is_admin()
      )
  )
);
