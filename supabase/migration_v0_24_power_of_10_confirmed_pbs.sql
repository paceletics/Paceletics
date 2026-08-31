-- Paceletics database migration v0.24
-- Track PB source and allow linked athletes to confirm PBs against their Power of 10 profile.

alter table public.personal_bests
  add column if not exists source text not null default 'paceletics_manual',
  add column if not exists source_reference text,
  add column if not exists source_confirmed_at timestamptz;

comment on column public.personal_bests.source is
  'Origin of the PB, for example paceletics_manual or power_of_10_self_confirmed.';
comment on column public.personal_bests.source_reference is
  'Optional source reference such as the athlete Power of 10 profile URL.';
comment on column public.personal_bests.source_confirmed_at is
  'Time the athlete confirmed the PB against the stated source.';

create or replace function public.save_my_power_of_10_confirmed_pbs(p_pbs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_athlete public.athletes%rowtype;
  v_item jsonb;
  v_event text;
  v_time numeric;
  v_date date;
  v_saved jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then raise exception 'You must be signed in.'; end if;
  if not exists (select 1 from public.profiles p where p.id=auth.uid() and p.role='athlete') then
    raise exception 'Only Athlete accounts can confirm Power of 10 PBs.';
  end if;

  select a.* into v_athlete from public.athletes a
  where a.linked_user_id=auth.uid() and coalesce(a.is_active,true)=true
  order by a.created_at limit 1;
  if not found then raise exception 'Your Athlete account is not linked to an active athlete profile.'; end if;
  if v_athlete.power_of_10_url is null or v_athlete.power_of_10_athlete_id is null then
    raise exception 'Link your Power of 10 athlete profile first.';
  end if;

  if p_pbs is null or jsonb_typeof(p_pbs) <> 'array' then raise exception 'PB data must be an array.'; end if;
  if jsonb_array_length(p_pbs) < 1 or jsonb_array_length(p_pbs) > 20 then raise exception 'Enter between 1 and 20 PBs.'; end if;

  for v_item in select value from jsonb_array_elements(p_pbs) loop
    v_event := trim(coalesce(v_item->>'event',''));
    if v_event not in ('100m','200m','400m','800m','1500m','60mH','80mH','100mH','110mH','300mH','400mH') then
      raise exception 'Choose a supported event.';
    end if;
    begin v_time := (v_item->>'time_seconds')::numeric;
    exception when others then raise exception '% PB must be a valid time in seconds.', v_event; end;
    if v_time <= 0 or v_time > 3600 then raise exception '% PB must be a valid time in seconds.', v_event; end if;

    v_date := null;
    if nullif(trim(coalesce(v_item->>'achieved_on','')),'') is not null then
      begin v_date := (v_item->>'achieved_on')::date;
      exception when others then raise exception '% PB date is invalid.', v_event; end;
      if v_date > current_date then raise exception '% PB date cannot be in the future.', v_event; end if;
    end if;

    insert into public.personal_bests(athlete_id,event,time_seconds,achieved_on,source,source_reference,source_confirmed_at)
    values(v_athlete.id,v_event,v_time,v_date,'power_of_10_self_confirmed',v_athlete.power_of_10_url,now())
    on conflict(athlete_id,event) do update set
      time_seconds=excluded.time_seconds,
      achieved_on=excluded.achieved_on,
      source=excluded.source,
      source_reference=excluded.source_reference,
      source_confirmed_at=excluded.source_confirmed_at;

    v_saved := v_saved || jsonb_build_array(jsonb_build_object(
      'event',v_event,'time_seconds',v_time,'achieved_on',v_date,'source','power_of_10_self_confirmed'
    ));
  end loop;

  return jsonb_build_object('status','saved','count',jsonb_array_length(v_saved),'power_of_10_url',v_athlete.power_of_10_url,'pbs',v_saved);
end;
$$;

revoke execute on function public.save_my_power_of_10_confirmed_pbs(jsonb) from public, anon, authenticated;
grant execute on function public.save_my_power_of_10_confirmed_pbs(jsonb) to authenticated;

create or replace function public.save_my_personal_best(p_event text, p_time_seconds numeric, p_achieved_on date default null::date)
returns jsonb
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_athlete public.athletes%rowtype;
  v_pb public.personal_bests%rowtype;
  v_event text;
begin
  if auth.uid() is null then raise exception 'You must be signed in.'; end if;
  if not exists (select 1 from public.profiles p where p.id=auth.uid() and p.role='athlete') then
    raise exception 'Only Athlete accounts can update their own PBs.';
  end if;
  select a.* into v_athlete from public.athletes a
  where a.linked_user_id=auth.uid() and coalesce(a.is_active,true)=true
  order by a.created_at limit 1;
  if not found then raise exception 'Your Athlete account is not linked to an active athlete profile.'; end if;
  v_event := trim(coalesce(p_event,''));
  if v_event not in ('100m','200m','400m','800m','1500m','60mH','80mH','100mH','110mH','300mH','400mH') then raise exception 'Choose a supported event.'; end if;
  if p_time_seconds is null or p_time_seconds <= 0 or p_time_seconds > 3600 then raise exception 'Enter a valid PB time in seconds.'; end if;
  if p_achieved_on is not null and p_achieved_on > current_date then raise exception 'PB date cannot be in the future.'; end if;

  insert into public.personal_bests(athlete_id,event,time_seconds,achieved_on,source,source_reference,source_confirmed_at)
  values(v_athlete.id,v_event,p_time_seconds,p_achieved_on,'paceletics_manual',null,null)
  on conflict(athlete_id,event) do update set
    time_seconds=excluded.time_seconds,
    achieved_on=excluded.achieved_on,
    source='paceletics_manual',
    source_reference=null,
    source_confirmed_at=null
  returning * into v_pb;

  return jsonb_build_object('athlete_id',v_athlete.id,'event',v_pb.event,'time_seconds',v_pb.time_seconds,'achieved_on',v_pb.achieved_on,'status','saved','source',v_pb.source);
end;
$$;
