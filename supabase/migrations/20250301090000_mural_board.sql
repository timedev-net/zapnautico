-- Mural de publicacoes das marinas

create table if not exists public.marina_wall_posts (
  id uuid primary key default gen_random_uuid(),
  marina_id uuid not null references public.marinas (id) on delete cascade,
  title text not null,
  description text,
  type text not null check (type in ('evento', 'aviso', 'publicidade')),
  start_date date not null,
  end_date date not null,
  image_url text,
  image_path text,
  created_by uuid references auth.users (id),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint marina_wall_dates_valid check (end_date >= start_date)
);

drop trigger if exists marina_wall_posts_set_updated_at on public.marina_wall_posts;
create trigger marina_wall_posts_set_updated_at
before update on public.marina_wall_posts
for each row
execute function public.set_updated_at();

create index if not exists marina_wall_posts_marina_idx
  on public.marina_wall_posts (marina_id, start_date desc, end_date desc);

alter table public.marina_wall_posts enable row level security;

drop policy if exists "Publicacoes do mural sao visiveis para autenticados" on public.marina_wall_posts;
create policy "Publicacoes do mural sao visiveis para autenticados"
  on public.marina_wall_posts
  for select
  to authenticated
  using (true);

drop policy if exists "Marina cria publicacoes para sua marina" on public.marina_wall_posts;
create policy "Marina cria publicacoes para sua marina"
  on public.marina_wall_posts
  for insert
  to authenticated
  with check (
    public.is_admin()
    or public.has_profile_for_marina('marina', marina_id)
  );

drop policy if exists "Marina atualiza publicacoes do seu mural" on public.marina_wall_posts;
create policy "Marina atualiza publicacoes do seu mural"
  on public.marina_wall_posts
  for update
  to authenticated
  using (
    public.is_admin()
    or public.has_profile_for_marina('marina', marina_id)
  )
  with check (
    public.is_admin()
    or public.has_profile_for_marina('marina', marina_id)
  );

drop policy if exists "Marina remove publicacoes do seu mural" on public.marina_wall_posts;
create policy "Marina remove publicacoes do seu mural"
  on public.marina_wall_posts
  for delete
  to authenticated
  using (
    public.is_admin()
    or public.has_profile_for_marina('marina', marina_id)
  );

drop view if exists public.marina_wall_posts_view;
create view public.marina_wall_posts_view as
select
  p.id,
  p.marina_id,
  m.name as marina_name,
  p.title,
  p.description,
  p.type,
  p.start_date,
  p.end_date,
  p.image_url,
  p.image_path,
  p.created_by,
  public.user_full_name(p.created_by) as created_by_name,
  p.created_at,
  p.updated_at
from public.marina_wall_posts p
left join public.marinas m on m.id = p.marina_id;

alter view public.marina_wall_posts_view set (security_invoker = true);

-- Bucket e politicas para fotos do mural
insert into storage.buckets (id, name, public)
values ('mural_photos', 'mural_photos', true)
on conflict (id) do nothing;

drop policy if exists "Mural photos are public" on storage.objects;
create policy "Mural photos are public"
  on storage.objects
  for select
  to public
  using (bucket_id = 'mural_photos');

drop policy if exists "Manage mural photos" on storage.objects;
create policy "Manage mural photos"
  on storage.objects
  for all
  to authenticated
  using (
    bucket_id = 'mural_photos'
    and (
      public.is_admin()
      or (
        split_part(name, '/', 1) = 'marinas'
        and case
          when split_part(name, '/', 2) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
            then public.has_profile_for_marina(
              'marina',
              split_part(name, '/', 2)::uuid
            )
          else false
        end
      )
    )
  )
  with check (
    bucket_id = 'mural_photos'
    and (
      public.is_admin()
      or (
        split_part(name, '/', 1) = 'marinas'
        and case
          when split_part(name, '/', 2) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
            then public.has_profile_for_marina(
              'marina',
              split_part(name, '/', 2)::uuid
            )
          else false
        end
      )
    )
  );

drop policy if exists "Mural bucket metadata" on storage.buckets;
create policy "Mural bucket metadata"
  on storage.buckets
  for select
  to authenticated
  using (name = 'mural_photos');
