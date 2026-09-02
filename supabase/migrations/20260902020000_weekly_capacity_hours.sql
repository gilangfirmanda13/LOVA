-- The "Beban Kerja Minggu Ini" (workload) widget's available-hours field
-- was entirely client-side and hardcoded per demo persona name (e.g.
-- 'Gilang':{available:34}) -- editing it in Account settings updated
-- the in-memory value for that page load only, then silently reverted
-- to the hardcoded demo number on next reload since nothing persisted.
alter table profiles add column if not exists weekly_capacity_hours integer not null default 40;
