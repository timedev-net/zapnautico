-- Habilita extensões necessárias
create extension if not exists "pgcrypto" with schema extensions;

-- Função utilitária para atualizar automaticamente a coluna updated_at
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

-- ========================
-- Tabela de cotas de embarcações
-- ========================
create table if not exists public.boat_quotas (
  id uuid primary key default gen_random_uuid(),
  boat_name text not null,
  total_slots integer not null check (total_slots >= 0),
  reserved_slots integer not null default 0 check (reserved_slots >= 0),
  marina text not null,
  status text not null default 'ativo',
  next_departure timestamptz,
  notes text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint reserved_slots_within_limit check (reserved_slots <= total_slots)
);

create trigger boat_quotas_set_updated_at
before update on public.boat_quotas
for each row
execute function public.set_updated_at();

create index if not exists boat_quotas_next_departure_idx
  on public.boat_quotas (next_departure);

alter table public.boat_quotas
  enable row level security;

create policy "Authenticated users can view quotas"
  on public.boat_quotas
  for select
  to authenticated
  using (true);

-- ========================
-- Tabela de anúncios (marketplace)
-- ========================
create table if not exists public.marketplace_listings (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  type text not null check (type in ('venda', 'aluguel', 'acessorio')),
  status text not null default 'ativo' check (status in ('ativo', 'inativo')),
  owner_id uuid not null references auth.users (id) on delete cascade,
  price numeric(12,2),
  currency text check (char_length(currency) = 3),
  description text,
  media_url text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create trigger marketplace_listings_set_updated_at
before update on public.marketplace_listings
for each row
execute function public.set_updated_at();

create index if not exists marketplace_listings_owner_idx
  on public.marketplace_listings (owner_id);

create index if not exists marketplace_listings_status_idx
  on public.marketplace_listings (status);

alter table public.marketplace_listings
  enable row level security;

create policy "Authenticated users can read listings"
  on public.marketplace_listings
  for select
  to authenticated
  using (true);

create policy "Users can insert own listings"
  on public.marketplace_listings
  for insert
  to authenticated
  with check (auth.uid() = owner_id);

create policy "Owners can update their listings"
  on public.marketplace_listings
  for update
  to authenticated
  using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

create policy "Owners can delete their listings"
  on public.marketplace_listings
  for delete
  to authenticated
  using (auth.uid() = owner_id);

-- ========================
-- Tabela de mensagens do chat
-- ========================
create table if not exists public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  channel_id text not null default 'geral',
  content text not null,
  sender_id uuid not null references auth.users (id) on delete cascade,
  sender_name text,
  created_at timestamptz not null default timezone('utc', now())
);

create index if not exists chat_messages_channel_created_idx
  on public.chat_messages (channel_id, created_at desc);

alter table public.chat_messages
  enable row level security;

create policy "Authenticated users can read chat messages"
  on public.chat_messages
  for select
  to authenticated
  using (true);

create policy "Authenticated users can insert chat messages"
  on public.chat_messages
  for insert
  to authenticated
  with check (auth.uid() = sender_id);

-- ========================
-- Funções RPC para gerenciamento de cotas
-- ========================

create or replace function public.reserve_quota_slot(quota_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  updated_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Somente usuários autenticados podem reservar cotas.';
  end if;

  update public.boat_quotas
  set reserved_slots = reserved_slots + 1,
      updated_at = timezone('utc', now())
  where id = quota_id
    and reserved_slots < total_slots
  returning id into updated_id;

  if not found then
    raise exception 'Nenhuma vaga disponível para esta cota.';
  end if;

  return true;
end;
$$;

create or replace function public.release_quota_slot(quota_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  updated_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Somente usuários autenticados podem liberar cotas.';
  end if;

  update public.boat_quotas
  set reserved_slots = reserved_slots - 1,
      updated_at = timezone('utc', now())
  where id = quota_id
    and reserved_slots > 0
  returning id into updated_id;

  if not found then
    raise exception 'Não há reservas para liberar.';
  end if;

  return true;
end;
$$;

