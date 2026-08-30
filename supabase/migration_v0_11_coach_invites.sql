-- Paceletics migration v0.11
-- Secure Club -> Coach invitation and account linking.

create table if not exists public.club_invites (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  coach_id uuid not null references public.club_coaches(id) on delete cascade,
  email text not null,
  token uuid not null default gen_random_uuid() unique,
  status text not null default 'pending' check (status in ('pending','accepted','revoked','expired')),
  expires_at timestamptz not null default (now() + interval '14 days'),
  accepted_by uuid references public.profiles(id) on delete set null,
  accepted_at timestamptz,
  created_at timestamptz not null default now()
);

create unique index if not exists club_invites_one_pending_per_coach
on public.club_invites (coach_id)
where status = 'pending';

alter table public.club_invites enable row level security;

-- Only the Club owner can manage and view invitations directly.
drop policy if exists "club_invites_owner_all" on public.club_invites;
create policy "club_invites_owner_all" on public.club_invites
for all
using (
  exists (
    select 1 from public.clubs c
    where c.id = club_invites.club_id
      and c.owner_user_id = auth.uid()
  )
)
with check (
  exists (
    select 1 from public.clubs c
    where c.id = club_invites.club_id
      and c.owner_user_id = auth.uid()
  )
);

-- Remove any draft linked-coach SELECT policies. Coach reads use a tightly scoped RPC below,
-- which avoids circular RLS checks between clubs and club_coaches.
drop policy if exists "clubs_linked_coach_select" on public.clubs;
drop policy if exists "club_coaches_linked_select" on public.club_coaches;
drop policy if exists "squads_linked_coach_select" on public.squads;
drop policy if exists "squad_coaches_linked_select" on public.squad_coaches;

-- Accepting an invite is done through this security-definer function.
-- The random token, matching signed-in email and Coach role are all required.
create or replace function public.accept_club_invite(p_token uuid)
returns table (
  club_id uuid,
  club_name text,
  coach_id uuid,
  coach_name text,
  linked_user_id uuid
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inv public.club_invites%rowtype;
  v_profile public.profiles%rowtype;
  v_email text;
  v_club_name text;
  v_coach_name text;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in to accept this invitation.';
  end if;

  select * into v_inv
  from public.club_invites
  where token = p_token
  for update;

  if not found then
    raise exception 'This invitation could not be found.';
  end if;

  if v_inv.status <> 'pending' then
    if v_inv.status = 'accepted' and v_inv.accepted_by = auth.uid() then
      select c.name, cc.full_name
      into v_club_name, v_coach_name
      from public.clubs c
      join public.club_coaches cc on cc.id = v_inv.coach_id
      where c.id = v_inv.club_id;

      return query
      select v_inv.club_id, v_club_name, v_inv.coach_id, v_coach_name, auth.uid();
      return;
    end if;
    raise exception 'This invitation is no longer active.';
  end if;

  if v_inv.expires_at <= now() then
    update public.club_invites
    set status = 'expired'
    where id = v_inv.id;
    raise exception 'This invitation has expired. Ask the club to create a new one.';
  end if;

  v_email := lower(trim(coalesce(auth.jwt() ->> 'email', '')));
  if v_email = '' then
    raise exception 'Your signed-in account does not have an email address.';
  end if;

  if lower(trim(v_inv.email)) <> v_email then
    raise exception 'Sign in with the email address this invitation was sent to.';
  end if;

  select * into v_profile
  from public.profiles
  where id = auth.uid();

  if not found then
    raise exception 'Your Paceletics profile could not be found.';
  end if;

  if v_profile.role <> 'coach' then
    raise exception 'This invitation must be accepted with a Coach account.';
  end if;

  update public.club_coaches
  set linked_user_id = auth.uid(),
      status = 'linked',
      email = v_inv.email
  where id = v_inv.coach_id
    and club_id = v_inv.club_id
  returning full_name into v_coach_name;

  if not found then
    raise exception 'The coach roster entry no longer exists.';
  end if;

  update public.club_invites
  set status = 'accepted',
      accepted_by = auth.uid(),
      accepted_at = now()
  where id = v_inv.id;

  select name into v_club_name
  from public.clubs
  where id = v_inv.club_id;

  return query
  select v_inv.club_id, v_club_name, v_inv.coach_id, v_coach_name, auth.uid();
end;
$$;

-- Read-only Coach overview. Returns only memberships linked to the current Coach account
-- and only squads assigned to that coach.
create or replace function public.get_my_coach_club()
returns table (
  club_id uuid,
  club_name text,
  coach_id uuid,
  coach_name text,
  coach_email text,
  squad_id uuid,
  squad_name text
)
language plpgsql
security definer
set search_path = public
as $$
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

  return query
  select
    c.id,
    c.name,
    cc.id,
    cc.full_name,
    cc.email,
    s.id,
    s.name
  from public.club_coaches cc
  join public.clubs c on c.id = cc.club_id
  left join public.squad_coaches sc on sc.coach_id = cc.id
  left join public.squads s on s.id = sc.squad_id
  where cc.linked_user_id = auth.uid()
    and cc.status = 'linked'
  order by c.name, s.name nulls last;
end;
$$;

revoke all on function public.accept_club_invite(uuid) from public;
grant execute on function public.accept_club_invite(uuid) to authenticated;
revoke all on function public.get_my_coach_club() from public;
grant execute on function public.get_my_coach_club() to authenticated;
