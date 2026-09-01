-- Bug found via multi-persona testing: delegating a task you own to
-- someone else silently failed. USING correctly lets the CURRENT pic
-- start the update (old row: pic_id = them), but WITH CHECK re-ran the
-- same "pic_id = me" condition against the NEW row -- which is false
-- by definition once you reassign it away from yourself, since you're
-- neither org owner nor the relevant division manager. Every staff-
-- level delegation of a self-owned task was rejected by Postgres
-- (42501) while the app's optimistic local update made it look like
-- it worked, leaving the UI and database permanently out of sync.
--
-- Fix: WITH CHECK only needs to keep the row inside the same tenant/
-- project scope -- USING already gated who may touch the row in the
-- first place (its own pic, the org owner, or the relevant division
-- manager), so re-deriving ownership against the post-update row is
-- both wrong (blocks legitimate reassignment) and redundant.

drop policy "general_tasks: owner, division manager, or personal owner can write" on general_tasks;
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
  );

drop policy "tasks: assignee can update their own task" on tasks;
create policy "tasks: assignee can update their own task" on tasks
  for update using (
    pic_id = (select auth.uid()) or (select auth.uid()) = any (secondary_pic)
  )
  with check (
    exists (
      select 1 from phases ph join projects p on p.id = ph.project_id
      where ph.id = tasks.phase_id
        and p.org_id = (select get_my_org_id())
    )
  );
