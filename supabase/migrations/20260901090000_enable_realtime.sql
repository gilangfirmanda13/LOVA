-- Enables Postgres Changes (Realtime) on the tables the app needs to
-- live-sync across devices/teammates without a manual refresh. Events
-- are authorized per-connection using each table's existing RLS SELECT
-- policy, so this does not widen what any user can see -- it only lets
-- rows they could already read stream to them as they change.
alter publication supabase_realtime add table
  projects,
  phases,
  tasks,
  task_delegations,
  general_tasks,
  general_task_delegations,
  events,
  approval_requests,
  rituals,
  ritual_completions,
  notebook_entries,
  notifications,
  ideas,
  journal_entries;
