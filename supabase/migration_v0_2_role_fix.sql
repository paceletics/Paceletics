-- Paceletics migration v0.2
-- Keeps Supabase profile role in sync with the website signup metadata.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    case
      when coalesce(new.raw_user_meta_data ->> 'account_type', new.raw_user_meta_data ->> 'role') in ('athlete','coach','club')
        then coalesce(new.raw_user_meta_data ->> 'account_type', new.raw_user_meta_data ->> 'role')
      else 'athlete'
    end
  )
  on conflict (id) do update set
    full_name = excluded.full_name,
    role = excluded.role;
  return new;
end;
$$;

update public.profiles p
set
  full_name = coalesce(u.raw_user_meta_data ->> 'full_name', p.full_name),
  role = case
    when coalesce(u.raw_user_meta_data ->> 'account_type', u.raw_user_meta_data ->> 'role') in ('athlete','coach','club')
      then coalesce(u.raw_user_meta_data ->> 'account_type', u.raw_user_meta_data ->> 'role')
    else p.role
  end
from auth.users u
where u.id = p.id;
