-- Garantir que novos usuários recebam o perfil "visitante" automaticamente.

create or replace function public.ensure_visitor_profile(target_user uuid default auth.uid())
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  user_id uuid := coalesce(target_user, auth.uid());
  visitor_profile_id uuid;
begin
  if user_id is null then
    raise exception 'Target user is required';
  end if;

  select id
  into visitor_profile_id
  from public.profile_types
  where slug = 'visitante'
  limit 1;

  if visitor_profile_id is null then
    raise exception 'Profile "visitante" not found';
  end if;

  insert into public.user_profiles (user_id, profile_type_id, assigned_by)
  select user_id, visitor_profile_id, user_id
  where not exists (
    select 1
    from public.user_profiles up
    where up.user_id = user_id
  );
end;
$$;

drop function if exists public.handle_new_user_default_profile();

create or replace function public.handle_new_user_default_profile()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  perform public.ensure_visitor_profile(new.id);
  return new;
end;
$$;

drop trigger if exists assign_visitor_profile_on_user_created on auth.users;

create trigger assign_visitor_profile_on_user_created
after insert on auth.users
for each row
execute function public.handle_new_user_default_profile();
