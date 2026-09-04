-- Product decision (explicit request): LOVA's divisions collaborate on
-- cross-divisional work constantly, and the previous division-scoped
-- read/write model was actively getting in the way -- a PBD member
-- couldn't see or touch L&D's or Creative's projects/tasks at all, and
-- only owner/manager could create/assign work or manage rituals. This
-- migration removes the division and role gating across the core work
-- surface: any authenticated member of the org can now read and write
-- projects, phases, tasks, project assignees, non-personal general
-- tasks, task/general-task delegations, rituals, and events, regardless
-- of their own division or role. The remaining boundary is org_id
-- (multi-tenant isolation, unchanged) and each user's own personal
-- space (general_tasks tagged to the `is_personal` division stay
-- readable/writable only by their own pic -- that's a private scratch
-- space, not "divisional work", and stays that way).

-- ------------------------------------------------------------
-- projects
-- ------------------------------------------------------------
drop policy "projects: division members can view" on projects;
create policy "projects: org members can view" on projects
  for select using (org_id = (select get_my_org_id()));

drop policy "projects: owner or division member can write" on projects;
create policy "projects: org members can write" on projects
  for all using (org_id = (select get_my_org_id()))
  with check (org_id = (select get_my_org_id()));

-- ------------------------------------------------------------
-- project_assignees
-- ------------------------------------------------------------
drop policy "project_assignees: owner or division member can manage" on project_assignees;
create policy "project_assignees: org members can manage" on project_assignees
  for all using (
    exists (select 1 from projects p where p.id = project_assignees.project_id and p.org_id = (select get_my_org_id()))
  )
  with check (
    exists (select 1 from projects p where p.id = project_assignees.project_id and p.org_id = (select get_my_org_id()))
  );

-- ------------------------------------------------------------
-- phases (visibility/write inherited from the parent project)
-- ------------------------------------------------------------
drop policy "phases: visible with project" on phases;
create policy "phases: visible with project" on phases
  for select using (
    exists (select 1 from projects p where p.id = phases.project_id and p.org_id = (select get_my_org_id()))
  );

drop policy "phases: owner or division member can write" on phases;
create policy "phases: org members can write" on phases
  for all using (
    exists (select 1 from projects p where p.id = phases.project_id and p.org_id = (select get_my_org_id()))
  )
  with check (
    exists (select 1 from projects p where p.id = phases.project_id and p.org_id = (select get_my_org_id()))
  );

-- ------------------------------------------------------------
-- tasks (the narrower "assignee can update their own task" policy
-- from work_core.sql is now redundant but harmless -- left in place)
-- ------------------------------------------------------------
drop policy "tasks: visible with project" on tasks;
create policy "tasks: visible with project" on tasks
  for select using (
    exists (
      select 1 from phases ph join projects p on p.id = ph.project_id
      where ph.id = tasks.phase_id and p.org_id = (select get_my_org_id())
    )
  );

drop policy "tasks: owner or division member can write" on tasks;
create policy "tasks: org members can write" on tasks
  for all using (
    exists (
      select 1 from phases ph join projects p on p.id = ph.project_id
      where ph.id = tasks.phase_id and p.org_id = (select get_my_org_id())
    )
  )
  with check (
    exists (
      select 1 from phases ph join projects p on p.id = ph.project_id
      where ph.id = tasks.phase_id and p.org_id = (select get_my_org_id())
    )
  );

-- ------------------------------------------------------------
-- task_delegations
-- ------------------------------------------------------------
drop policy "task_delegations: assignee or manager can insert" on task_delegations;
create policy "task_delegations: org members can insert" on task_delegations
  for insert with check (
    exists (
      select 1 from tasks t join phases ph on ph.id = t.phase_id join projects p on p.id = ph.project_id
      where t.id = task_delegations.task_id and p.org_id = (select get_my_org_id())
    )
  );

-- ------------------------------------------------------------
-- general_tasks (Ruang Personal stays private to its own pic --
-- everything else is now org-wide, not just division-wide)
-- ------------------------------------------------------------
drop policy "general_tasks: division members can view" on general_tasks;
create policy "general_tasks: org members can view non-personal, pic can view their own" on general_tasks
  for select using (
    org_id = (select get_my_org_id())
    and (
      exists (select 1 from divisions d where d.id = general_tasks.division_id and d.is_personal)
        and pic_id = (select auth.uid())
      or not exists (select 1 from divisions d where d.id = general_tasks.division_id and d.is_personal)
    )
  );

drop policy "general_tasks: owner, division manager, or personal owner can write" on general_tasks;
create policy "general_tasks: org members can write non-personal, pic can write their own" on general_tasks
  for all using (
    org_id = (select get_my_org_id())
    and (
      pic_id = (select auth.uid())
      or not exists (select 1 from divisions d where d.id = general_tasks.division_id and d.is_personal)
    )
  )
  with check (
    org_id = (select get_my_org_id())
    and (
      pic_id = (select auth.uid())
      or not exists (select 1 from divisions d where d.id = general_tasks.division_id and d.is_personal)
    )
  );

-- ------------------------------------------------------------
-- general_task_delegations
-- ------------------------------------------------------------
drop policy "general_task_delegations: assignee or manager can insert" on general_task_delegations;
create policy "general_task_delegations: org members can insert" on general_task_delegations
  for insert with check (
    exists (
      select 1 from general_tasks g
      where g.id = general_task_delegations.general_task_id and g.org_id = (select get_my_org_id())
    )
  );

-- ------------------------------------------------------------
-- rituals (visibility was already org-wide; write was owner/manager
-- only -- open it to every role, matching "siapapun bisa kasih
-- assignment ritual")
-- ------------------------------------------------------------
drop policy "rituals: owner or manager can write" on rituals;
create policy "rituals: org members can write" on rituals
  for all using (org_id = (select get_my_org_id()))
  with check (org_id = (select get_my_org_id()));

-- ------------------------------------------------------------
-- events (same shape as projects/tasks: org-wide read, org-wide
-- write regardless of role or division)
-- ------------------------------------------------------------
drop policy "events: division members can view" on events;
create policy "events: org members can view" on events
  for select using (org_id = (select get_my_org_id()));

drop policy "events: owner or division manager can write" on events;
create policy "events: org members can write" on events
  for all using (org_id = (select get_my_org_id()))
  with check (org_id = (select get_my_org_id()));
