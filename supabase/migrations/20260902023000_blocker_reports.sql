-- "Kendala & Blocker" was 100% client-local demo data with no backing
-- table at all -- every org saw the same 3 hardcoded fake blockers
-- forever, and there was no way to make a real one persist or to
-- actually remove a fake one (only "resolve", which just marks it done,
-- not gone). Same visibility/write shape as notebook_entries.
create table blocker_reports (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references organizations(id) on delete cascade,
  reported_by uuid references profiles(id) on delete set null,
  scope text not null default 'general' check (scope in ('general', 'project', 'task')),
  division_id uuid references divisions(id),
  project_id uuid references projects(id) on delete set null,
  phase_id uuid references phases(id) on delete set null,
  task_id uuid references tasks(id) on delete set null,
  category text not null,
  description text,
  entry_date date not null default current_date,
  resolved boolean not null default false,
  resolved_at date,
  created_at timestamptz not null default now()
);

create index blocker_reports_org_division_idx on blocker_reports (org_id, division_id);

alter table blocker_reports enable row level security;

create policy "blocker_reports: division members can view" on blocker_reports
  for select using (
    org_id = (select get_my_org_id())
    and (
      division_id is null
      or (exists (select 1 from divisions d where d.id = blocker_reports.division_id and d.is_personal) and reported_by = (select auth.uid()))
      or (not exists (select 1 from divisions d where d.id = blocker_reports.division_id and d.is_personal) and ((select get_my_role()) = 'owner' or division_id = (select get_my_division_id())))
    )
  );

create policy "blocker_reports: reporter can write, manager/owner can too" on blocker_reports
  for all using (
    org_id = (select get_my_org_id())
    and (reported_by = (select auth.uid()) or (select get_my_role()) = 'owner' or ((select get_my_role()) = 'manager' and division_id = (select get_my_division_id())))
  )
  with check (
    org_id = (select get_my_org_id())
    and (reported_by = (select auth.uid()) or (select get_my_role()) = 'owner' or ((select get_my_role()) = 'manager' and division_id = (select get_my_division_id())))
  );

alter publication supabase_realtime add table blocker_reports;
