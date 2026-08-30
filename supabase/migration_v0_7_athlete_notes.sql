-- Paceletics v0.7 athlete profile notes
-- Run once in Supabase SQL Editor.

alter table public.athletes
add column if not exists coach_notes text;
