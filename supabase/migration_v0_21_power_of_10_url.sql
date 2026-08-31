-- Paceletics database migration v0.21
-- Add an optional Power of 10 athlete profile URL for future authorised integration/sync.

alter table public.athletes
  add column if not exists power_of_10_url text;

comment on column public.athletes.power_of_10_url is
  'Optional public Power of 10 athlete profile URL, stored for future authorised integration/sync.';
