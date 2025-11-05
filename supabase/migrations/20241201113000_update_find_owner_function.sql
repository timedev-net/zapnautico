-- Atualiza função para evitar erro de permissão e normaliza e-mail

create or replace function public.find_proprietario_by_email(search_email text)
returns table (
  user_id uuid,
  email text,
  full_name text
)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  normalized_email text;
begin
  if search_email is null or length(trim(search_email)) = 0 then
    return;
  end if;

  normalized_email := lower(trim(search_email));

  if not (public.is_admin() or public.has_profile('proprietario')) then
    return;
  end if;

  return query
    select
      u.id,
      u.email,
      coalesce(
        u.raw_user_meta_data->>'full_name',
        u.raw_user_meta_data->>'name',
        ''
      ) as full_name
    from auth.users u
    where u.email is not null
      and lower(u.email) = normalized_email
      and public.user_has_profile(u.id, 'proprietario')
    limit 1;
end;
$$;
