-- Paceletics migration v0.12
-- Club athlete-to-squad assignment and scoped Coach athlete visibility.

create table if not exists public.squad_athletes (
  id uuid primary key default gen_random_uuid(),
  squad_id uuid not null references public.squads(id) on delete cascade,
  athlete_id uuid not null references public.athletes(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (squad_id, athlete_id)
);

alter table public.squad_athletes enable row level security;

-- Club owners manage athlete-to-squad membership for athletes they own.
drop policy if exists "squad_athletes_owner_all" on public.squad_athletes;
create policy "squad_athletes_owner_all" on public.squad_athletes
for all
using (
  exists (
    select 1
    from public.squads s
    join public.clubs c on c.id = s.club_id
    where s.id = squad_athletes.squad_id
      and c.owner_user_id = auth.uid()
  )
)
with check (
  exists (
    select 1
    from public.squads s
    join public.clubs c on c.id = s.club_id
    where s.id = squad_athletes.squad_id
      and c.owner_user_id = auth.uid()
  )
  and exists (
    select 1 from public.athletes a
    where a.id = squad_athletes.athlete_id
      and a.owner_user_id = auth.uid()
  )
);

-- Coach overview v2. Returns only linked memberships, assigned squads,
-- and athletes the Club has placed into those assigned squads.
create or replace function public.get_my_coach_club_v2()
returns table (
  club_id uuid,
  club_name text,
  coach_id uuid,
  coach_name text,
  coach_email text,
  squad_id uuid,
  squad_name text,
  athlete_id uuid,
  athlete_name text,
  athlete_group text,
  athlete_primary_event text
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
    s.name,
    a.id,
    a.full_name,
    a.group_name,
    a.primary_event
  from public.club_coaches cc
  join public.clubs c on c.id = cc.club_id
  left join public.squad_coaches sc on sc.coach_id = cc.id
  left join public.squads s on s.id = sc.squad_id
  left join public.squad_athletes sa on sa.squad_id = s.id
  left join public.athletes a on a.id = sa.athlete_id
  where cc.linked_user_id = auth.uid()
    and cc.status = 'linked'
  order by c.name, s.name nulls last, a.full_name nulls last;
end;
$$;

revoke all on function public.get_my_coach_club_v2() from public;
grant execute on function public.get_my_coach_club_v2() to authenticated;
