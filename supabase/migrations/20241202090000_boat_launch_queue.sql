-- Fila de descida de embarcações

create table if not exists public.boat_launch_queue (
  id uuid primary key default gen_random_uuid(),
  boat_id uuid not null references public.boats (id) on delete cascade,
  marina_id uuid not null references public.marinas (id) on delete cascade,
  requested_by uuid not null default auth.uid() references auth.users (id),
  status text not null default 'pending' check (
    status in ('pending', 'completed', 'cancelled')
  ),
  requested_at timestamptz not null default timezone('utc', now()),
  processed_at timestamptz,
  notes text
);

create index if not exists boat_launch_queue_marina_idx
  on public.boat_launch_queue (marina_id, status, requested_at);

create index if not exists boat_launch_queue_boat_idx
  on public.boat_launch_queue (boat_id);

create index if not exists boat_launch_queue_requested_by_idx
  on public.boat_launch_queue (requested_by);

create unique index if not exists boat_launch_queue_unique_pending
  on public.boat_launch_queue (boat_id)
  where status = 'pending';

alter table public.boat_launch_queue enable row level security;

drop policy if exists "Visualizar fila por autorizados" on public.boat_launch_queue;
create policy "Visualizar fila por autorizados"
  on public.boat_launch_queue
  for select
  to authenticated
  using (
    public.can_manage_boat(boat_id)
    or public.has_profile_for_marina('marina', marina_id)
    or public.is_admin()
  );

drop policy if exists "Inserir solicitacao de descida" on public.boat_launch_queue;
create policy "Inserir solicitacao de descida"
  on public.boat_launch_queue
  for insert
  to authenticated
  with check (
    status = 'pending'
    and requested_by = auth.uid()
    and public.can_manage_boat(boat_id)
  );

drop policy if exists "Atualizar solicitacao de descida" on public.boat_launch_queue;
create policy "Atualizar solicitacao de descida"
  on public.boat_launch_queue
  for update
  to authenticated
  using (
    public.has_profile_for_marina('marina', marina_id)
    or public.is_admin()
  )
  with check (
    public.has_profile_for_marina('marina', marina_id)
    or public.is_admin()
  );

drop policy if exists "Remover solicitacao de descida" on public.boat_launch_queue;
create policy "Remover solicitacao de descida"
  on public.boat_launch_queue
  for delete
  to authenticated
  using (
    requested_by = auth.uid()
    or public.has_profile_for_marina('marina', marina_id)
    or public.is_admin()
  );

drop view if exists public.boat_launch_queue_view;

create view public.boat_launch_queue_view as
select
  q.id,
  q.boat_id,
  q.marina_id,
  m.name as marina_name,
  q.requested_by,
  public.user_email(q.requested_by) as requested_by_email,
  public.user_full_name(q.requested_by) as requested_by_name,
  q.status,
  q.requested_at,
  row_number() over (partition by q.marina_id order by q.requested_at) as queue_position,
  case
    when public.can_manage_boat(q.boat_id)
      or public.has_profile_for_marina('marina', q.marina_id)
      or public.is_admin()
    then b.name
    else null
  end as visible_boat_name,
  case
    when public.can_manage_boat(q.boat_id)
      or public.has_profile_for_marina('marina', q.marina_id)
      or public.is_admin()
    then b.primary_owner_name
    else null
  end as visible_owner_name,
  public.can_manage_boat(q.boat_id) as is_own_boat,
  public.has_profile_for_marina('marina', q.marina_id) as is_marina_user
from public.boat_launch_queue q
join public.boats_detailed b on b.id = q.boat_id
left join public.marinas m on m.id = q.marina_id
where q.status = 'pending';

alter view public.boat_launch_queue_view set (security_invoker = true);
