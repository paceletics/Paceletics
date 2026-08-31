-- Paceletics v0.19
-- Allow a linked Athlete account to create a training session only for itself.

create or replace function public.create_my_training_session(
  p_title text,
  p_event text,
  p_training_goal text,
  p_main_set text,
  p_recovery text,
  p_effort smallint,
  p_notes text default null,
  p_scheduled_date date default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_athlete_id uuid;
  v_session_id uuid;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in.';
  end if;

  if not exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'athlete'
  ) then
    raise exception 'Only Athlete accounts can create their own sessions.';
  end if;

  select a.id into v_athlete_id
  from public.athletes a
  where a.linked_user_id = auth.uid()
    and a.is_active = true
  order by a.created_at
  limit 1;

  if v_athlete_id is null then
    raise exception 'Your Athlete account is not linked to an active athlete profile.';
  end if;

  if nullif(trim(coalesce(p_title,'')),'') is null or length(trim(p_title)) > 120 then
    raise exception 'Enter a session name up to 120 characters.';
  end if;

  if p_event not in ('100m','200m','400m','800m','1500m') then
    raise exception 'Choose a valid event.';
  end if;

  if p_training_goal not in ('acceleration','max_velocity','speed_endurance','special_endurance','race_modelling') then
    raise exception 'Choose a valid training goal.';
  end if;

  if nullif(trim(coalesce(p_main_set,'')),'') is null or length(trim(p_main_set)) > 2000 then
    raise exception 'Enter a valid main set.';
  end if;

  if p_recovery is not null and length(trim(p_recovery)) > 500 then
    raise exception 'Recovery description is too long.';
  end if;

  if p_notes is not null and length(trim(p_notes)) > 4000 then
    raise exception 'Notes are too long.';
  end if;

  if p_effort is null or p_effort < 70 or p_effort > 110 then
    raise exception 'Effort must be between 70 and 110 percent.';
  end if;

  insert into public.sessions (
    created_by,title,event,main_set,recovery,effort,notes,scheduled_date,training_goal
  ) values (
    auth.uid(),trim(p_title),p_event,trim(p_main_set),nullif(trim(coalesce(p_recovery,'')),''),
    p_effort,nullif(trim(coalesce(p_notes,'')),''),p_scheduled_date,p_training_goal
  ) returning id into v_session_id;

  insert into public.assignments (session_id,athlete_id,assigned_by,status)
  values (v_session_id,v_athlete_id,auth.uid(),'planned');

  return v_session_id;
end;
$$;

revoke all on function public.create_my_training_session(text,text,text,text,text,smallint,text,date) from public;
revoke all on function public.create_my_training_session(text,text,text,text,text,smallint,text,date) from anon;
grant execute on function public.create_my_training_session(text,text,text,text,text,smallint,text,date) to authenticated;

-- Include the session creator type so the Athlete UI can clearly distinguish
-- Coach/Club assignments from sessions the Athlete created personally.
create or replace function public.get_my_athlete_dashboard()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_athlete public.athletes%rowtype;
  v_club_name text;
  v_data jsonb;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in.';
  end if;

  if not exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'athlete'
  ) then
    raise exception 'This view is only available to Athlete accounts.';
  end if;

  select a.* into v_athlete
  from public.athletes a
  where a.linked_user_id = auth.uid()
    and a.is_active = true
  order by a.created_at
  limit 1;

  if not found then
    return jsonb_build_object(
      'linked',false,'athlete',null,'club_name',null,'pbs','[]'::jsonb,'training','[]'::jsonb
    );
  end if;

  select c.name into v_club_name
  from public.clubs c
  where c.owner_user_id = v_athlete.owner_user_id
  limit 1;

  select jsonb_build_object(
    'linked',true,
    'club_name',v_club_name,
    'athlete',jsonb_build_object(
      'id',v_athlete.id,'full_name',v_athlete.full_name,'group_name',v_athlete.group_name,'primary_event',v_athlete.primary_event
    ),
    'pbs',coalesce((
      select jsonb_agg(jsonb_build_object(
        'event',pb.event,'time_seconds',pb.time_seconds,'achieved_on',pb.achieved_on
      ) order by pb.event)
      from public.personal_bests pb where pb.athlete_id=v_athlete.id
    ),'[]'::jsonb),
    'training',coalesce((
      select jsonb_agg(q.row_data order by q.sort_date desc)
      from (
        select
          coalesce(r.completed_at,s.scheduled_date::timestamptz,x.created_at) as sort_date,
          jsonb_build_object(
            'assignment_id',x.id,
            'status',x.status,
            'session_id',s.id,
            'title',s.title,
            'event',s.event,
            'training_goal',s.training_goal,
            'main_set',s.main_set,
            'recovery',s.recovery,
            'effort',s.effort,
            'scheduled_date',s.scheduled_date,
            'notes',s.notes,
            'session_source',case when s.created_by=auth.uid() then 'self' else coalesce(cp.role,'assigned') end,
            'result',case when r.id is null then null else jsonb_build_object(
              'id',r.id,'rep_times',r.rep_times,'rpe',r.rpe,'notes',r.notes,'completed_at',r.completed_at
            ) end
          ) as row_data
        from public.assignments x
        join public.sessions s on s.id=x.session_id
        left join public.profiles cp on cp.id=s.created_by
        left join public.results r on r.assignment_id=x.id
        where x.athlete_id=v_athlete.id
        order by sort_date desc
        limit 100
      ) q
    ),'[]'::jsonb)
  ) into v_data;

  return v_data;
end;
$$;

revoke all on function public.get_my_athlete_dashboard() from public;
revoke all on function public.get_my_athlete_dashboard() from anon;
grant execute on function public.get_my_athlete_dashboard() to authenticated;
