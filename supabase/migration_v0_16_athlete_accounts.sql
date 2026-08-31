-- Paceletics migration v0.16
-- Secure Athlete account invitations, linked dashboard data and Athlete result entry.

create table if not exists public.athlete_invites (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  athlete_id uuid not null references public.athletes(id) on delete cascade,
  email text not null,
  token uuid not null default gen_random_uuid() unique,
  status text not null default 'pending' check (status in ('pending','accepted','revoked','expired')),
  expires_at timestamptz not null default (now() + interval '14 days'),
  accepted_by uuid references public.profiles(id) on delete set null,
  accepted_at timestamptz,
  created_at timestamptz not null default now()
);

create unique index if not exists athlete_invites_one_pending_per_athlete
on public.athlete_invites (athlete_id)
where status = 'pending';

alter table public.athlete_invites enable row level security;

drop policy if exists "athlete_invites_owner_all" on public.athlete_invites;
create policy "athlete_invites_owner_all" on public.athlete_invites
for all
using (
  exists (
    select 1
    from public.clubs c
    join public.athletes a on a.owner_user_id = c.owner_user_id
    where c.id = athlete_invites.club_id
      and a.id = athlete_invites.athlete_id
      and c.owner_user_id = auth.uid()
  )
)
with check (
  exists (
    select 1
    from public.clubs c
    join public.athletes a on a.owner_user_id = c.owner_user_id
    where c.id = athlete_invites.club_id
      and a.id = athlete_invites.athlete_id
      and c.owner_user_id = auth.uid()
  )
);

create or replace function public.accept_athlete_invite(p_token uuid)
returns table (
  athlete_id uuid,
  athlete_name text,
  club_id uuid,
  club_name text,
  linked_user_id uuid
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inv public.athlete_invites%rowtype;
  v_profile public.profiles%rowtype;
  v_athlete public.athletes%rowtype;
  v_email text;
  v_club_name text;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in to accept this invitation.';
  end if;

  select ai.* into v_inv
  from public.athlete_invites ai
  where ai.token = p_token
  for update;

  if not found then
    raise exception 'This athlete invitation could not be found.';
  end if;

  if v_inv.status <> 'pending' then
    if v_inv.status = 'accepted' and v_inv.accepted_by = auth.uid() then
      select a.* into v_athlete from public.athletes a where a.id = v_inv.athlete_id;
      select c.name into v_club_name from public.clubs c where c.id = v_inv.club_id;
      return query select v_athlete.id, v_athlete.full_name, v_inv.club_id, v_club_name, auth.uid();
      return;
    end if;
    raise exception 'This invitation is no longer active.';
  end if;

  if v_inv.expires_at <= now() then
    update public.athlete_invites ai
    set status = 'expired'
    where ai.id = v_inv.id;
    raise exception 'This invitation has expired. Ask the club to create a new one.';
  end if;

  v_email := lower(trim(coalesce(auth.jwt() ->> 'email', '')));
  if v_email = '' then
    raise exception 'Your signed-in account does not have an email address.';
  end if;

  if lower(trim(v_inv.email)) <> v_email then
    raise exception 'Sign in with the email address this invitation was sent to.';
  end if;

  select p.* into v_profile
  from public.profiles p
  where p.id = auth.uid();

  if not found then
    raise exception 'Your Paceletics profile could not be found.';
  end if;

  if v_profile.role <> 'athlete' then
    raise exception 'This invitation must be accepted with an Athlete account.';
  end if;

  select a.* into v_athlete
  from public.athletes a
  join public.clubs c on c.owner_user_id = a.owner_user_id
  where a.id = v_inv.athlete_id
    and c.id = v_inv.club_id
  for update of a;

  if not found then
    raise exception 'The athlete record no longer belongs to this club.';
  end if;

  if v_athlete.linked_user_id is not null and v_athlete.linked_user_id <> auth.uid() then
    raise exception 'This athlete profile is already linked to another account.';
  end if;

  if exists (
    select 1 from public.athletes a
    where a.linked_user_id = auth.uid()
      and a.id <> v_athlete.id
  ) then
    raise exception 'This Athlete account is already linked to another athlete profile.';
  end if;

  update public.athletes a
  set linked_user_id = auth.uid()
  where a.id = v_athlete.id;

  update public.athlete_invites ai
  set status = 'accepted',
      accepted_by = auth.uid(),
      accepted_at = now()
  where ai.id = v_inv.id;

  select c.name into v_club_name
  from public.clubs c
  where c.id = v_inv.club_id;

  return query
  select v_athlete.id, v_athlete.full_name, v_inv.club_id, v_club_name, auth.uid();
end;
$$;

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
  order by a.created_at
  limit 1;

  if not found then
    return jsonb_build_object(
      'linked', false,
      'athlete', null,
      'club_name', null,
      'pbs', '[]'::jsonb,
      'training', '[]'::jsonb
    );
  end if;

  select c.name into v_club_name
  from public.clubs c
  where c.owner_user_id = v_athlete.owner_user_id
  limit 1;

  select jsonb_build_object(
    'linked', true,
    'club_name', v_club_name,
    'athlete', jsonb_build_object(
      'id', v_athlete.id,
      'full_name', v_athlete.full_name,
      'group_name', v_athlete.group_name,
      'primary_event', v_athlete.primary_event
    ),
    'pbs', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'event', pb.event,
          'time_seconds', pb.time_seconds,
          'achieved_on', pb.achieved_on
        ) order by pb.event
      )
      from public.personal_bests pb
      where pb.athlete_id = v_athlete.id
    ), '[]'::jsonb),
    'training', coalesce((
      select jsonb_agg(q.row_data order by q.sort_date desc)
      from (
        select
          coalesce(r.completed_at, s.scheduled_date::timestamptz, x.created_at) as sort_date,
          jsonb_build_object(
            'assignment_id', x.id,
            'status', x.status,
            'session_id', s.id,
            'title', s.title,
            'event', s.event,
            'main_set', s.main_set,
            'recovery', s.recovery,
            'effort', s.effort,
            'scheduled_date', s.scheduled_date,
            'notes', s.notes,
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
        join public.sessions s on s.id = x.session_id
        left join public.results r on r.assignment_id = x.id
        where x.athlete_id = v_athlete.id
        order by sort_date desc
        limit 100
      ) q
    ), '[]'::jsonb)
  ) into v_data;

  return v_data;
