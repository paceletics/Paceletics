-- Paceletics migration v0.18
-- Safe athlete offboarding: remove active access without deleting historical PBs/results.

alter table public.athletes
  add column if not exists is_active boolean not null default true;

alter table public.athletes
  add column if not exists left_club_at timestamptz;

-- Active athlete records remain visible to their Club owner / linked Athlete account.
-- Offboarded records stay in the database for history but disappear from normal active queries.
drop policy if exists "athletes_select_owner_or_linked" on public.athletes;
create policy "athletes_select_owner_or_linked" on public.athletes
for select using (
  is_active = true
  and (auth.uid() = owner_user_id or auth.uid() = linked_user_id)
);

create or replace function public.offboard_club_athlete(p_athlete_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_athlete public.athletes%rowtype;
  v_name text;
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
    raise exception 'Only Club accounts can remove an athlete from the club.';
  end if;

  select a.* into v_athlete
  from public.athletes a
  where a.id = p_athlete_id
  for update;

  if not found then
    raise exception 'Athlete could not be found.';
  end if;

  if v_athlete.owner_user_id <> auth.uid() then
    raise exception 'You do not have permission to remove this athlete.';
  end if;

  if v_athlete.is_active = false then
    return jsonb_build_object(
      'athlete_id', v_athlete.id,
      'athlete_name', v_athlete.full_name,
      'status', 'already_removed'
    );
  end if;

  v_name := v_athlete.full_name;

  -- Stop Athlete-account access immediately and archive the active record.
  update public.athletes a
  set is_active = false,
      linked_user_id = null,
      left_club_at = now()
  where a.id = p_athlete_id;

  -- Remove all squad access so linked Coaches can no longer see the athlete.
  delete from public.squad_athletes sa
  where sa.athlete_id = p_athlete_id;

  -- Cancel any future/planned work while keeping completed training history.
  update public.assignments x
  set status = 'skipped'
  where x.athlete_id = p_athlete_id
    and x.status = 'planned';

  -- Revoke any invitation that has not been accepted yet.
  update public.athlete_invites ai
  set status = 'revoked'
  where ai.athlete_id = p_athlete_id
    and ai.status = 'pending';

  return jsonb_build_object(
    'athlete_id', p_athlete_id,
    'athlete_name', v_name,
    'status', 'removed',
    'history_preserved', true,
    'athlete_access_revoked', true,
    'squad_access_removed', true
  );
end;
$$;

revoke all on function public.offboard_club_athlete(uuid) from public;
grant execute on function public.offboard_club_athlete(uuid) to authenticated;
