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
