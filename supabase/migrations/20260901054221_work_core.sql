-- ============================================================
-- LOVA Phase 2: Core work — projects, phases, tasks, general_tasks
--
-- Visibility model: browsing your division's work (projects + tasks)
-- is open to everyone in that division, matching LOVA's existing
-- "operation visibility" UX (the Projects/Division screens have
-- always shown the whole board, not just "my" items) and the
-- product's calm-productivity/transparency philosophy. What's
-- role-gated is *writing*: creating/assigning/deleting is Owner or
-- the division's Manager, though a Staff member can still update a
-- task they're actually on (status, notes, zone) — that's the
-- existing quick-toggle / edit-my-task behavior. Ruang Personal
-- (division.is_personal) is the one exception: those rows are
-- private to their own owner, full stop, regardless of role.
-- ============================================================

create table projects (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references organizations(id) on delete cascade,
  division_id uuid not null references divisions(id),
  title text not null,
  client text,
  priority text not null default 'sedang' check (priority in ('tinggi', 'sedang', 'rendah')),
  effort text not null default 'medium' check (effort in ('low', 'medium', 'high', 'extreme')),
  value numeric not null default 0,
  start_date date,
  deadline date,
  description text,
  active boolean not null default true,
  created_by uuid references profiles(id),
  created_at timestamptz not null default now()
);

create table project_assignees (
  project_id uuid not null references projects(id) on delete cascade,
  profile_id uuid not null references profiles(id) on delete cascade,
  primary key (project_id, profile_id)
);

create table phases (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references projects(id) on delete cascade,
  name text not null,
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);

create table tasks (
  id uuid primary key default gen_random_uuid(),
  phase_id uuid not null references phases(id) on delete cascade,
  name text not null,
  status text not null default 'todo' check (status in ('todo', 'progress', 'review', 'revisi', 'done')),
  pic_id uuid references profiles(id),
  secondary_pic uuid[] not null default '{}',
  priority text check (priority in ('tinggi', 'sedang', 'rendah')),
  effort text check (effort in ('low', 'medium', 'high', 'extreme')),
  start_date date,
  start_time time,
  deadline date,
  end_time time,
  zone text not null default 'later' check (zone in ('focus', 'upnext', 'later')),
  notes text,
  assigned_by uuid references profiles(id),
  original_assigned_by uuid references profiles(id),
  assignment_status text check (assignment_status in ('pending', 'accepted', 'hold', 'denied')),
  assigned_at date,
  pre_toggle_status text,
  completed_at date,
  focus_order int not null default 0,
  created_at timestamptz not null default now()
);

create table task_delegations (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references tasks(id) on delete cascade,
  from_profile uuid references profiles(id),
  to_profile uuid references profiles(id),
  note text,
  created_at timestamptz not null default now()
);

create table general_tasks (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references organizations(id) on delete cascade,
  division_id uuid not null references divisions(id),
  name text not null,
  status text not null default 'todo' check (status in ('todo', 'progress', 'review', 'revisi', 'done')),
  pic_id uuid references profiles(id),
  priority text check (priority in ('tinggi', 'sedang', 'rendah')),
  start_date date,
  start_time time,
  deadline date,
  end_time time,
  zone text not null default 'later' check (zone in ('focus', 'upnext', 'later')),
  notes text,
  assigned_by uuid references profiles(id),
  original_assigned_by uuid references profiles(id),
  assignment_status text check (assignment_status in ('pending', 'accepted', 'hold', 'denied')),
  assigned_at date,
  pre_toggle_status text,
  completed_at date,
  focus_order int not null default 0,
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);

create index projects_org_idx on projects (org_id);
create index projects_division_idx on projects (division_id);
create index phases_project_idx on phases (project_id);
create index tasks_phase_idx on tasks (phase_id);
create index tasks_pic_idx on tasks (pic_id);
create index general_tasks_org_division_idx on general_tasks (org_id, division_id);
create index general_tasks_pic_idx on general_tasks (pic_id);
create index task_delegations_task_idx on task_delegations (task_id);

-- ------------------------------------------------------------
-- Helper: current user's division id (bypasses RLS, mirrors
-- get_my_org_id/get_my_role from the identity migration)
-- ------------------------------------------------------------
create function get_my_division_id()
returns uuid
language sql
security definer
set search_path = public
stable
as $$
  select division_id from profiles where id = auth.uid();
$$;

revoke execute on function get_my_division_id() from public, anon;
grant execute on function get_my_division_id() to authenticated;

-- ------------------------------------------------------------
-- projects
-- ------------------------------------------------------------
alter table projects enable row level security;

create policy "projects: division members can view" on projects
  for select using (
    org_id = (select get_my_org_id())
    and ((select get_my_role()) = 'owner' or division_id = (select get_my_division_id()))
  );

create policy "projects: owner or division manager can write" on projects
  for all using (
    org_id = (select get_my_org_id())
    and ((select get_my_role()) = 'owner' or ((select get_my_role()) = 'manager' and division_id = (select get_my_division_id())))
  )
  with check (
    org_id = (select get_my_org_id())
    and ((select get_my_role()) = 'owner' or ((select get_my_role()) = 'manager' and division_id = (select get_my_division_id())))
  );

-- ------------------------------------------------------------
-- project_assignees
-- ------------------------------------------------------------
alter table project_assignees enable row level security;

create policy "project_assignees: visible with project" on project_assignees
  for select using (
    exists (select 1 from projects p where p.id = project_assignees.project_id)
  );

