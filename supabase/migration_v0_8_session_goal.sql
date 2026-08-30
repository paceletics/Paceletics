-- Paceletics v0.8 session builder
-- Run once in Supabase SQL Editor.

alter table public.sessions
add column if not exists training_goal text;

alter table public.sessions
drop constraint if exists sessions_training_goal_check;

alter table public.sessions
add constraint sessions_training_goal_check
check (
  training_goal is null or training_goal in (
    'acceleration',
    'max_velocity',
    'speed_endurance',
    'special_endurance',
    'race_modelling'
  )
);
