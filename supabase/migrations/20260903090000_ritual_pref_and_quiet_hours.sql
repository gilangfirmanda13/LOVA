-- HIGH: the Account screen's "Ritual divisi yang ditampilkan" select and
-- the whole "Quiet Hours" section (enable toggle + start/end time) only
-- ever wrote to local JS variables (userProfile.ritualDivision, and a
-- bare `var quietHours = {...}` never touched by LovaDB at all) -- there
-- was no column to persist them to and no updateProfile() call for
-- either, so every change silently reset to the default on next load.
-- Reported directly: "di profil saat ngerubah isi profil seperti divisi,
-- ritual dan quiet hour ketika di save dan refresh balik lagi ke semula."
alter table profiles add column if not exists ritual_division_id uuid references divisions(id);
alter table profiles add column if not exists quiet_hours_enabled boolean not null default false;
alter table profiles add column if not exists quiet_hours_start text not null default '18:00';
alter table profiles add column if not exists quiet_hours_end text not null default '08:00';
