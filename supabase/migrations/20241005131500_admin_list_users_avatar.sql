drop function if exists public.admin_list_users();

create function public.admin_list_users()
returns table (
  id uuid,
  email text,
  full_name text,
  phone text,
  avatar_url text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if not is_admin() then
    raise exception 'Insufficient privileges';
  end if;

  return query
  select
    u.id,
    u.email::text,
    coalesce(u.raw_user_meta_data->>'full_name', u.raw_user_meta_data->>'name')::text,
    u.phone::text,
    u.raw_user_meta_data->>'avatar_url' as avatar_url,
    u.created_at
  from auth.users u
  order by u.created_at;
end;
$$;

