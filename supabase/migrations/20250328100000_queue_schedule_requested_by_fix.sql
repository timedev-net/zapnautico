-- Fix ambiguous requested_by reference in scheduling RPC

create or replace function public.schedule_launch_queue_transition(
  entry_id uuid,
  target_status text,
  delay_minutes integer,
  requested_by uuid default auth.uid()
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_entry record;
  v_schedule_at timestamptz;
  v_requested_by uuid := requested_by;
begin
  if entry_id is null then
    raise exception 'entry_id is required';
  end if;

  if target_status is null
     or target_status not in ('in_water', 'completed') then
    raise exception 'Invalid target status';
  end if;

  if coalesce(delay_minutes, 0) <= 0 then
    raise exception 'Delay in minutes must be greater than zero.';
  end if;

  select id, marina_id, status
  into v_entry
  from public.boat_launch_queue
  where id = entry_id
  for update;

  if v_entry.id is null then
    raise exception 'Queue entry not found.';
  end if;

  if not (
    public.has_profile_for_marina('marina', v_entry.marina_id, v_requested_by)
    or public.is_admin(v_requested_by)
  ) then
    raise exception 'Not authorized to update this queue entry.';
  end if;

  if v_entry.status not in ('pending', 'in_water', 'in_progress') then
    raise exception 'Entry is already finalized.';
  end if;

  v_schedule_at := timezone('utc', now()) + make_interval(mins => delay_minutes);

  update public.boat_launch_queue q
  set status = 'in_progress',
      auto_transition_to = target_status,
      auto_transition_at = v_schedule_at,
      auto_transition_requested_by = v_requested_by
  where q.id = entry_id;
end;
$$;