end;
$$;

create or replace function public.save_athlete_result(
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
  v_athlete public.athletes%rowtype;
  v_assignment public.assignments%rowtype;
  v_result public.results%rowtype;
  v_rep_text text;
  v_rep_num numeric;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in.';
  end if;

  if not exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'athlete'
  ) then
    raise exception 'Only Athlete accounts can use Athlete result entry.';
  end if;

  select a.* into v_athlete
  from public.athletes a
  where a.linked_user_id = auth.uid()
  order by a.created_at
  limit 1;

  if not found then
    raise exception 'Your Athlete account is not linked to an athlete profile.';
  end if;

  select x.* into v_assignment
  from public.assignments x
  where x.id = p_assignment_id
    and x.athlete_id = v_athlete.id;

  if not found then
    raise exception 'You do not have access to this assignment.';
  end if;

  if v_assignment.status = 'skipped' then
    raise exception 'A skipped assignment cannot be completed with a result.';
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
    assignment_id, athlete_id, rep_times, rpe, notes, completed_at
  ) values (
    v_assignment.id, v_athlete.id, p_rep_times, p_rpe,
    nullif(trim(coalesce(p_notes, '')), ''), now()
  )
  on conflict (assignment_id)
  do update set
    athlete_id = excluded.athlete_id,
    rep_times = excluded.rep_times,
    rpe = excluded.rpe,
    notes = excluded.notes,
    completed_at = now()
  returning * into v_result;

  update public.assignments x
  set status = 'completed'
  where x.id = v_assignment.id;

  return jsonb_build_object(
    'result_id', v_result.id,
    'assignment_id', v_assignment.id,
    'athlete_id', v_athlete.id,
    'status', 'completed',
    'rep_times', v_result.rep_times,
    'rpe', v_result.rpe,
    'notes', v_result.notes,
    'completed_at', v_result.completed_at
  );
end;
$$;

revoke all on function public.accept_athlete_invite(uuid) from public;
grant execute on function public.accept_athlete_invite(uuid) to authenticated;

revoke all on function public.get_my_athlete_dashboard() from public;
grant execute on function public.get_my_athlete_dashboard() to authenticated;

revoke all on function public.save_athlete_result(uuid,jsonb,smallint,text) from public;
grant execute on function public.save_athlete_result(uuid,jsonb,smallint,text) to authenticated;
