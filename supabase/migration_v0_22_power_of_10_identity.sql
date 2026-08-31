-- Paceletics database migration v0.22
-- Parse and retain the Power of 10 athlete identity from the stored profile URL.

alter table public.athletes
  add column if not exists power_of_10_athlete_id text,
  add column if not exists power_of_10_linked_at timestamptz;

create or replace function public.extract_power_of_10_athlete_id(p_url text)
returns text
language sql
immutable
strict
security invoker
set search_path = ''
as $$
  select (regexp_match(
    trim(p_url),
    '(?i)^https://(?:www[.])?powerof10[.]uk/Home/Athlete/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})(?:[/?#].*)?$'
  ))[1];
$$;

create or replace function public.sync_power_of_10_identity()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_id text;
begin
  if new.power_of_10_url is null or trim(new.power_of_10_url) = '' then
    new.power_of_10_url := null;
    new.power_of_10_athlete_id := null;
    new.power_of_10_linked_at := null;
    return new;
  end if;

  v_id := public.extract_power_of_10_athlete_id(new.power_of_10_url);
  if v_id is null then
    raise exception 'Use a valid Power of 10 athlete profile URL.';
  end if;

  new.power_of_10_url := trim(new.power_of_10_url);
  new.power_of_10_athlete_id := lower(v_id);

  if tg_op = 'INSERT'
     or old.power_of_10_url is distinct from new.power_of_10_url
     or old.power_of_10_athlete_id is distinct from lower(v_id) then
    new.power_of_10_linked_at := now();
  end if;

  return new;
end;
$$;

drop trigger if exists athletes_sync_power_of_10_identity on public.athletes;
create trigger athletes_sync_power_of_10_identity
before insert or update of power_of_10_url on public.athletes
for each row execute function public.sync_power_of_10_identity();

-- Backfill any URLs saved before this migration.
update public.athletes
set power_of_10_url = power_of_10_url
where power_of_10_url is not null;

comment on column public.athletes.power_of_10_athlete_id is
  'Power of 10 athlete identifier parsed from power_of_10_url.';
comment on column public.athletes.power_of_10_linked_at is
  'Time the current Power of 10 profile link was connected.';

-- These helpers are internal trigger plumbing, not Data API endpoints.
revoke execute on function public.extract_power_of_10_athlete_id(text) from public, anon, authenticated;
revoke execute on function public.sync_power_of_10_identity() from public, anon, authenticated;
