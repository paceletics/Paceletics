-- Paceletics Beta 1.1: hurdle events, PBs and secure session goals.

alter table public.athletes drop constraint if exists athletes_primary_event_check;
alter table public.athletes add constraint athletes_primary_event_check check (primary_event = any (array['100m','200m','400m','800m','1500m','60mH','80mH','100mH','110mH','300mH','400mH']::text[]));

alter table public.personal_bests drop constraint if exists personal_bests_event_check;
alter table public.personal_bests add constraint personal_bests_event_check check (event = any (array['100m','200m','400m','800m','1500m','60mH','80mH','100mH','110mH','300mH','400mH']::text[]));

alter table public.sessions drop constraint if exists sessions_event_check;
alter table public.sessions add constraint sessions_event_check check (event = any (array['100m','200m','400m','800m','1500m','60mH','80mH','100mH','110mH','300mH','400mH']::text[]));

alter table public.sessions drop constraint if exists sessions_training_goal_check;
alter table public.sessions add constraint sessions_training_goal_check check (
  training_goal is null or training_goal = any (array[
    'acceleration','max_velocity','speed_endurance','special_endurance','race_modelling',
    'hurdle_technique','hurdle_one','three_step_rhythm','hurdle_speed','hurdle_rhythm','alternate_leg'
  ]::text[])
);

create or replace function public.save_my_personal_best(p_event text,p_time_seconds numeric,p_achieved_on date default null)
returns jsonb language plpgsql security definer set search_path='public' as $$
declare v_athlete public.athletes%rowtype; v_pb public.personal_bests%rowtype; v_event text;
begin
  if auth.uid() is null then raise exception 'You must be signed in.'; end if;
  if not exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='athlete') then raise exception 'Only Athlete accounts can update their own PBs.'; end if;
  select a.* into v_athlete from public.athletes a where a.linked_user_id=auth.uid() and coalesce(a.is_active,true)=true order by a.created_at limit 1;
  if not found then raise exception 'Your Athlete account is not linked to an active athlete profile.'; end if;
  v_event:=trim(coalesce(p_event,''));
  if v_event not in ('100m','200m','400m','800m','1500m','60mH','80mH','100mH','110mH','300mH','400mH') then raise exception 'Choose a supported event.'; end if;
  if p_time_seconds is null or p_time_seconds<=0 or p_time_seconds>3600 then raise exception 'Enter a valid PB time in seconds.'; end if;
  if p_achieved_on is not null and p_achieved_on>current_date then raise exception 'PB date cannot be in the future.'; end if;
  insert into public.personal_bests(athlete_id,event,time_seconds,achieved_on) values(v_athlete.id,v_event,p_time_seconds,p_achieved_on)
  on conflict(athlete_id,event) do update set time_seconds=excluded.time_seconds,achieved_on=excluded.achieved_on returning * into v_pb;
  return jsonb_build_object('athlete_id',v_athlete.id,'event',v_pb.event,'time_seconds',v_pb.time_seconds,'achieved_on',v_pb.achieved_on,'status','saved');
end;$$;
revoke all on function public.save_my_personal_best(text,numeric,date) from public,anon;
grant execute on function public.save_my_personal_best(text,numeric,date) to authenticated;

create or replace function public.create_my_training_session(p_title text,p_event text,p_training_goal text,p_main_set text,p_recovery text,p_effort smallint,p_notes text default null,p_scheduled_date date default null)
returns uuid language plpgsql security definer set search_path='public' as $$
declare v_athlete_id uuid;v_session_id uuid;v_hurdle boolean;
begin
  if auth.uid() is null then raise exception 'You must be signed in.'; end if;
  if not exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='athlete') then raise exception 'Only Athlete accounts can create their own sessions.'; end if;
  select a.id into v_athlete_id from public.athletes a where a.linked_user_id=auth.uid() and a.is_active=true order by a.created_at limit 1;
  if v_athlete_id is null then raise exception 'Your Athlete account is not linked to an active athlete profile.'; end if;
  if nullif(trim(coalesce(p_title,'')),'') is null or length(trim(p_title))>120 then raise exception 'Enter a session name up to 120 characters.'; end if;
  if p_event not in ('100m','200m','400m','800m','1500m','60mH','80mH','100mH','110mH','300mH','400mH') then raise exception 'Choose a valid event.'; end if;
  v_hurdle:=p_event in ('60mH','80mH','100mH','110mH','300mH','400mH');
  if (not v_hurdle and p_training_goal not in ('acceleration','max_velocity','speed_endurance','special_endurance','race_modelling')) or
     (v_hurdle and p_training_goal not in ('hurdle_technique','hurdle_one','three_step_rhythm','hurdle_speed','speed_endurance','hurdle_rhythm','race_modelling','alternate_leg')) then raise exception 'Choose a valid training goal for this event.'; end if;
  if nullif(trim(coalesce(p_main_set,'')),'') is null or length(trim(p_main_set))>2000 then raise exception 'Enter a valid main set.'; end if;
  if p_recovery is not null and length(trim(p_recovery))>500 then raise exception 'Recovery description is too long.'; end if;
  if p_notes is not null and length(trim(p_notes))>4000 then raise exception 'Notes are too long.'; end if;
  if p_effort is null or p_effort<70 or p_effort>110 then raise exception 'Effort must be between 70 and 110 percent.'; end if;
  insert into public.sessions(created_by,title,event,main_set,recovery,effort,notes,scheduled_date,training_goal)
  values(auth.uid(),trim(p_title),p_event,trim(p_main_set),nullif(trim(coalesce(p_recovery,'')),''),p_effort,nullif(trim(coalesce(p_notes,'')),''),p_scheduled_date,p_training_goal) returning id into v_session_id;
  insert into public.assignments(session_id,athlete_id,assigned_by,status) values(v_session_id,v_athlete_id,auth.uid(),'planned');
  return v_session_id;
