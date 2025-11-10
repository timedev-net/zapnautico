create table if not exists public.boat_expenses (
  id uuid primary key default gen_random_uuid(),
  boat_id uuid not null references public.boats (id) on delete cascade,
  category text not null check (
    category in (
      'manutencao',
      'documento',
      'marina',
      'combustivel',
      'acessorios',
      'outros'
    )
  ),
  amount numeric(14, 2) not null check (amount >= 0),
  incurred_on date not null default current_date,
  description text,
  division_configured boolean not null default false,
  division_completed boolean not null default false,
  created_by uuid not null references auth.users (id),
  receipt_photo_path text,
  receipt_photo_url text,
  receipt_file_path text,
  receipt_file_url text,
  receipt_file_name text,
  receipt_file_type text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create index if not exists boat_expenses_boat_idx
  on public.boat_expenses (boat_id);

create index if not exists boat_expenses_created_by_idx
  on public.boat_expenses (created_by);

drop trigger if exists boat_expenses_set_updated_at on public.boat_expenses;
create trigger boat_expenses_set_updated_at
before update on public.boat_expenses
for each row
execute function public.set_updated_at();

create table if not exists public.boat_expense_shares (
  id uuid primary key default gen_random_uuid(),
  expense_id uuid not null references public.boat_expenses (id) on delete cascade,
  owner_id uuid not null references auth.users (id) on delete cascade,
  share_amount numeric(14, 2) not null check (share_amount >= 0),
  owner_name_snapshot text,
  owner_email_snapshot text,
  created_at timestamptz not null default timezone('utc', now()),
  unique (expense_id, owner_id)
);

create index if not exists boat_expense_shares_expense_idx
  on public.boat_expense_shares (expense_id);

alter table public.boat_expenses enable row level security;
alter table public.boat_expense_shares enable row level security;

drop policy if exists "Visualizar despesas de embarcacoes" on public.boat_expenses;
drop policy if exists "Criar despesa vinculada a embarcacao" on public.boat_expenses;
drop policy if exists "Autor atualiza despesa" on public.boat_expenses;
drop policy if exists "Autor remove despesa" on public.boat_expenses;

create policy "Visualizar despesas de embarcacoes"
  on public.boat_expenses
  for select
  to authenticated
  using (public.can_manage_boat(boat_id));

create policy "Criar despesa vinculada a embarcacao"
  on public.boat_expenses
  for insert
  to authenticated
  with check (
    public.can_manage_boat(boat_id)
    and auth.uid() = created_by
  );

create policy "Autor atualiza despesa"
  on public.boat_expenses
  for update
  to authenticated
  using (
    public.can_manage_boat(boat_id)
    and auth.uid() = created_by
  )
  with check (
    public.can_manage_boat(boat_id)
    and auth.uid() = created_by
  );

create policy "Autor remove despesa"
  on public.boat_expenses
  for delete
  to authenticated
  using (
    public.can_manage_boat(boat_id)
    and auth.uid() = created_by
  );

-- Policies for shares

drop policy if exists "Visualizar divisao de despesa" on public.boat_expense_shares;
drop policy if exists "Atualizar divisao de despesa" on public.boat_expense_shares;
drop policy if exists "Remover divisao de despesa" on public.boat_expense_shares;
drop policy if exists "Criar divisao de despesa" on public.boat_expense_shares;

create policy "Visualizar divisao de despesa"
  on public.boat_expense_shares
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.boat_expenses e
      where e.id = expense_id
        and public.can_manage_boat(e.boat_id)
    )
  );

create policy "Criar divisao de despesa"
  on public.boat_expense_shares
  for insert
  to authenticated
  with check (
    exists (
      select 1
      from public.boat_expenses e
      where e.id = expense_id
        and public.can_manage_boat(e.boat_id)
        and auth.uid() = e.created_by
    )
  );

create policy "Atualizar divisao de despesa"
  on public.boat_expense_shares
  for update
  to authenticated
  using (
    exists (
      select 1
      from public.boat_expenses e
      where e.id = expense_id
        and public.can_manage_boat(e.boat_id)
        and auth.uid() = e.created_by
    )
  )
  with check (
    exists (
      select 1
      from public.boat_expenses e
      where e.id = expense_id
        and public.can_manage_boat(e.boat_id)
        and auth.uid() = e.created_by
    )
  );

create policy "Remover divisao de despesa"
  on public.boat_expense_shares
  for delete
  to authenticated
  using (
    exists (
      select 1
      from public.boat_expenses e
      where e.id = expense_id
        and public.can_manage_boat(e.boat_id)
        and auth.uid() = e.created_by
    )
  );

-- View para facilitar leituras no app

drop view if exists public.boat_expenses_detailed;
create view public.boat_expenses_detailed as
with share_data as (
  select
    expense_id,
    jsonb_agg(
      jsonb_build_object(
        'owner_id', s.owner_id,
        'share_amount', s.share_amount,
        'owner_name', coalesce(s.owner_name_snapshot, public.user_full_name(s.owner_id)),
        'owner_email', coalesce(s.owner_email_snapshot, public.user_email(s.owner_id))
      )
      order by coalesce(s.owner_name_snapshot, public.user_full_name(s.owner_id))
    ) filter (where s.id is not null) as shares
  from public.boat_expense_shares s
  group by expense_id
)
select
  e.id,
  e.boat_id,
  b.name as boat_name,
  e.category,
  e.amount,
  e.incurred_on,
  e.description,
  e.division_configured,
  e.division_completed,
  e.receipt_photo_url,
  e.receipt_photo_path,
  e.receipt_file_url,
  e.receipt_file_path,
  e.receipt_file_name,
  e.receipt_file_type,
  e.created_by,
  public.user_full_name(e.created_by) as created_by_name,
  public.user_email(e.created_by) as created_by_email,
  e.created_at,
  e.updated_at,
  coalesce(shares.shares, '[]'::jsonb) as shares
from public.boat_expenses e
join public.boats b on b.id = e.boat_id
left join share_data shares on shares.expense_id = e.id;

alter view public.boat_expenses_detailed set (security_invoker = true);

-- Storage bucket para anexos financeiros

insert into storage.buckets (id, name, public)
values ('boat_expense_files', 'boat_expense_files', false)
on conflict (id) do nothing;

-- Policies para objetos do bucket

drop policy if exists "Acesso a anexos financeiros" on storage.objects;
drop policy if exists "Upload de anexos financeiros" on storage.objects;
drop policy if exists "Atualiza anexos financeiros" on storage.objects;
drop policy if exists "Remove anexos financeiros" on storage.objects;
drop policy if exists "Consulta bucket de anexos financeiros" on storage.buckets;

create policy "Acesso a anexos financeiros"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'boat_expense_files'
    and public.can_manage_boat(public.storage_boat_id(name))
  );

create policy "Upload de anexos financeiros"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'boat_expense_files'
    and public.can_manage_boat(public.storage_boat_id(name))
  );

create policy "Atualiza anexos financeiros"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'boat_expense_files'
    and public.can_manage_boat(public.storage_boat_id(name))
  )
  with check (
    bucket_id = 'boat_expense_files'
    and public.can_manage_boat(public.storage_boat_id(name))
  );

create policy "Remove anexos financeiros"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'boat_expense_files'
    and public.can_manage_boat(public.storage_boat_id(name))
  );

create policy "Consulta bucket de anexos financeiros"
  on storage.buckets
  for select
  to authenticated
  using (name = 'boat_expense_files');
