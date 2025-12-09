-- Store queue backend credentials in a private table for backend processing.

create table if not exists public.queue_settings (
  key text primary key,
  value text not null,
  updated_at timestamptz not null default timezone('utc', now())
);

alter table public.queue_settings enable row level security;

do $$
begin
  if not exists (
    select 1 from public.queue_settings where key = 'supabase_url'
  ) then
    insert into public.queue_settings (key, value)
    values ('supabase_url', 'https://buykphfcdyjwotzsgprr.supabase.co');
  end if;

  if not exists (
    select 1 from public.queue_settings where key = 'service_role_key'
  ) then
    insert into public.queue_settings (key, value)
    values (
      'service_role_key',
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJ1eWtwaGZjZHlqd290enNncHJyIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2MjE4MjE3OSwiZXhwIjoyMDc3NzU4MTc5fQ.hfsO5Z5MarUavQH7stIHqdIueyrGKUxTQJxkl91Uz8k'
    );
  end if;
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
  v_functions_url text;
  v_service_key text;
  v_due record;
begin
  select value into v_functions_url
  from public.queue_settings
  where key = 'supabase_url';

  select value into v_service_key
  from public.queue_settings
  where key = 'service_role_key';

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
