-- Paceletics cloud database schema v0.1
-- Run this in Supabase SQL Editor.

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  role text not null default 'athlete' check (role in ('athlete','coach','club')),
  created_at timestamptz not null default now()
);

create table if not exists public.athletes (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references public.profiles(id) on delete cascade,
  linked_user_id uuid references public.profiles(id) on delete set null,
  full_name text not null,
  group_name text,
  primary_event text check (primary_event in ('100m','200m','400m','800m','1500m')),
  created_at timestamptz not null default now()
);

create table if not exists public.personal_bests (
  id uuid primary key default gen_random_uuid(),
  athlete_id uuid not null references public.athletes(id) on delete cascade,
  event text not null check (event in ('100m','200m','400m','800m','1500m')),
  time_seconds numeric(8,3) not null check (time_seconds > 0),
  achieved_on date,
  created_at timestamptz not null default now(),
  unique (athlete_id, event)
);

create table if not exists public.sessions (
  id uuid primary key default gen_random_uuid(),
  created_by uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  event text not null check (event in ('100m','200m','400m','800m','1500m')),
  main_set text not null,
  recovery text,
  effort smallint check (effort between 70 and 110),
  notes text,
  scheduled_date date,
  created_at timestamptz not null default now()
);

create table if not exists public.assignments (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.sessions(id) on delete cascade,
  athlete_id uuid not null references public.athletes(id) on delete cascade,
  assigned_by uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'planned' check (status in ('planned','completed','skipped')),
  created_at timestamptz not null default now(),
  unique (session_id, athlete_id)
);

create table if not exists public.results (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null unique references public.assignments(id) on delete cascade,
  athlete_id uuid not null references public.athletes(id) on delete cascade,
  rep_times jsonb not null default '[]'::jsonb,
  rpe smallint check (rpe between 1 and 10),
  notes text,
  completed_at timestamptz not null default now()
);

-- Create a profile automatically whenever a Supabase Auth user signs up.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    case
      when new.raw_user_meta_data ->> 'role' in ('athlete','coach','club')
        then new.raw_user_meta_data ->> 'role'
      else 'athlete'
    end
  )
  on conflict (id) do update set
    full_name = excluded.full_name,
    role = excluded.role;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert or update of raw_user_meta_data on auth.users
for each row execute procedure public.handle_new_user();

-- Backfill any users created before this schema was installed.
insert into public.profiles (id, full_name, role)
select
  id,
  coalesce(raw_user_meta_data ->> 'full_name', ''),
  case
    when raw_user_meta_data ->> 'role' in ('athlete','coach','club')
      then raw_user_meta_data ->> 'role'
    else 'athlete'
  end
from auth.users
on conflict (id) do nothing;

-- Row Level Security
alter table public.profiles enable row level security;
alter table public.athletes enable row level security;
alter table public.personal_bests enable row level security;
alter table public.sessions enable row level security;
alter table public.assignments enable row level security;
alter table public.results enable row level security;

-- Profiles: users can read and update only their own profile.
drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own" on public.profiles
for select using (auth.uid() = id);

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own" on public.profiles
for update using (auth.uid() = id) with check (auth.uid() = id);

-- Athletes: a coach/club account can manage records it owns.
-- A linked athlete account can read its own athlete record.
drop policy if exists "athletes_select_owner_or_linked" on public.athletes;
create policy "athletes_select_owner_or_linked" on public.athletes
for select using (auth.uid() = owner_user_id or auth.uid() = linked_user_id);

drop policy if exists "athletes_insert_owner" on public.athletes;
create policy "athletes_insert_owner" on public.athletes
for insert with check (auth.uid() = owner_user_id);

drop policy if exists "athletes_update_owner" on public.athletes;
create policy "athletes_update_owner" on public.athletes
for update using (auth.uid() = owner_user_id) with check (auth.uid() = owner_user_id);

drop policy if exists "athletes_delete_owner" on public.athletes;
create policy "athletes_delete_owner" on public.athletes
for delete using (auth.uid() = owner_user_id);

-- PBs follow athlete ownership/linking.
drop policy if exists "pbs_select_accessible_athlete" on public.personal_bests;
create policy "pbs_select_accessible_athlete" on public.personal_bests
for select using (
  exists (
    select 1 from public.athletes a
    where a.id = athlete_id
      and (a.owner_user_id = auth.uid() or a.linked_user_id = auth.uid())
  )
);

drop policy if exists "pbs_manage_owner" on public.personal_bests;
create policy "pbs_manage_owner" on public.personal_bests
for all using (
  exists (
    select 1 from public.athletes a
    where a.id = athlete_id and a.owner_user_id = auth.uid()
  )
) with check (
  exists (
    select 1 from public.athletes a
    where a.id = athlete_id and a.owner_user_id = auth.uid()
  )
);

-- Sessions are managed by their creator.
drop policy if exists "sessions_select_creator_or_assigned" on public.sessions;
create policy "sessions_select_creator_or_assigned" on public.sessions
for select using (
  created_by = auth.uid()
  or exists (
    select 1
    from public.assignments x
    join public.athletes a on a.id = x.athlete_id
    where x.session_id = sessions.id and a.linked_user_id = auth.uid()
  )
);

drop policy if exists "sessions_insert_creator" on public.sessions;
create policy "sessions_insert_creator" on public.sessions
for insert with check (created_by = auth.uid());

drop policy if exists "sessions_update_creator" on public.sessions;
create policy "sessions_update_creator" on public.sessions
for update using (created_by = auth.uid()) with check (created_by = auth.uid());

drop policy if exists "sessions_delete_creator" on public.sessions;
create policy "sessions_delete_creator" on public.sessions
for delete using (created_by = auth.uid());

-- Assignments: assigning coach/club can manage; linked athlete can read.
drop policy if exists "assignments_select_owner_or_athlete" on public.assignments;
create policy "assignments_select_owner_or_athlete" on public.assignments
for select using (
  assigned_by = auth.uid()
  or exists (
    select 1 from public.athletes a
    where a.id = athlete_id and a.linked_user_id = auth.uid()
  )
);

drop policy if exists "assignments_manage_assigner" on public.assignments;
create policy "assignments_manage_assigner" on public.assignments
for all using (assigned_by = auth.uid()) with check (assigned_by = auth.uid());

-- Results: coach/club owner and linked athlete can read.
-- Linked athlete can add/update their own result, and owner can manage it too.
drop policy if exists "results_select_accessible" on public.results;
create policy "results_select_accessible" on public.results
for select using (
  exists (
    select 1 from public.athletes a
    where a.id = athlete_id
      and (a.owner_user_id = auth.uid() or a.linked_user_id = auth.uid())
  )
);

drop policy if exists "results_insert_accessible" on public.results;
create policy "results_insert_accessible" on public.results
for insert with check (
  exists (
    select 1 from public.athletes a
    where a.id = athlete_id
      and (a.owner_user_id = auth.uid() or a.linked_user_id = auth.uid())
  )
);

drop policy if exists "results_update_accessible" on public.results;
create policy "results_update_accessible" on public.results
for update using (
  exists (
    select 1 from public.athletes a
    where a.id = athlete_id
      and (a.owner_user_id = auth.uid() or a.linked_user_id = auth.uid())
  )
) with check (
  exists (
    select 1 from public.athletes a
    where a.id = athlete_id
      and (a.owner_user_id = auth.uid() or a.linked_user_id = auth.uid())
  )
);
