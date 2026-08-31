-- Paceletics database migration v0.26 (development branch only)
-- Extend personal bests so a future authorised Power of 10 feed can populate every event type.
-- DO NOT apply to production until the feature is approved for release.

alter table public.personal_bests
  alter column time_seconds drop not null,
  add column if not exists performance_value numeric,
  add column if not exists performance_unit text,
  add column if not exists performance_display text,
  add column if not exists event_category text,
  add column if not exists power_of_10_updated_at timestamptz;

update public.personal_bests
set performance_value = coalesce(performance_value, time_seconds),
    performance_unit = coalesce(performance_unit, case when time_seconds is not null then 'seconds' end),
    performance_display = coalesce(
      performance_display,
      case when time_seconds is not null then trim(to_char(time_seconds, 'FM999999990.00')) end
    )
where performance_value is null
   or performance_unit is null
   or performance_display is null;

comment on column public.personal_bests.performance_value is
  'Numeric performance value for any event: seconds, metres, points, etc.';
comment on column public.personal_bests.performance_unit is
  'Unit for performance_value, e.g. seconds, metres or points.';
comment on column public.personal_bests.performance_display is
  'Display-ready PB text retained from the authorised source, e.g. 11.62, 6.21m or 3412.';
comment on column public.personal_bests.event_category is
  'Broad event group such as Sprints, Endurance, Hurdles, Jumps, Throws or Combined Events.';
comment on column public.personal_bests.power_of_10_updated_at is
  'Time this PB was last refreshed from an authorised Power of 10 data source.';

create or replace function public.replace_power_of_10_personal_bests(
  p_athlete_id uuid,
  p_profile_url text,
  p_pbs jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_athlete public.athletes%rowtype;
  v_item jsonb;
  v_event text;
  v_category text;
  v_unit text;
  v_display text;
  v_value numeric;
  v_time numeric;
  v_date date;
  v_count integer := 0;
begin
  select a.* into v_athlete
  from public.athletes a
  where a.id = p_athlete_id
    and coalesce(a.is_active, true) = true;

  if not found then
    raise exception 'Athlete profile was not found.';
  end if;

  if v_athlete.power_of_10_url is null
     or trim(v_athlete.power_of_10_url) <> trim(coalesce(p_profile_url, '')) then
    raise exception 'Power of 10 profile URL does not match the linked athlete profile.';
  end if;

  if p_pbs is null or jsonb_typeof(p_pbs) <> 'array' then
    raise exception 'Power of 10 PB payload must be an array.';
  end if;

  -- Only remove PBs previously supplied by the authorised Power of 10 import.
  -- Manual Paceletics PBs for events absent from the feed remain untouched.
  delete from public.personal_bests pb
  where pb.athlete_id = v_athlete.id
    and pb.source = 'power_of_10_import';

  for v_item in select value from jsonb_array_elements(p_pbs)
  loop
    v_event := nullif(trim(coalesce(v_item->>'event', '')), '');
    v_category := nullif(trim(coalesce(v_item->>'category', '')), '');
    v_unit := lower(nullif(trim(coalesce(v_item->>'unit', '')), ''));
    v_display := nullif(trim(coalesce(v_item->>'display', '')), '');

    if v_event is null then
      raise exception 'Each Power of 10 PB requires an event name.';
    end if;

    begin
      v_value := (v_item->>'value')::numeric;
    exception when others then
      raise exception 'PB value for % is invalid.', v_event;
    end;

    if v_value is null or v_value < 0 then
      raise exception 'PB value for % is invalid.', v_event;
    end if;

    if v_unit not in ('seconds', 'metres', 'points') then
      raise exception 'PB unit for % must be seconds, metres or points.', v_event;
    end if;

    v_date := null;
    if nullif(trim(coalesce(v_item->>'achieved_on', '')), '') is not null then
      begin
        v_date := (v_item->>'achieved_on')::date;
      exception when others then
        raise exception 'PB date for % is invalid.', v_event;
      end;
    end if;

    v_time := case when v_unit = 'seconds' then v_value else null end;
    if v_display is null then
      v_display := case
        when v_unit = 'seconds' then trim(to_char(v_value, 'FM999999990.00'))
        when v_unit = 'metres' then trim(to_char(v_value, 'FM999999990.00')) || 'm'
        when v_unit = 'points' then trim(to_char(v_value, 'FM999999990')) || ' pts'
      end;
    end if;

    insert into public.personal_bests (
      athlete_id,
      event,
      time_seconds,
      achieved_on,
      source,
      source_reference,
      source_confirmed_at,
      performance_value,
      performance_unit,
      performance_display,
      event_category,
      power_of_10_updated_at
    ) values (
      v_athlete.id,
      v_event,
      v_time,
      v_date,
      'power_of_10_import',
      v_athlete.power_of_10_url,
      now(),
      v_value,
      v_unit,
      v_display,
      v_category,
      now()
    )
    on conflict (athlete_id, event)
    do update set
      time_seconds = excluded.time_seconds,
      achieved_on = excluded.achieved_on,
      source = excluded.source,
      source_reference = excluded.source_reference,
      source_confirmed_at = excluded.source_confirmed_at,
      performance_value = excluded.performance_value,
      performance_unit = excluded.performance_unit,
      performance_display = excluded.performance_display,
      event_category = excluded.event_category,
      power_of_10_updated_at = excluded.power_of_10_updated_at;

    v_count := v_count + 1;
  end loop;

  return jsonb_build_object(
    'status', 'imported',
    'athlete_id', v_athlete.id,
    'power_of_10_url', v_athlete.power_of_10_url,
    'count', v_count
  );
end;
$$;

-- The import function is deliberately backend-only. The browser cannot call it.
revoke execute on function public.replace_power_of_10_personal_bests(uuid,text,jsonb)
from public, anon, authenticated;
grant execute on function public.replace_power_of_10_personal_bests(uuid,text,jsonb)
to service_role;
