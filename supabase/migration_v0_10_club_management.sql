-- Paceletics migration v0.10
-- Club management: club profile, coach roster, squads and coach-to-squad assignments.
-- First release is intentionally club-owner only. Coach account linking comes later.

create table if not exists public.clubs (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null unique references public.profiles(id) on delete cascade,
  name text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.club_coaches (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  linked_user_id uuid references public.profiles(id) on delete set null,
  full_name text not null,
  email text,
  status text not null default 'roster' check (status in ('roster','linked')),
  created_at timestamptz not null default now(),
  unique (club_id, linked_user_id)
);

create unique index if not exists club_coaches_unique_email
on public.club_coaches (club_id, lower(email))
where email is not null and btrim(email) <> '';

create table if not exists public.squads (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  name text not null,
  created_at timestamptz not null default now(),
  unique (club_id, name)
);

create table if not exists public.squad_coaches (
  id uuid primary key default gen_random_uuid(),
  squad_id uuid not null references public.squads(id) on delete cascade,
  coach_id uuid not null references public.club_coaches(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (squad_id, coach_id)
);

alter table public.clubs enable row level security;
alter table public.club_coaches enable row level security;
alter table public.squads enable row level security;
alter table public.squad_coaches enable row level security;

-- Clean up any earlier draft policies if this migration is re-run.
drop policy if exists "clubs_linked_coach_select" on public.clubs;
drop policy if exists "club_coaches_linked_select" on public.club_coaches;
drop policy if exists "squads_linked_coach_select" on public.squads;
drop policy if exists "squad_coaches_linked_select" on public.squad_coaches;

-- Club record is managed only by its owning Club account.
drop policy if exists "clubs_owner_all" on public.clubs;
create policy "clubs_owner_all" on public.clubs
for all
using (owner_user_id = auth.uid())
with check (owner_user_id = auth.uid());

-- Coach roster follows club ownership.
drop policy if exists "club_coaches_owner_all" on public.club_coaches;
create policy "club_coaches_owner_all" on public.club_coaches
for all
using (
  exists (
    select 1 from public.clubs c
    where c.id = club_coaches.club_id and c.owner_user_id = auth.uid()
  )
)
with check (
  exists (
    select 1 from public.clubs c
    where c.id = club_coaches.club_id and c.owner_user_id = auth.uid()
  )
);

-- Squads follow club ownership.
drop policy if exists "squads_owner_all" on public.squads;
create policy "squads_owner_all" on public.squads
for all
using (
  exists (
    select 1 from public.clubs c
    where c.id = squads.club_id and c.owner_user_id = auth.uid()
  )
)
with check (
  exists (
    select 1 from public.clubs c
    where c.id = squads.club_id and c.owner_user_id = auth.uid()
  )
);

-- Coach-to-squad assignments follow club ownership.
drop policy if exists "squad_coaches_owner_all" on public.squad_coaches;
create policy "squad_coaches_owner_all" on public.squad_coaches
for all
using (
  exists (
    select 1
    from public.squads s
    join public.clubs c on c.id = s.club_id
    where s.id = squad_coaches.squad_id and c.owner_user_id = auth.uid()
  )
)
with check (
  exists (
    select 1
    from public.squads s
    join public.clubs c on c.id = s.club_id
    where s.id = squad_coaches.squad_id and c.owner_user_id = auth.uid()
  )
);
