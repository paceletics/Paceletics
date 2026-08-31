-- Paceletics migration v0.15
-- Secure Coach result entry for athletes in assigned squads.

create or replace function public.get_my_coach_result_context()
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
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role = 'coach'
  ) then
    raise exception 'This view is only available to Coach accounts.';
  end if;

  select jsonb_build_object(
    'assignments', coalesce((
      select jsonb_agg(q.row_data order by q.status_order, q.sort_date desc, q.athlete_name)
      from (
        select
          case when x.status = 'planned' then 0 else 1 end as status_order,
          coalesce(r.completed_at, s.scheduled_date::timestamptz, x.created_at) as sort_date,
          a.full_name as athlete_name,
          jsonb_build_object(
            'assignment_id', x.id,
            'status', x.status,
            'athlete_id', a.id,
            'athlete_name', a.full_name,
            'athlete_group', a.group_name,
            'athlete_primary_event', a.primary_event,
            'session_id', s.id,
            'title', s.title,
            'event', s.event,
            'main_set', s.main_set,
            'recovery', s.recovery,
            'effort', s.effort,
            'scheduled_date', s.scheduled_date,
            'result', case
              when r.id is null then null
              else jsonb_build_object(
                'id', r.id,
                'rep_times', r.rep_times,
                'rpe', r.rpe,
                'notes', r.notes,
                'completed_at', r.completed_at
              )
            end
          ) as row_data
        from public.assignments x
        join public.athletes a on a.id = x.athlete_id
        join public.sessions s on s.id = x.session_id
        left join public.results r on r.assignment_id = x.id
        where x.status in ('planned','completed')
          and exists (
            select 1
            from public.club_coaches cc
            join public.squad_coaches sc on sc.coach_id = cc.id
            join public.squad_athletes sa on sa.squad_id = sc.squad_id
            where cc.linked_user_id = auth.uid()
              and cc.status = 'linked'
              and sa.athlete_id = a.id
          )
      ) q
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

create or replace function public.save_coach_result(
  p_assignment_id uuid,
  p_rep_times jsonb,
  p_rpe smallint,
  p_notes text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_assignment public.assignments%rowtype;
  v_result public.results%rowtype;
  v_rep_text text;
  v_rep_num numeric;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in.';
  end if;

  if not exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role = 'coach'
  ) then
    raise exception 'Only Coach accounts can log Coach results.';
  end if;

  select x.*
  into v_assignment
  from public.assignments x
  where x.id = p_assignment_id;

  if not found then
    raise exception 'The selected assignment could not be found.';
  end if;

  if v_assignment.status = 'skipped' then
    raise exception 'A skipped assignment cannot be completed with a result.';
  end if;

  if not exists (
    select 1
    from public.club_coaches cc
    join public.squad_coaches sc on sc.coach_id = cc.id
    join public.squad_athletes sa on sa.squad_id = sc.squad_id
    where cc.linked_user_id = auth.uid()
      and cc.status = 'linked'
      and sa.athlete_id = v_assignment.athlete_id
  ) then
    raise exception 'You do not have access to this athlete.';
  end if;

  if p_rep_times is null or jsonb_typeof(p_rep_times) <> 'array' then
    raise exception 'Enter at least one valid rep time.';
  end if;

  if jsonb_array_length(p_rep_times) < 1 or jsonb_array_length(p_rep_times) > 30 then
    raise exception 'Enter between 1 and 30 rep times.';
  end if;

  for v_rep_text in
    select value from jsonb_array_elements_text(p_rep_times)
  loop
    begin
      v_rep_num := v_rep_text::numeric;
    exception when others then
      raise exception 'Every rep time must be a positive number.';
    end;

    if v_rep_num <= 0 then
      raise exception 'Every rep time must be a positive number.';
    end if;
  end loop;

  if p_rpe is null or p_rpe < 1 or p_rpe > 10 then
    raise exception 'RPE must be between 1 and 10.';
  end if;

  insert into public.results (
    assignment_id,
    athlete_id,
    rep_times,
    rpe,
    notes,
    completed_at
  ) values (
    v_assignment.id,
    v_assignment.athlete_id,
    p_rep_times,
    p_rpe,
    nullif(trim(coalesce(p_notes, '')), ''),
    now()
  )
  on conflict (assignment_id)
  do update set
    athlete_id = excluded.athlete_id,
    rep_times = excluded.rep_times,
    rpe = excluded.rpe,
    notes = excluded.notes,
    completed_at = now()
  returning * into v_result;

  update public.assignments
  set status = 'completed'
  where id = v_assignment.id;

  return jsonb_build_object(
    'result_id', v_result.id,
    'assignment_id', v_assignment.id,
    'athlete_id', v_assignment.athlete_id,
    'status', 'completed',
    'rep_times', v_result.rep_times,
    'rpe', v_result.rpe,
    'notes', v_result.notes,
    'completed_at', v_result.completed_at
  );
end;
$$;

revoke all on function public.get_my_coach_result_context() from public;
grant execute on function public.get_my_coach_result_context() to authenticated;

revoke all on function public.save_coach_result(uuid,jsonb,smallint,text) from public;
grant execute on function public.save_coach_result(uuid,jsonb,smallint,text) to authenticated;
