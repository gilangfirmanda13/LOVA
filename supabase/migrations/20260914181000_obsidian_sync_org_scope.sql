-- SECURITY FIX: the obsidian-sync edge function reads across ALL
-- organizations with the service-role key (bypassing RLS) and had no
-- org_id filter at all -- fine while only one org existed, but the app
-- explicitly supports self-serve signup, so the moment a second org
-- appeared its data would get pulled into Lenusa's own committed vault
-- with zero isolation. This column lets the function scope itself to
-- exactly one organization instead of dumping every tenant.
--
-- Set on the very first organization ever created in this project, which
-- is Lenusa's own (org creation predates any other org by construction --
-- every org created after this migration runs defaults to false and is
-- correctly excluded from the sync).
alter table organizations add column if not exists obsidian_sync_enabled boolean not null default false;

update organizations
set obsidian_sync_enabled = true
where id = (select id from organizations order by created_at asc limit 1);
