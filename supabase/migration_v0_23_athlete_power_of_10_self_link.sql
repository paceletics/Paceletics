-- Paceletics database migration v0.23
-- Allow a linked Athlete account to manage its own Power of 10 profile connection.

create or replace function public.save_my_power_of_10_profile(p_url text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_athlete public.athletes%rowtype;
  v_url text;
  v_power_id text;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in.';
  end if;

  if not exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role = 'athlete'
  ) then
    raise exception 'Only Athlete accounts can update their Power of 10 profile.';
  end if;

  select a.* into v_athlete
  from public.athletes a
  where a.linked_user_id = auth.uid()
    and coalesce(a.is_active, true) = true
  order by a.created_at
  limit 1;

  if not found then
    raise exception 'Your Athlete account is not linked to an active athlete profile.';
  end if;

  v_url := nullif(trim(coalesce(p_url, '')), '');

  if v_url is not null then
    v_power_id := public.extract_power_of_10_athlete_id(v_url);
    if v_power_id is null then
      raise exception 'Use a valid Power of 10 athlete profile URL.';
    end if;
  end if;

  update public.athletes a
  set power_of_10_url = v_url
  where a.id = v_athlete.id
  returning a.* into v_athlete;

  return jsonb_build_object(
    'status', case when v_athlete.power_of_10_url is null then 'unlinked' else 'linked' end,
    'athlete_id', v_athlete.id,
    'power_of_10_url', v_athlete.power_of_10_url,
    'power_of_10_athlete_id', v_athlete.power_of_10_athlete_id,
    'power_of_10_linked_at', v_athlete.power_of_10_linked_at
  );
end;
$$;

revoke execute on function public.save_my_power_of_10_profile(text) from public, anon, authenticated;
grant execute on function public.save_my_power_of_10_profile(text) to authenticated;
