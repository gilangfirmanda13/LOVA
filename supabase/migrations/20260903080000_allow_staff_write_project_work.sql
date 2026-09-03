-- HIGH: Staff could see "Project baru" / "+ Task" / phase controls in the UI
-- and go through the whole creation flow, but the write policies on
-- projects/phases/tasks/project_assignees only ever allowed 'owner' or a
-- division-matching 'manager' -- so every insert a Staff member made was
-- silently rejected by RLS (42501). The client never checked the result
-- and had already pushed the new project/phase/task into local state, so
-- it looked like it worked right up until the next reload replaced local
-- state with the real (unchanged) database rows, and nobody else in the
-- org ever saw it in the meantime. Reported directly: "dinda, hilda, dan
-- staff lain gk bisa buat project, phase dan task, ketika buat hanya
-- muncul di tempat mereka di tempat yg lain gk muncul."
--
-- Fix: extend the same division-scoped write access already granted to
-- 'manager' to 'staff' too, on all four tables involved in project/phase/
-- task creation and editing. This matches how general_tasks already lets
-- any staff member manage tasks in their own division.
drop policy "projects: owner or division manager can write" on projects;
create policy "projects: owner or division member can write" on projects
  for all using (
    org_id = (select get_my_org_id())
    and (
      (select get_my_role()) = 'owner'
      or ((select get_my_role()) in ('manager','staff') and division_id = (select get_my_division_id()))
    )
  )
  with check (
    org_id = (select get_my_org_id())
    and (
      (select get_my_role()) = 'owner'
      or ((select get_my_role()) in ('manager','staff') and division_id = (select get_my_division_id()))
    )
  );

drop policy "project_assignees: owner or division manager can manage" on project_assignees;
create policy "project_assignees: owner or division member can manage" on project_assignees
  for all using (
    exists (
      select 1 from projects p
      where p.id = project_assignees.project_id
        and p.org_id = (select get_my_org_id())
        and ((select get_my_role()) = 'owner' or ((select get_my_role()) in ('manager','staff') and p.division_id = (select get_my_division_id())))
    )
  )
  with check (
    exists (
      select 1 from projects p
      where p.id = project_assignees.project_id
        and p.org_id = (select get_my_org_id())
        and ((select get_my_role()) = 'owner' or ((select get_my_role()) in ('manager','staff') and p.division_id = (select get_my_division_id())))
    )
  );

drop policy "phases: owner or division manager can write" on phases;
create policy "phases: owner or division member can write" on phases
  for all using (
    exists (
      select 1 from projects p
      where p.id = phases.project_id
        and p.org_id = (select get_my_org_id())
        and ((select get_my_role()) = 'owner' or ((select get_my_role()) in ('manager','staff') and p.division_id = (select get_my_division_id())))
    )
  )
  with check (
    exists (
      select 1 from projects p
      where p.id = phases.project_id
        and p.org_id = (select get_my_org_id())
        and ((select get_my_role()) = 'owner' or ((select get_my_role()) in ('manager','staff') and p.division_id = (select get_my_division_id())))
    )
  );

drop policy "tasks: owner or division manager can write" on tasks;
create policy "tasks: owner or division member can write" on tasks
  for all using (
    exists (
      select 1 from phases ph join projects p on p.id = ph.project_id
      where ph.id = tasks.phase_id
        and p.org_id = (select get_my_org_id())
        and ((select get_my_role()) = 'owner' or ((select get_my_role()) in ('manager','staff') and p.division_id = (select get_my_division_id())))
    )
  )
  with check (
    exists (
      select 1 from phases ph join projects p on p.id = ph.project_id
      where ph.id = tasks.phase_id
        and p.org_id = (select get_my_org_id())
        and ((select get_my_role()) = 'owner' or ((select get_my_role()) in ('manager','staff') and p.division_id = (select get_my_division_id())))
    )
  );
