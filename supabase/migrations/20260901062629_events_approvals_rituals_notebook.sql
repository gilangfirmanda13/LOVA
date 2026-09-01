-- ============================================================
-- LOVA: events, approval_requests, rituals, notebook_entries,
-- notifications, ideas. Same visibility philosophy as work_core:
-- division-scoped read for everyone, owner/manager write, except
-- where the feature itself is inherently personal or two-party
-- (notifications, approvals) — see each table's own comment.
-- ============================================================

-- ------------------------------------------------------------
-- events (division nullable = "Umum", visible org-wide)
-- ------------------------------------------------------------
create table events (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references organizations(id) on delete cascade,
  division_id uuid references divisions(id),
  title text not null,
  description text,
  event_type text not null check (event_type in ('training', 'sertifikasi', 'meeting', 'demonstration')),
  cakupan text not null default 'internal' check (cakupan in ('publik', 'klien', 'internal')),
  client_name text,
  date date not null,
  date_mulai date,
  date_selesai date,
  start_time time not null,
  end_time time not null,
  location_type text not null,
  location_detail text,
  attendee_ids uuid[] not null default '{}',
  linked_project_id uuid references projects(id) on delete set null,
  pembicara text,
  harga numeric,
  jumlah_peserta int,
  created_by uuid references profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create index events_org_division_idx on events (org_id, division_id);

alter table events enable row level security;

create policy "events: division members can view" on events
  for select using (
    org_id = (select get_my_org_id())
    and (division_id is null or (select get_my_role()) = 'owner' or division_id = (select get_my_division_id()))
  );

create policy "events: owner or division manager can write" on events
  for all using (
    org_id = (select get_my_org_id())
    and ((select get_my_role()) = 'owner' or ((select get_my_role()) = 'manager' and (division_id is null or division_id = (select get_my_division_id()))))
  )
  with check (
    org_id = (select get_my_org_id())
    and ((select get_my_role()) = 'owner' or ((select get_my_role()) = 'manager' and (division_id is null or division_id = (select get_my_division_id()))))
  );

-- ------------------------------------------------------------
-- approval_requests (two-party by nature: requester + approvers,
-- plus the owner for oversight — not a division-broadcast table)
-- ------------------------------------------------------------
create table approval_requests (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references organizations(id) on delete cascade,
  request_type text not null check (request_type in ('general', 'dana', 'cuti', 'lembur')),
  title text not null,
  description text,
  amount numeric,
  leave_start date,
  leave_end date,
  overtime_date date,
  overtime_hours numeric,
  requested_by uuid references profiles(id) on delete set null,
  approver_ids uuid[] not null default '{}',
  approved_by_ids uuid[] not null default '{}',
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  linked_project_id uuid references projects(id) on delete set null,
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);

create index approval_requests_org_idx on approval_requests (org_id);

alter table approval_requests enable row level security;

create policy "approval_requests: requester, approver, or owner can view" on approval_requests
  for select using (
    org_id = (select get_my_org_id())
    and ((select get_my_role()) = 'owner' or requested_by = (select auth.uid()) or (select auth.uid()) = any (approver_ids))
  );

create policy "approval_requests: any member can request" on approval_requests
  for insert with check (org_id = (select get_my_org_id()) and requested_by = (select auth.uid()));

create policy "approval_requests: approver or owner can decide" on approval_requests
  for update using (
    org_id = (select get_my_org_id())
    and ((select get_my_role()) = 'owner' or requested_by = (select auth.uid()) or (select auth.uid()) = any (approver_ids))
  )
  with check (org_id = (select get_my_org_id()));

-- ------------------------------------------------------------
-- rituals (org-wide visibility, owner/manager manage)
-- ------------------------------------------------------------
create table rituals (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references organizations(id) on delete cascade,
  title text not null,
  description text,
  start_time time not null,
  end_time time not null,
  days text[] not null default '{}',
  division_ids uuid[] not null default '{}',
  pic_id uuid references profiles(id) on delete set null,
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);

create index rituals_org_idx on rituals (org_id);

alter table rituals enable row level security;

create policy "rituals: org members can view" on rituals
  for select using (org_id = (select get_my_org_id()));

create policy "rituals: owner or manager can write" on rituals
  for all using (org_id = (select get_my_org_id()) and (select get_my_role()) in ('owner', 'manager'))
  with check (org_id = (select get_my_org_id()) and (select get_my_role()) in ('owner', 'manager'));

create table ritual_completions (
  id uuid primary key default gen_random_uuid(),
  ritual_id uuid not null references rituals(id) on delete cascade,
  profile_id uuid not null references profiles(id) on delete cascade,
  date date not null,
  created_at timestamptz not null default now(),
  unique (ritual_id, profile_id, date)
);

create index ritual_completions_ritual_idx on ritual_completions (ritual_id);

alter table ritual_completions enable row level security;

create policy "ritual_completions: visible with ritual" on ritual_completions
  for select using (exists (select 1 from rituals r where r.id = ritual_completions.ritual_id));

create policy "ritual_completions: you can mark your own" on ritual_completions
  for all using (profile_id = (select auth.uid())) with check (profile_id = (select auth.uid()));

-- ------------------------------------------------------------
-- notebook_entries (same visibility shape as general_tasks —
-- division-scoped, private when linked to the personal division)
-- ------------------------------------------------------------
create table notebook_entries (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references organizations(id) on delete cascade,
  division_id uuid references divisions(id),
  title text not null,
  type text not null default 'word' check (type in ('word', 'table', 'other')),
  content text,
  author_id uuid references profiles(id) on delete set null,
  entry_date date not null default current_date,
  project_id uuid references projects(id) on delete set null,
  phase_id uuid references phases(id) on delete set null,
  task_id uuid references tasks(id) on delete set null,
  follow_up date,
  created_at timestamptz not null default now()
);

create index notebook_entries_org_division_idx on notebook_entries (org_id, division_id);

alter table notebook_entries enable row level security;

create policy "notebook_entries: division members can view" on notebook_entries
  for select using (
    org_id = (select get_my_org_id())
    and (
      division_id is null
      or (exists (select 1 from divisions d where d.id = notebook_entries.division_id and d.is_personal) and author_id = (select auth.uid()))
      or (not exists (select 1 from divisions d where d.id = notebook_entries.division_id and d.is_personal) and ((select get_my_role()) = 'owner' or division_id = (select get_my_division_id())))
    )
  );

create policy "notebook_entries: author can write, manager/owner can too" on notebook_entries
  for all using (
    org_id = (select get_my_org_id())
    and (author_id = (select auth.uid()) or (select get_my_role()) = 'owner' or ((select get_my_role()) = 'manager' and division_id = (select get_my_division_id())))
  )
  with check (
    org_id = (select get_my_org_id())
    and (author_id = (select auth.uid()) or (select get_my_role()) = 'owner' or ((select get_my_role()) = 'manager' and division_id = (select get_my_division_id())))
  );

-- ------------------------------------------------------------
-- notifications (strictly per-recipient — this is what makes
-- the old single shared "notifications" array into something
-- that actually works for more than one person at a time)
-- ------------------------------------------------------------
create table notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references profiles(id) on delete cascade,
  title text not null,
  meta text,
  icon text,
  color text,
  read boolean not null default false,
  action text,
  created_at timestamptz not null default now()
);

