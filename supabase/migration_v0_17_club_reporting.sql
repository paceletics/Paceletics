-- Paceletics migration v0.17
-- Secure Club-owner reporting across coaches, squads, athletes, sessions and results.

create or replace function public.get_my_club_report()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_club public.clubs%rowtype;
  v_data jsonb;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in.';
  end if;

  if not exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role = 'club'
  ) then
    raise exception 'This report is only available to Club accounts.';
  end if;

  select c.*
  into v_club
  from public.clubs c
  where c.owner_user_id = auth.uid()
  limit 1;

  if not found then
    raise exception 'Set up your club before opening Club Reports.';
  end if;

  select jsonb_build_object(
    'club', jsonb_build_object(
      'id', v_club.id,
      'name', v_club.name
    ),

    'metrics', jsonb_build_object(
      'athletes', (
        select count(*)
        from public.athletes a
        where a.owner_user_id = auth.uid()
      ),
      'linked_athletes', (
        select count(*)
        from public.athletes a
        where a.owner_user_id = auth.uid()
          and a.linked_user_id is not null
      ),
      'coaches', (
        select count(*)
        from public.club_coaches cc
        where cc.club_id = v_club.id
      ),
      'linked_coaches', (
        select count(*)
        from public.club_coaches cc
        where cc.club_id = v_club.id
          and cc.status = 'linked'
          and cc.linked_user_id is not null
      ),
      'squads', (
        select count(*)
        from public.squads s
        where s.club_id = v_club.id
      ),
      'assigned_sessions', (
        select count(distinct x.session_id)
        from public.assignments x
        join public.athletes a on a.id = x.athlete_id
        where a.owner_user_id = auth.uid()
      ),
      'planned_assignments', (
        select count(*)
        from public.assignments x
        join public.athletes a on a.id = x.athlete_id
        where a.owner_user_id = auth.uid()
          and x.status = 'planned'
      ),
      'completed_assignments', (
        select count(*)
        from public.assignments x
        join public.athletes a on a.id = x.athlete_id
        where a.owner_user_id = auth.uid()
          and x.status = 'completed'
      ),
      'results', (
        select count(*)
        from public.results r
        join public.athletes a on a.id = r.athlete_id
        where a.owner_user_id = auth.uid()
      ),
      'average_rpe', (
        select round(avg(r.rpe::numeric), 1)
        from public.results r
        join public.athletes a on a.id = r.athlete_id
        where a.owner_user_id = auth.uid()
      )
    ),

    'squads', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', s.id,
          'name', s.name,
          'athletes', (
            select count(distinct sa.athlete_id)
            from public.squad_athletes sa
            join public.athletes a on a.id = sa.athlete_id
            where sa.squad_id = s.id
              and a.owner_user_id = auth.uid()
          ),
          'coaches', (
            select count(distinct sc.coach_id)
            from public.squad_coaches sc
            join public.club_coaches cc on cc.id = sc.coach_id
            where sc.squad_id = s.id
              and cc.club_id = v_club.id
          ),
          'planned', (
            select count(*)
            from public.assignments x
            join public.squad_athletes sa on sa.athlete_id = x.athlete_id
            join public.athletes a on a.id = x.athlete_id
            where sa.squad_id = s.id
              and a.owner_user_id = auth.uid()
              and x.status = 'planned'
          ),
          'completed', (
            select count(*)
            from public.assignments x
            join public.squad_athletes sa on sa.athlete_id = x.athlete_id
            join public.athletes a on a.id = x.athlete_id
            where sa.squad_id = s.id
              and a.owner_user_id = auth.uid()
              and x.status = 'completed'
          ),
          'results', (
            select count(*)
            from public.results r
            join public.squad_athletes sa on sa.athlete_id = r.athlete_id
            join public.athletes a on a.id = r.athlete_id
            where sa.squad_id = s.id
              and a.owner_user_id = auth.uid()
          ),
          'average_rpe', (
            select round(avg(r.rpe::numeric), 1)
            from public.results r
            join public.squad_athletes sa on sa.athlete_id = r.athlete_id
            join public.athletes a on a.id = r.athlete_id
            where sa.squad_id = s.id
              and a.owner_user_id = auth.uid()
          )
        )
        order by s.name
      )
      from public.squads s
      where s.club_id = v_club.id
    ), '[]'::jsonb),

    'athletes', coalesce((
      select jsonb_agg(q.row_data order by q.full_name)
      from (
        select
          a.full_name,
          jsonb_build_object(
            'id', a.id,
            'full_name', a.full_name,
            'group_name', a.group_name,
            'primary_event', a.primary_event,
            'linked', a.linked_user_id is not null,
            'squads', coalesce((
              select jsonb_agg(s.name order by s.name)
              from public.squad_athletes sa
              join public.squads s on s.id = sa.squad_id
              where sa.athlete_id = a.id
                and s.club_id = v_club.id
            ), '[]'::jsonb),
            'primary_pb', (
              select jsonb_build_object(
                'event', pb.event,
                'time_seconds', pb.time_seconds,
                'achieved_on', pb.achieved_on
              )
              from public.personal_bests pb
              where pb.athlete_id = a.id
                and pb.event = a.primary_event
              limit 1
            ),
            'planned', (
              select count(*)
              from public.assignments x
              where x.athlete_id = a.id
                and x.status = 'planned'
            ),
            'completed', (
              select count(*)
              from public.assignments x
              where x.athlete_id = a.id
                and x.status = 'completed'
            ),
            'results', (
              select count(*)
              from public.results r
              where r.athlete_id = a.id
            ),
            'average_rpe', (
              select round(avg(r.rpe::numeric), 1)
              from public.results r
              where r.athlete_id = a.id
            ),
            'last_completed', (
              select max(r.completed_at)
              from public.results r
              where r.athlete_id = a.id
            )
          ) as row_data
        from public.athletes a
        where a.owner_user_id = auth.uid()
      ) q
    ), '[]'::jsonb),

    'recent_results', coalesce((
      select jsonb_agg(q.row_data order by q.completed_at desc)
      from (
        select
          r.completed_at,
          jsonb_build_object(
            'result_id', r.id,
            'completed_at', r.completed_at,
            'athlete_id', a.id,
            'athlete_name', a.full_name,
            'session_id', s.id,
            'session_title', s.title,
            'event', s.event,
            'main_set', s.main_set,
            'rep_times', r.rep_times,
            'rpe', r.rpe
          ) as row_data
        from public.results r
        join public.athletes a on a.id = r.athlete_id
        join public.assignments x on x.id = r.assignment_id
        join public.sessions s on s.id = x.session_id
        where a.owner_user_id = auth.uid()
        order by r.completed_at desc
        limit 25
      ) q
    ), '[]'::jsonb)
  ) into v_data;

  return v_data;
end;
$$;

revoke all on function public.get_my_club_report() from public;
grant execute on function public.get_my_club_report() to authenticated;
