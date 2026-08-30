-- Paceletics migration v0.13
-- Secure read-only athlete profiles for linked Coaches.

create or replace function public.get_coach_athlete_profile(p_athlete_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_allowed boolean := false;
  v_profile jsonb;
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

  select exists (
    select 1
    from public.club_coaches cc
    join public.squad_coaches sc on sc.coach_id = cc.id
    join public.squad_athletes sa on sa.squad_id = sc.squad_id
    where cc.linked_user_id = auth.uid()
      and cc.status = 'linked'
      and sa.athlete_id = p_athlete_id
  ) into v_allowed;

  if not v_allowed then
    raise exception 'You do not have access to this athlete.';
  end if;

  select jsonb_build_object(
    'athlete', jsonb_build_object(
      'id', a.id,
      'full_name', a.full_name,
      'group_name', a.group_name,
      'primary_event', a.primary_event
    ),
    'pbs', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'event', pb.event,
          'time_seconds', pb.time_seconds,
          'achieved_on', pb.achieved_on
        ) order by
          case pb.event
            when '100m' then 1
            when '200m' then 2
            when '400m' then 3
            when '800m' then 4
            when '1500m' then 5
            else 99
          end
      )
      from public.personal_bests pb
      where pb.athlete_id = a.id
    ), '[]'::jsonb),
    'training', coalesce((
      select jsonb_agg(t.row_data order by t.sort_time desc)
      from (
        select
          coalesce(r.completed_at, s.scheduled_date::timestamptz, x.created_at) as sort_time,
          jsonb_build_object(
            'assignment_id', x.id,
            'status', x.status,
            'assigned_at', x.created_at,
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
                'rep_times', r.rep_times,
                'rpe', r.rpe,
                'notes', r.notes,
                'completed_at', r.completed_at
              )
            end
          ) as row_data
        from public.assignments x
        join public.sessions s on s.id = x.session_id
        left join public.results r on r.assignment_id = x.id
        where x.athlete_id = a.id
        order by coalesce(r.completed_at, s.scheduled_date::timestamptz, x.created_at) desc
        limit 20
      ) t
    ), '[]'::jsonb)
  ) into v_profile
  from public.athletes a
  where a.id = p_athlete_id;

  if v_profile is null then
    raise exception 'Athlete could not be found.';
  end if;

  return v_profile;
end;
$$;

revoke all on function public.get_coach_athlete_profile(uuid) from public;
grant execute on function public.get_coach_athlete_profile(uuid) to authenticated;