create index notifications_recipient_idx on notifications (recipient_id, created_at desc);

alter table notifications enable row level security;

create policy "notifications: only the recipient can see or manage their own" on notifications
  for all using (recipient_id = (select auth.uid())) with check (recipient_id = (select auth.uid()));

-- Anyone who can see a profile in the org can notify them (e.g. "you were
-- assigned a task") — inserts aren't limited to the recipient themselves.
create policy "notifications: org members can notify each other" on notifications
  for insert with check (
    exists (select 1 from profiles p where p.id = notifications.recipient_id and p.org_id = (select get_my_org_id()))
  );

-- ------------------------------------------------------------
-- ideas (parking lot — org-wide, lightweight)
-- ------------------------------------------------------------
create table ideas (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references organizations(id) on delete cascade,
  title text not null,
  description text,
  submitted_by uuid references profiles(id) on delete set null,
  entry_date date not null default current_date,
  archived boolean not null default false,
  created_at timestamptz not null default now()
);

create index ideas_org_idx on ideas (org_id);

alter table ideas enable row level security;

create policy "ideas: org members can view" on ideas
  for select using (org_id = (select get_my_org_id()));

create policy "ideas: org members can submit" on ideas
  for insert with check (org_id = (select get_my_org_id()) and submitted_by = (select auth.uid()));

create policy "ideas: submitter or owner/manager can update" on ideas
  for update using (
    org_id = (select get_my_org_id())
    and (submitted_by = (select auth.uid()) or (select get_my_role()) in ('owner', 'manager'))
  )
  with check (org_id = (select get_my_org_id()));
