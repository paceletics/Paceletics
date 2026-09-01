-- Privacy-conscious anonymous page-view analytics for the Paceletics beta.
-- Stores no IP address, full referrer URL, user-agent string, or fingerprint.
create table if not exists public.page_views (
  id uuid primary key default gen_random_uuid(),
  visitor_id uuid not null,
  page_path text not null,
  referrer_domain text,
  device_category text not null,
  browser_category text not null,
  created_at timestamptz not null default now(),
  constraint page_views_path_length check (char_length(page_path) between 1 and 300),
  constraint page_views_path_shape check (page_path like '/%' and page_path not like '%?%' and page_path not like '%#%'),
  constraint page_views_referrer_length check (referrer_domain is null or char_length(referrer_domain) <= 253),
  constraint page_views_referrer_shape check (referrer_domain is null or referrer_domain !~ '[/@?#[:space:]]'),
  constraint page_views_device_category check (device_category in ('desktop', 'mobile', 'tablet', 'unknown')),
  constraint page_views_browser_category check (browser_category in ('chrome', 'safari', 'firefox', 'edge', 'other'))
);

comment on table public.page_views is
  'Privacy-conscious beta page views. No raw IP addresses, full referrer URLs, user-agent strings, or fingerprint data are stored.';
comment on column public.page_views.visitor_id is
  'Random first-party identifier generated in the visitor browser and stored locally; not derived from device characteristics.';
comment on column public.page_views.referrer_domain is
  'Hostname only. Full referrer URLs and paths are deliberately discarded.';

alter table public.page_views enable row level security;

drop policy if exists page_views_insert_anonymous on public.page_views;
create policy page_views_insert_anonymous
on public.page_views
for insert
to anon, authenticated
with check (
  page_path like '/%'
  and page_path not like '%?%'
  and page_path not like '%#%'
  and char_length(page_path) between 1 and 300
  and (referrer_domain is null or (
    char_length(referrer_domain) <= 253
    and referrer_domain !~ '[/@?#[:space:]]'
  ))
  and device_category in ('desktop', 'mobile', 'tablet', 'unknown')
  and browser_category in ('chrome', 'safari', 'firefox', 'edge', 'other')
);

drop policy if exists page_views_select_club_owner on public.page_views;
create policy page_views_select_club_owner
on public.page_views
for select
to authenticated
using (
  exists (
    select 1
    from public.profiles
    where profiles.id = (select auth.uid())
      and profiles.role = 'club'
  )
);

revoke all on table public.page_views from anon, authenticated;
grant insert on table public.page_views to anon, authenticated;
grant select on table public.page_views to authenticated;

create index if not exists page_views_created_at_idx
  on public.page_views (created_at desc);
create index if not exists page_views_visitor_created_idx
  on public.page_views (visitor_id, created_at desc);
create index if not exists page_views_path_created_idx
  on public.page_views (page_path, created_at desc);

create or replace function public.get_page_view_report(p_days integer default 30)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  report_result jsonb;
begin
  if p_days < 1 or p_days > 365 then
    raise exception 'p_days must be between 1 and 365';
  end if;
  if not exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and role = 'club'
  ) then
    raise exception 'Club account required';
  end if;

  select jsonb_build_object(
    'generated_at', now(),
    'period_days', p_days,
    'total_visits', (select count(*) from public.page_views),
    'unique_visitors', (select count(distinct visitor_id) from public.page_views),
    'period_visits', (select count(*) from public.page_views where created_at >= now() - make_interval(days => p_days)),
    'period_unique_visitors', (select count(distinct visitor_id) from public.page_views where created_at >= now() - make_interval(days => p_days)),
    'pages', coalesce((
      select jsonb_agg(jsonb_build_object('path', page_path, 'visits', visits, 'unique_visitors', unique_visitors) order by visits desc, page_path)
      from (
        select page_path, count(*) visits, count(distinct visitor_id) unique_visitors
        from public.page_views
        where created_at >= now() - make_interval(days => p_days)
        group by page_path
        order by count(*) desc
        limit 50
      ) p
    ), '[]'::jsonb),
    'referrers', coalesce((
      select jsonb_agg(jsonb_build_object('domain', ref_domain, 'visits', visits) order by visits desc, ref_domain)
      from (
        select coalesce(referrer_domain, 'Direct / internal') ref_domain, count(*) visits
        from public.page_views
        where created_at >= now() - make_interval(days => p_days)
        group by coalesce(referrer_domain, 'Direct / internal')
        order by count(*) desc
        limit 25
      ) r
    ), '[]'::jsonb),
    'devices', coalesce((
      select jsonb_agg(jsonb_build_object('category', device_category, 'visits', visit_count) order by visit_count desc)
      from (
        select device_category, count(*) visit_count
        from public.page_views
        where created_at >= now() - make_interval(days => p_days)
        group by device_category
      ) d
    ), '[]'::jsonb),
    'browsers', coalesce((
      select jsonb_agg(jsonb_build_object('category', browser_category, 'visits', visit_count) order by visit_count desc)
      from (
        select browser_category, count(*) visit_count
        from public.page_views
        where created_at >= now() - make_interval(days => p_days)
        group by browser_category
      ) b
    ), '[]'::jsonb),
    'daily', coalesce((
      select jsonb_agg(jsonb_build_object('date', visit_date, 'visits', visits, 'unique_visitors', unique_visitors) order by visit_date)
      from (
        select created_at::date visit_date, count(*) visits, count(distinct visitor_id) unique_visitors
        from public.page_views
        where created_at >= now() - make_interval(days => p_days)
        group by created_at::date
      ) x
    ), '[]'::jsonb)
  ) into report_result;
  return report_result;
end;
$$;

revoke all on function public.get_page_view_report(integer) from public, anon;
grant execute on function public.get_page_view_report(integer) to authenticated;