end;$$;
revoke all on function public.create_my_training_session(text,text,text,text,text,smallint,text,date) from public,anon;
grant execute on function public.create_my_training_session(text,text,text,text,text,smallint,text,date) to authenticated;

create or replace function public.create_coach_session(p_title text,p_event text,p_training_goal text,p_main_set text,p_recovery text,p_effort smallint,p_notes text,p_scheduled_date date,p_athlete_ids uuid[])
returns uuid language plpgsql security definer set search_path='public' as $$
declare v_session_id uuid;v_goal_label text;v_notes text;v_hurdle boolean;
begin
  if auth.uid() is null then raise exception 'You must be signed in.'; end if;
  if not exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='coach') then raise exception 'Only Coach accounts can use this session builder.'; end if;
  if nullif(trim(coalesce(p_title,'')),'') is null or length(trim(p_title))>120 then raise exception 'Enter a session name up to 120 characters.'; end if;
  if p_event not in ('100m','200m','400m','800m','1500m','60mH','80mH','100mH','110mH','300mH','400mH') then raise exception 'Choose a valid event.'; end if;
  v_hurdle:=p_event in ('60mH','80mH','100mH','110mH','300mH','400mH');
  if (not v_hurdle and p_training_goal not in ('acceleration','max_velocity','speed_endurance','special_endurance','race_modelling')) or
     (v_hurdle and p_training_goal not in ('hurdle_technique','hurdle_one','three_step_rhythm','hurdle_speed','speed_endurance','hurdle_rhythm','race_modelling','alternate_leg')) then raise exception 'Choose a valid training goal for this event.'; end if;
  if nullif(trim(coalesce(p_main_set,'')),'') is null or length(trim(p_main_set))>2000 then raise exception 'Enter a valid main set.'; end if;
  if p_recovery is not null and length(trim(p_recovery))>500 then raise exception 'Recovery description is too long.'; end if;
  if p_notes is not null and length(trim(p_notes))>4000 then raise exception 'Notes are too long.'; end if;
  if p_effort is null or p_effort<70 or p_effort>110 then raise exception 'Effort must be between 70 and 110 percent.'; end if;
  if p_athlete_ids is null or cardinality(p_athlete_ids)=0 then raise exception 'Choose at least one athlete.'; end if;
  if exists(select 1 from unnest(p_athlete_ids) requested(athlete_id) where not exists(
    select 1 from public.club_coaches cc join public.squad_coaches sc on sc.coach_id=cc.id join public.squad_athletes sa on sa.squad_id=sc.squad_id
    where cc.linked_user_id=auth.uid() and cc.status='linked' and sa.athlete_id=requested.athlete_id)) then raise exception 'One or more selected athletes are outside your assigned squads.'; end if;
  v_goal_label:=case p_training_goal when 'acceleration' then 'Acceleration' when 'max_velocity' then 'Max velocity' when 'speed_endurance' then 'Speed endurance' when 'special_endurance' then 'Special endurance' when 'race_modelling' then 'Race modelling' when 'hurdle_technique' then 'Lead/trail leg technique' when 'hurdle_one' then 'Acceleration to hurdle 1' when 'three_step_rhythm' then '3-step rhythm' when 'hurdle_speed' then 'Hurdle speed' when 'hurdle_rhythm' then '400mH rhythm' when 'alternate_leg' then 'Alternate-leg work' else p_training_goal end;
  v_notes:=concat_ws(E'\n',nullif(trim(coalesce(p_notes,'')),''),'Training goal: '||v_goal_label);
  insert into public.sessions(created_by,title,event,main_set,recovery,effort,notes,scheduled_date,training_goal)
  values(auth.uid(),trim(p_title),p_event,trim(p_main_set),nullif(trim(coalesce(p_recovery,'')),''),p_effort,v_notes,p_scheduled_date,p_training_goal) returning id into v_session_id;
  insert into public.assignments(session_id,athlete_id,assigned_by,status) select v_session_id,x.athlete_id,auth.uid(),'planned' from(select distinct unnest(p_athlete_ids) as athlete_id)x;
  return v_session_id;
end;$$;
revoke all on function public.create_coach_session(text,text,text,text,text,smallint,text,date,uuid[]) from public,anon;
grant execute on function public.create_coach_session(text,text,text,text,text,smallint,text,date,uuid[]) to authenticated;
