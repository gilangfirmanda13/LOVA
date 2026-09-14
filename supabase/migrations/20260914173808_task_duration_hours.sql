-- Per-task estimated duration (hours), independent of the existing project-level `effort`
-- bucket. Nullable/additive on both tables -- existing rows are unaffected, and capacity
-- math in the app falls back to the old project-effort/priority estimate when a task has
-- no duration set yet.
alter table public.tasks add column if not exists duration_hours numeric;
alter table public.general_tasks add column if not exists duration_hours numeric;

comment on column public.tasks.duration_hours is 'Estimated hours to complete this task, set by the assigner/PIC. Optional.';
comment on column public.general_tasks.duration_hours is 'Estimated hours to complete this task, set by the assigner/PIC. Optional.';
