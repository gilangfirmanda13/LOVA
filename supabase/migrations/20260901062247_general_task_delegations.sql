-- ============================================================
-- Mirror of task_delegations for general_tasks — the original
-- task_delegations table only referenced `tasks` (project tasks),
-- but the app's own delegate flow (Missed Tasks) runs on both
-- project and general tasks. Same visibility/insert rules as
-- task_delegations, adapted to general_tasks' RLS shape.
-- ============================================================

create table general_task_delegations (
  id uuid primary key default gen_random_uuid(),
  general_task_id uuid not null references general_tasks(id) on delete cascade,
  from_profile uuid references profiles(id) on delete set null,
  to_profile uuid references profiles(id) on delete set null,
  note text,
  created_at timestamptz not null default now()
);

create index general_task_delegations_task_idx on general_task_delegations (general_task_id);

alter table general_task_delegations enable row level security;

create policy "general_task_delegations: visible with task" on general_task_delegations
  for select using (
    exists (select 1 from general_tasks g where g.id = general_task_delegations.general_task_id)
  );

create policy "general_task_delegations: assignee or manager can insert" on general_task_delegations
  for insert with check (
    exists (
      select 1 from general_tasks g
      where g.id = general_task_delegations.general_task_id
        and (g.pic_id = (select auth.uid())
          or (g.org_id = (select get_my_org_id()) and ((select get_my_role()) = 'owner' or ((select get_my_role()) = 'manager' and g.division_id = (select get_my_division_id())))))
    )
  );
