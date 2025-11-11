-- Marketplace + contatos overhaul

-- 1) Ajustes estruturais na tabela de anúncios
alter table public.marketplace_listings
  drop constraint if exists marketplace_listings_type_check,
  drop constraint if exists marketplace_listings_status_check;

alter table public.marketplace_listings
  rename column type to category;

alter table public.marketplace_listings
  drop column if exists currency;

alter table public.marketplace_listings
  add column if not exists condition text not null default 'usado',
  add column if not exists payment_options text[] not null default array[]::text[],
  add column if not exists city text,
  add column if not exists state text,
  add column if not exists latitude double precision,
  add column if not exists longitude double precision,
  add column if not exists advertiser_name text,
  add column if not exists whatsapp_contacts jsonb not null default '[]'::jsonb,
  add column if not exists instagram_handle text,
  add column if not exists show_email boolean not null default false,
  add column if not exists video_url text,
  add column if not exists photos jsonb not null default '[]'::jsonb,
  add column if not exists boat_id uuid references public.boats (id) on delete set null,
  add column if not exists published_at timestamptz,
  add column if not exists sold_at timestamptz;

alter table public.marketplace_listings
  alter column status set default 'aguardando_publicacao';

update public.marketplace_listings
set status = case
  when status in ('ativo', 'publicado') then 'publicado'
  when status in ('inativo', 'arquivado') then 'aguardando_publicacao'
  when status = 'vendido' then 'vendido'
  else 'aguardando_publicacao'
end
where status not in ('aguardando_publicacao', 'publicado', 'vendido');

update public.marketplace_listings
set category = case
  when category = 'venda' then 'Embarcações'
  when category = 'aluguel' then 'Locação / Charter'
  when category = 'acessorio' then 'Peças e Acessórios'
  else 'Embarcações'
end;

alter table public.marketplace_listings
  add constraint marketplace_listings_category_check
    check (category in (
      'Embarcações',
      'Peças e Acessórios',
      'Equipamentos de Segurança',
      'Eletrônicos Náuticos',
      'Serviços',
      'Itens de Lazer e Esportes Aquáticos',
      'Equipamentos de Bordo / Conforto',
      'Vestuário e Acessórios',
      'Locação / Charter',
      'Cotas / Consórcios'
    ));

alter table public.marketplace_listings
  add constraint marketplace_listings_status_check
    check (status in ('aguardando_publicacao', 'publicado', 'vendido'));

alter table public.marketplace_listings
  add constraint marketplace_listings_condition_check
    check (condition in ('novo', 'usado'));

alter table public.marketplace_listings
  add constraint marketplace_payment_options_check
    check (payment_options <@ array['pix','credito_vista','credito_parcelado','negociavel']);

alter table public.marketplace_listings
  add constraint marketplace_whatsapp_contacts_array_check
    check (jsonb_typeof(whatsapp_contacts) = 'array');

alter table public.marketplace_listings
  add constraint marketplace_photos_array_check
    check (jsonb_typeof(photos) = 'array');

update public.marketplace_listings
set advertiser_name = coalesce(advertiser_name, public.user_full_name(owner_id))
where advertiser_name is null;

update public.marketplace_listings
set payment_options = array['pix']::text[]
where payment_options = '{}';

update public.marketplace_listings
set published_at = coalesce(published_at, created_at)
where status = 'publicado';

-- 2) View com metadados do proprietário
create or replace view public.marketplace_listings_view as
select
  ml.*,
  public.user_full_name(ml.owner_id) as owner_full_name,
  public.user_email(ml.owner_id) as owner_email
from public.marketplace_listings ml;

alter view public.marketplace_listings_view set (security_invoker = true);

-- 3) Trigger para auditoria de status
create or replace function public.marketplace_listings_status_audit()
returns trigger
language plpgsql
as $$
begin
  if new.status = 'publicado' and coalesce(old.status, '') <> 'publicado' then
    new.published_at = timezone('utc', now());
  end if;

  if new.status = 'vendido' and coalesce(old.status, '') <> 'vendido' then
    new.sold_at = timezone('utc', now());
  end if;

  return new;
