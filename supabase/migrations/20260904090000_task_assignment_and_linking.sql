-- Feature batch (explicit request):
-- 1) general_tasks needs a secondary PIC (mirroring tasks.secondary_pic),
--    an optional link to a project, and an optional client label so a
--    standalone task can still be filtered/grouped by client.
-- 2) rituals needs a secondary PIC list too, for the same "PIC utama +
--    PIC sekunder everywhere" request.
alter table general_tasks add column if not exists secondary_pic uuid[] not null default '{}';
alter table general_tasks add column if not exists project_id uuid references projects(id) on delete set null;
alter table general_tasks add column if not exists client text;

alter table rituals add column if not exists secondary_pic_ids uuid[] not null default '{}';
