-- Adiciona o tipo de embarcação ao cadastro e atualiza as visões dependentes.

alter table public.boats
  add column if not exists boat_type text not null default 'lancha'
    check (
      boat_type in (
        'lancha',
        'jet_ski',
        'barco_pesca',
        'bote',
        'iate',
        'veleiro'
      )
    );

update public.boats
set boat_type = 'lancha'
where boat_type is null;

drop view if exists public.boat_launch_queue_view;
drop view if exists public.boats_detailed;

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
  b.boat_type,
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

create view public.boat_launch_queue_view as
with photo as (
  select
    bp.boat_id,
    bp.public_url,
    row_number() over (
      partition by bp.boat_id
      order by bp.position nulls last, bp.created_at
    ) as photo_rank
  from public.boat_photos bp
)
select
  q.id,
  q.boat_id,
  q.generic_boat_name,
  q.marina_id,
  m.name as marina_name,
  q.requested_by,
  public.user_email(q.requested_by) as requested_by_email,
  public.user_full_name(q.requested_by) as requested_by_name,
  q.status,
  q.requested_at,
  row_number() over (
    partition by coalesce(
      q.marina_id,
      '00000000-0000-0000-0000-000000000000'::uuid
    )
    order by q.requested_at
  ) as queue_position,
  b.name as boat_name,
  p.public_url as boat_photo_url,
  case
    when q.boat_id is null then q.generic_boat_name
    when public.can_manage_boat(q.boat_id)
      or public.has_profile_for_marina('marina', q.marina_id)
      or public.is_admin()
    then b.name
    else null
  end as visible_boat_name,
  case
    when q.boat_id is null then null
    when public.can_manage_boat(q.boat_id)
      or public.has_profile_for_marina('marina', q.marina_id)
      or public.is_admin()
    then b.primary_owner_name
    else null
  end as visible_owner_name,
  coalesce(
    case when q.boat_id is not null then public.can_manage_boat(q.boat_id) end,
    false
  ) as is_own_boat,
  public.has_profile_for_marina('marina', q.marina_id) as is_marina_user
from public.boat_launch_queue q
left join public.boats_detailed b on b.id = q.boat_id
left join photo p on p.boat_id = q.boat_id and p.photo_rank = 1
left join public.marinas m on m.id = q.marina_id
where q.status = 'pending';

alter view public.boat_launch_queue_view set (security_invoker = true);
