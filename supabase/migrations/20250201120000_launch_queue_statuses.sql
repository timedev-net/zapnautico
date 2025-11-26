-- Allow new statuses for boat launch queue and expose them in the view

alter table public.boat_launch_queue
  drop constraint if exists boat_launch_queue_status_check;

alter table public.boat_launch_queue
  add constraint boat_launch_queue_status_check
  check (
    status in ('pending', 'in_progress', 'in_water', 'completed', 'cancelled')
  );

create or replace view public.boat_launch_queue_view as
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
where q.status in ('pending', 'in_progress', 'in_water');

alter view public.boat_launch_queue_view set (security_invoker = true);
