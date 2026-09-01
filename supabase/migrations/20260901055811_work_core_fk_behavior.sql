-- ============================================================
-- Fix: deleting a profile (someone leaving the org) was blocked
-- outright if they were referenced anywhere as a pic/assigner —
-- discovered while cleaning up Phase 2 test data. A person leaving
-- should unassign their work, not make it impossible to remove them.
-- ============================================================

alter table tasks drop constraint tasks_pic_id_fkey;
alter table tasks add constraint tasks_pic_id_fkey foreign key (pic_id) references profiles(id) on delete set null;

alter table tasks drop constraint tasks_assigned_by_fkey;
alter table tasks add constraint tasks_assigned_by_fkey foreign key (assigned_by) references profiles(id) on delete set null;

alter table tasks drop constraint tasks_original_assigned_by_fkey;
alter table tasks add constraint tasks_original_assigned_by_fkey foreign key (original_assigned_by) references profiles(id) on delete set null;

alter table general_tasks drop constraint general_tasks_pic_id_fkey;
alter table general_tasks add constraint general_tasks_pic_id_fkey foreign key (pic_id) references profiles(id) on delete set null;

alter table general_tasks drop constraint general_tasks_assigned_by_fkey;
alter table general_tasks add constraint general_tasks_assigned_by_fkey foreign key (assigned_by) references profiles(id) on delete set null;

alter table general_tasks drop constraint general_tasks_original_assigned_by_fkey;
alter table general_tasks add constraint general_tasks_original_assigned_by_fkey foreign key (original_assigned_by) references profiles(id) on delete set null;

alter table projects drop constraint projects_created_by_fkey;
alter table projects add constraint projects_created_by_fkey foreign key (created_by) references profiles(id) on delete set null;

alter table task_delegations drop constraint task_delegations_from_profile_fkey;
alter table task_delegations add constraint task_delegations_from_profile_fkey foreign key (from_profile) references profiles(id) on delete set null;

alter table task_delegations drop constraint task_delegations_to_profile_fkey;
alter table task_delegations add constraint task_delegations_to_profile_fkey foreign key (to_profile) references profiles(id) on delete set null;
