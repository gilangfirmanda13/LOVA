-- Cleanup: drop the diagnostic-only function used to trace an RLS
-- propagation-delay issue while debugging the staff-write-access
-- migration. Not needed in the schema going forward.
drop function if exists debug_check_project_write(uuid, uuid);
