-- Corrige ambiguidade de coluna na função admin_set_user_profiles.

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
  profile_type_uuid uuid;
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
    delete from public.user_profiles up
    where up.user_id = target_user
      and up.profile_type_id <> all(selected_profile_ids);
  end if;

  for payload in select jsonb_array_elements(profile_payloads)
  loop
    slug_value := payload->>'slug';

    if slug_value is null then
      continue;
    end if;

    select id
    into profile_type_uuid
    from public.profile_types
    where slug = slug_value
    limit 1;

    if profile_type_uuid is null then
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
    values (target_user, profile_type_uuid, auth.uid(), marina_value)
    on conflict (user_id, profile_type_id) do update
      set marina_id = excluded.marina_id,
          assigned_by = excluded.assigned_by;
  end loop;
end;
$$;