end;
$$;

drop trigger if exists marketplace_listings_status_audit on public.marketplace_listings;
create trigger marketplace_listings_status_audit
before update on public.marketplace_listings
for each row
execute function public.marketplace_listings_status_audit();

-- 4) Índices auxiliares
create index if not exists marketplace_listings_category_idx
  on public.marketplace_listings (category);

create index if not exists marketplace_listings_created_idx
  on public.marketplace_listings (created_at desc);

create index if not exists marketplace_listings_city_state_idx
  on public.marketplace_listings (state, city);

-- 5) Políticas revisadas
drop policy if exists "Owners can update their listings" on public.marketplace_listings;
drop policy if exists "Owners can delete their listings" on public.marketplace_listings;

drop policy if exists "Admins manage listings" on public.marketplace_listings;

create policy "Owners update editable listings"
  on public.marketplace_listings
  for update
  to authenticated
  using (auth.uid() = owner_id and status <> 'vendido')
  with check (auth.uid() = owner_id);

create policy "Owners delete editable listings"
  on public.marketplace_listings
  for delete
  to authenticated
  using (auth.uid() = owner_id and status <> 'vendido');

create policy "Admins manage listings"
  on public.marketplace_listings
  for all
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- 6) Contatos dos usuários
create table if not exists public.user_contact_channels (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  channel text not null check (channel in ('whatsapp','instagram')),
  label text not null,
  value text not null,
  position integer not null default 0,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

drop trigger if exists user_contact_channels_set_updated_at on public.user_contact_channels;
create trigger user_contact_channels_set_updated_at
before update on public.user_contact_channels
for each row
execute function public.set_updated_at();

alter table public.user_contact_channels enable row level security;

drop policy if exists "Users manage contact channels" on public.user_contact_channels;
drop policy if exists "Admins manage contact channels" on public.user_contact_channels;

create policy "Users manage contact channels"
  on public.user_contact_channels
  for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "Admins manage contact channels"
  on public.user_contact_channels
  for all
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

create index if not exists user_contact_channels_user_idx
  on public.user_contact_channels (user_id, channel, position);

create unique index if not exists user_contact_unique_value
  on public.user_contact_channels (user_id, channel, lower(value));

-- 7) Bucket para fotos do marketplace
insert into storage.buckets (id, name, public)
values ('marketplace_photos', 'marketplace_photos', true)
on conflict (id) do nothing;

drop policy if exists "Public read marketplace photos" on storage.objects;
drop policy if exists "Users manage marketplace photos" on storage.objects;

drop policy if exists "Public read marketplace bucket" on storage.buckets;

drop policy if exists "Public read marketplace objects" on storage.objects;

create policy "Marketplace photos are public"
  on storage.objects
  for select
  to public
  using (bucket_id = 'marketplace_photos');

create policy "Manage marketplace photos"
  on storage.objects
  for all
  to authenticated
  using (
    bucket_id = 'marketplace_photos'
    and (
      public.is_admin()
      or (
        split_part(name, '/', 1) = 'listings'
        and exists (
          select 1 from public.marketplace_listings ml
          where ml.id::text = split_part(name, '/', 2)
            and ml.owner_id = auth.uid()
        )
      )
    )
  )
  with check (
    bucket_id = 'marketplace_photos'
    and (
      public.is_admin()
      or (
        split_part(name, '/', 1) = 'listings'
        and exists (
          select 1 from public.marketplace_listings ml
          where ml.id::text = split_part(name, '/', 2)
            and ml.owner_id = auth.uid()
        )
      )
    )
  );

create policy "Marketplace bucket metadata"
  on storage.buckets
  for select
  to authenticated
  using (name = 'marketplace_photos');
