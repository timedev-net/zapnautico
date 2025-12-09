-- Backend-driven scheduling for launch queue transitions

create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net with schema extensions;

alter table public.boat_launch_queue
  add column if not exists auto_transition_to text,
  add column if not exists auto_transition_at timestamptz,
  add column if not exists auto_transition_requested_by uuid references auth.users (id);

alter table public.boat_launch_queue
  drop constraint if exists boat_launch_queue_auto_transition_status_check;

alter table public.boat_launch_queue
  add constraint boat_launch_queue_auto_transition_status_check
  check (
    auto_transition_to is null
      or auto_transition_to in ('in_water', 'completed')
  );

create index if not exists boat_launch_queue_auto_transition_idx
  on public.boat_launch_queue (status, auto_transition_at)
  where auto_transition_to is not null;

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
    public.has_profile_for_marina('marina', v_entry.marina_id, requested_by)
    or public.is_admin(requested_by)
  ) then
    raise exception 'Not authorized to update this queue entry.';
  end if;

  if v_entry.status not in ('pending', 'in_water', 'in_progress') then
    raise exception 'Entry is already finalized.';
  end if;

  v_schedule_at := timezone('utc', now()) + make_interval(mins => delay_minutes);

  update public.boat_launch_queue
  set status = 'in_progress',
      auto_transition_to = target_status,
      auto_transition_at = v_schedule_at,
      auto_transition_requested_by = requested_by
  where id = entry_id;
end;
$$;

create or replace function public.process_launch_queue_transitions(
  max_batch integer default 50
) returns table(entry_id uuid, new_status text)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_now timestamptz := timezone('utc', now());
  v_functions_url text := nullif(
    current_setting('app.settings.supabase_url', true),
    ''
  );
  v_service_key text := nullif(
    current_setting('app.settings.service_role_key', true),
    ''
  );
  v_due record;
begin
  if v_functions_url is not null then
    v_functions_url :=
      rtrim(v_functions_url, '/') || '/functions/v1/notify_queue_status_change';
  end if;

  for v_due in
    select id, auto_transition_to
    from public.boat_launch_queue
    where status = 'in_progress'
      and auto_transition_to is not null
      and auto_transition_at is not null
      and auto_transition_at <= v_now
    order by auto_transition_at
    limit greatest(1, coalesce(max_batch, 50))
    for update skip locked
  loop
    update public.boat_launch_queue q
    set status = v_due.auto_transition_to,
        processed_at = v_now,
        auto_transition_to = null,
        auto_transition_at = null,
        auto_transition_requested_by = null
    where q.id = v_due.id
    returning q.id, q.status into entry_id, new_status;

    if v_functions_url is not null and v_service_key is not null then
      begin
        perform
          net.http_post(
            url := v_functions_url,
            headers := jsonb_build_object(
              'Content-Type', 'application/json',
              'Authorization', 'Bearer ' || v_service_key,
              'apikey', v_service_key
            ),
            body := jsonb_build_object(
              'entry_id', entry_id,
              'status', new_status
            )
          );
      exception
        when others then
          -- Best-effort notification. Processing should continue even on failure.
          null;
      end;
    end if;
    return next;
  end loop;
end;
$$;

do $$
declare
  existing_job int;
begin
  select jobid into existing_job
  from cron.job
  where jobname = 'process_launch_queue_transitions';

  if existing_job is not null then
    perform cron.unschedule(existing_job);
  end if;
end;
$$;

select cron.schedule(
  'process_launch_queue_transitions',
  '* * * * *',
  $$ select public.process_launch_queue_transitions(); $$
);
