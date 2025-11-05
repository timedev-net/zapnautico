-- Linka o perfil "marina" a uma marina específica ao atribuir o perfil ao usuário.

do $$
begin
  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'user_profiles'
      and column_name = 'marina_id'
  ) then
    alter table public.user_profiles
      add column marina_id uuid references public.marinas (id);
  end if;
end;
$$;

create or replace view public.user_profiles_view as
select
  up.id,
  up.user_id,
  pt.slug as profile_slug,
  pt.name as profile_name,
  pt.description,
  up.assigned_by,
  up.created_at,
  up.marina_id,
  m.name as marina_name
from public.user_profiles up
join public.profile_types pt on pt.id = up.profile_type_id
left join public.marinas m on m.id = up.marina_id;

alter view public.user_profiles_view set (security_invoker = true);

drop function if exists public.admin_set_user_profiles(uuid, text[]);

create or replace function public.admin_set_user_profiles(
  target_user uuid,
  profile_payloads jsonb default '[]'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  payload jsonb;
  slug_value text;
  marina_value uuid;
  profile_type_id uuid;
  selected_profile_ids uuid[];
begin
  if not is_admin() then
    raise exception 'Insufficient privileges';
  end if;

  if target_user is null then
    raise exception 'Target user is required';
  end if;

  if profile_payloads is null
     or jsonb_typeof(profile_payloads) <> 'array'
     or jsonb_array_length(profile_payloads) = 0 then
    delete from public.user_profiles where user_id = target_user;
    return;
  end if;

  select coalesce(array_agg(distinct pt.id), array[]::uuid[])
  into selected_profile_ids
  from jsonb_array_elements(profile_payloads) as arr(elem)
  join public.profile_types pt on pt.slug = arr.elem->>'slug';

  if selected_profile_ids is null
     or array_length(selected_profile_ids, 1) is null then
    delete from public.user_profiles where user_id = target_user;
  else
    delete from public.user_profiles
    where user_id = target_user
      and profile_type_id <> all(selected_profile_ids);
  end if;

  for payload in select jsonb_array_elements(profile_payloads)
  loop
    slug_value := payload->>'slug';

    if slug_value is null then
      continue;
    end if;

    select id
    into profile_type_id
    from public.profile_types
    where slug = slug_value
    limit 1;

    if profile_type_id is null then
      raise exception 'Perfil "%" não encontrado.', slug_value;
    end if;

    marina_value := null;

    if slug_value = 'marina' then
      marina_value := (payload->>'marina_id')::uuid;

      if marina_value is null then
        raise exception 'Marina é obrigatória para o perfil "marina".';
      end if;
    end if;

    insert into public.user_profiles (user_id, profile_type_id, assigned_by, marina_id)
    values (target_user, profile_type_id, auth.uid(), marina_value)
    on conflict (user_id, profile_type_id) do update
      set marina_id = excluded.marina_id,
          assigned_by = excluded.assigned_by;
  end loop;
end;
$$;
