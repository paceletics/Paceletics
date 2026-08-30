-- Paceletics migration v0.14
-- Secure Coach session creation and squad-scoped athlete assignment.

-- Context for the Coach Session Builder: only athletes in squads assigned to
-- the currently signed-in linked Coach account, plus the PBs needed for target previews.
create or replace function public.get_my_coach_session_context()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_data jsonb;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in.';
  end if;

  if not exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'coach'
  ) then
    raise exception 'This view is only available to Coach accounts.';
  end if;

  select jsonb_build_object(
    'athletes', coalesce((
      select jsonb_agg(x.row_data order by x.full_name)
      from (
        select distinct on (a.id)
          a.full_name,
          jsonb_build_object(
            'id', a.id,
            'full_name', a.full_name,
            'group_name', a.group_name,
            'primary_event', a.primary_event,
            'squads', (
              select coalesce(jsonb_agg(distinct s2.name order by s2.name), '[]'::jsonb)
              from public.club_coaches cc2
              join public.squad_coaches sc2 on sc2.coach_id = cc2.id
              join public.squads s2 on s2.id = sc2.squad_id
              join public.squad_athletes sa2 on sa2.squad_id = s2.id
              where cc2.linked_user_id = auth.uid()
                and cc2.status = 'linked'
                and sa2.athlete_id = a.id
            )
          ) as row_data
        from public.club_coaches cc
        join public.squad_coaches sc on sc.coach_id = cc.id
        join public.squad_athletes sa on sa.squad_id = sc.squad_id
        join public.athletes a on a.id = sa.athlete_id
        where cc.linked_user_id = auth.uid()
          and cc.status = 'linked'
        order by a.id, a.full_name
      ) x
    ), '[]'::jsonb),
    'pbs', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'athlete_id', pb.athlete_id,
          'event', pb.event,
          'time_seconds', pb.time_seconds,
          'achieved_on', pb.achieved_on
        )
        order by pb.athlete_id, pb.event
      )
      from public.personal_bests pb
      where exists (
        select 1
        from public.club_coaches cc
        join public.squad_coaches sc on sc.coach_id = cc.id
        join public.squad_athletes sa on sa.squad_id = sc.squad_id
        where cc.linked_user_id = auth.uid()
          and cc.status = 'linked'
          and sa.athlete_id = pb.athlete_id
      )
    ), '[]'::jsonb)
  ) into v_data;

  return v_data;
end;
$$;

-- Creates one session and its athlete assignments atomically.
-- Every requested athlete must be in a squad assigned to the current Coach.
create or replace function public.create_coach_session(
  p_title text,
  p_event text,
  p_training_goal text,
  p_main_set text,
  p_recovery text,
  p_effort smallint,
  p_notes text,
  p_scheduled_date date,
  p_athlete_ids uuid[]
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_session_id uuid;
  v_goal_label text;
  v_notes text;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in.';
  end if;

  if not exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'coach'
  ) then
    raise exception 'Only Coach accounts can use this session builder.';
  end if;

  if nullif(trim(coalesce(p_title, '')), '') is null then
    raise exception 'Enter a session name.';
  end if;

  if p_event not in ('100m','200m','400m','800m','1500m') then
    raise exception 'Choose a valid event.';
  end if;

  if p_training_goal not in ('acceleration','max_velocity','speed_endurance','special_endurance','race_modelling') then
    raise exception 'Choose a valid training goal.';
  end if;

  if nullif(trim(coalesce(p_main_set, '')), '') is null then
    raise exception 'Choose the main set.';
  end if;

  if p_effort is null or p_effort < 70 or p_effort > 110 then
    raise exception 'Effort must be between 70 and 110 percent.';
  end if;

  if p_athlete_ids is null or cardinality(p_athlete_ids) = 0 then
    raise exception 'Choose at least one athlete.';
  end if;

  -- Reject the request if even one athlete is outside the Coach's assigned squads.
  if exists (
    select 1
    from unnest(p_athlete_ids) requested(athlete_id)
    where not exists (
      select 1
      from public.club_coaches cc
      join public.squad_coaches sc on sc.coach_id = cc.id
      join public.squad_athletes sa on sa.squad_id = sc.squad_id
      where cc.linked_user_id = auth.uid()
        and cc.status = 'linked'
        and sa.athlete_id = requested.athlete_id
    )
  ) then
    raise exception 'One or more selected athletes are outside your assigned squads.';
  end if;

  v_goal_label := case p_training_goal
    when 'acceleration' then 'Acceleration'
    when 'max_velocity' then 'Max velocity'
    when 'speed_endurance' then 'Speed endurance'
    when 'special_endurance' then 'Special endurance'
    when 'race_modelling' then 'Race modelling'
    else p_training_goal
  end;

  v_notes := concat_ws(E'\n', nullif(trim(coalesce(p_notes,'')), ''), 'Training goal: ' || v_goal_label);

  insert into public.sessions (
    created_by, title, event, main_set, recovery, effort, notes, scheduled_date
  ) values (
    auth.uid(), trim(p_title), p_event, trim(p_main_set), nullif(trim(coalesce(p_recovery,'')), ''),
    p_effort, v_notes, p_scheduled_date
  )
  returning id into v_session_id;

  insert into public.assignments (session_id, athlete_id, assigned_by, status)
  select v_session_id, x.athlete_id, auth.uid(), 'planned'
  from (
    select distinct unnest(p_athlete_ids) as athlete_id
  ) x;

  return v_session_id;
end;
$$;

-- Tighten direct assignment creation. Owners can continue to use the existing
-- Club/owner builder directly. Linked Coaches use create_coach_session(), which
-- performs its own squad checks as a security-definer function.
drop policy if exists "assignments_manage_assigner" on public.assignments;
drop policy if exists "assignments_insert_owner" on public.assignments;
drop policy if exists "assignments_update_assigner" on public.assignments;
drop policy if exists "assignments_delete_assigner" on public.assignments;

create policy "assignments_insert_owner" on public.assignments
for insert
with check (
  assigned_by = auth.uid()
  and exists (
    select 1 from public.athletes a
    where a.id = assignments.athlete_id
      and a.owner_user_id = auth.uid()
  )
);

create policy "assignments_update_assigner" on public.assignments
for update
using (assigned_by = auth.uid())
with check (assigned_by = auth.uid());

create policy "assignments_delete_assigner" on public.assignments
for delete
using (assigned_by = auth.uid());

revoke all on function public.get_my_coach_session_context() from public;
grant execute on function public.get_my_coach_session_context() to authenticated;

revoke all on function public.create_coach_session(text,text,text,text,text,smallint,text,date,uuid[]) from public;
grant execute on function public.create_coach_session(text,text,text,text,text,smallint,text,date,uuid[]) to authenticated;