create policy "project_assignees: owner or division manager can manage" on project_assignees
  for all using (
    exists (
      select 1 from projects p
      where p.id = project_assignees.project_id
        and p.org_id = (select get_my_org_id())
        and ((select get_my_role()) = 'owner' or ((select get_my_role()) = 'manager' and p.division_id = (select get_my_division_id())))
    )
  )
  with check (
    exists (
      select 1 from projects p
      where p.id = project_assignees.project_id
        and p.org_id = (select get_my_org_id())
        and ((select get_my_role()) = 'owner' or ((select get_my_role()) = 'manager' and p.division_id = (select get_my_division_id())))
    )
  );

-- ------------------------------------------------------------
-- phases (visibility/write inherited from the parent project)
-- ------------------------------------------------------------
alter table phases enable row level security;

create policy "phases: visible with project" on phases
  for select using (
    exists (
      select 1 from projects p
      where p.id = phases.project_id
        and p.org_id = (select get_my_org_id())
        and ((select get_my_role()) = 'owner' or p.division_id = (select get_my_division_id()))
    )
  );

create policy "phases: owner or division manager can write" on phases
  for all using (
    exists (
      select 1 from projects p
      where p.id = phases.project_id
        and p.org_id = (select get_my_org_id())
        and ((select get_my_role()) = 'owner' or ((select get_my_role()) = 'manager' and p.division_id = (select get_my_division_id())))
    )
  )
  with check (
    exists (
      select 1 from projects p
      where p.id = phases.project_id
        and p.org_id = (select get_my_org_id())
        and ((select get_my_role()) = 'owner' or ((select get_my_role()) = 'manager' and p.division_id = (select get_my_division_id())))
    )
  );

-- ------------------------------------------------------------
-- tasks (visibility inherited from project/division; a Staff member
-- can also update a task they're actually on, even outside their
-- division-management scope)
-- ------------------------------------------------------------
alter table tasks enable row level security;

create policy "tasks: visible with project" on tasks
  for select using (
    exists (
      select 1 from phases ph join projects p on p.id = ph.project_id
      where ph.id = tasks.phase_id
        and p.org_id = (select get_my_org_id())
        and ((select get_my_role()) = 'owner' or p.division_id = (select get_my_division_id()))
    )
  );

create policy "tasks: owner or division manager can write" on tasks
  for all using (
    exists (
      select 1 from phases ph join projects p on p.id = ph.project_id
      where ph.id = tasks.phase_id
        and p.org_id = (select get_my_org_id())
        and ((select get_my_role()) = 'owner' or ((select get_my_role()) = 'manager' and p.division_id = (select get_my_division_id())))
    )
  )
  with check (
    exists (
      select 1 from phases ph join projects p on p.id = ph.project_id
      where ph.id = tasks.phase_id
        and p.org_id = (select get_my_org_id())
        and ((select get_my_role()) = 'owner' or ((select get_my_role()) = 'manager' and p.division_id = (select get_my_division_id())))
    )
  );

create policy "tasks: assignee can update their own task" on tasks
  for update using (
    pic_id = (select auth.uid()) or (select auth.uid()) = any (secondary_pic)
  )
  with check (
    pic_id = (select auth.uid()) or (select auth.uid()) = any (secondary_pic)
  );

-- ------------------------------------------------------------
-- task_delegations
-- ------------------------------------------------------------
alter table task_delegations enable row level security;

create policy "task_delegations: visible with task" on task_delegations
  for select using (
    exists (select 1 from tasks t where t.id = task_delegations.task_id)
  );

create policy "task_delegations: assignee or manager can insert" on task_delegations
  for insert with check (
    exists (
      select 1 from tasks t
      where t.id = task_delegations.task_id
        and (t.pic_id = (select auth.uid()) or (select auth.uid()) = any (t.secondary_pic))
    )
    or exists (
      select 1 from tasks t join phases ph on ph.id = t.phase_id join projects p on p.id = ph.project_id
      where t.id = task_delegations.task_id
        and p.org_id = (select get_my_org_id())
        and ((select get_my_role()) = 'owner' or ((select get_my_role()) = 'manager' and p.division_id = (select get_my_division_id())))
    )
  );

-- ------------------------------------------------------------
-- general_tasks (Ruang Personal rows are private to their own pic)
-- ------------------------------------------------------------
alter table general_tasks enable row level security;

create policy "general_tasks: division members can view" on general_tasks
  for select using (
    org_id = (select get_my_org_id())
    and (
      exists (select 1 from divisions d where d.id = general_tasks.division_id and d.is_personal)
        and pic_id = (select auth.uid())
      or not exists (select 1 from divisions d where d.id = general_tasks.division_id and d.is_personal)
        and ((select get_my_role()) = 'owner' or division_id = (select get_my_division_id()))
    )
  );

create policy "general_tasks: owner, division manager, or personal owner can write" on general_tasks
  for all using (
    org_id = (select get_my_org_id())
    and (
      pic_id = (select auth.uid())
      or (select get_my_role()) = 'owner'
      or ((select get_my_role()) = 'manager' and division_id = (select get_my_division_id()))
    )
  )
  with check (
    org_id = (select get_my_org_id())
    and (
      pic_id = (select auth.uid())
      or (select get_my_role()) = 'owner'
      or ((select get_my_role()) = 'manager' and division_id = (select get_my_division_id()))
    )
  );
