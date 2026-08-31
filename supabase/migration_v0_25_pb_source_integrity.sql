-- Paceletics database migration v0.25
-- Prevent a manually edited PB from retaining an old Power of 10 confirmation label.

create or replace function public.keep_pb_source_honest()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if (new.time_seconds is distinct from old.time_seconds or new.achieved_on is distinct from old.achieved_on)
     and new.source is not distinct from old.source
     and new.source_reference is not distinct from old.source_reference
     and new.source_confirmed_at is not distinct from old.source_confirmed_at then
    new.source := 'paceletics_manual';
    new.source_reference := null;
    new.source_confirmed_at := null;
  end if;
  return new;
end;
$$;

drop trigger if exists personal_bests_keep_source_honest on public.personal_bests;
create trigger personal_bests_keep_source_honest
before update of time_seconds, achieved_on, source, source_reference, source_confirmed_at
on public.personal_bests
for each row execute function public.keep_pb_source_honest();

revoke execute on function public.keep_pb_source_honest() from public, anon, authenticated;
