-- ============================================================
-- LOVA Phase 1 hardening — findings from `supabase db advisors`
-- ============================================================

-- ------------------------------------------------------------
-- 1) Lock down function EXECUTE grants.
-- New functions are PUBLIC-executable by default in Postgres, and
-- Supabase's default privileges additionally hand that to `anon` and
-- `authenticated` for anything in the exposed `public` schema. Only
-- get_invite_preview is meant to be called by a not-yet-authenticated
-- visitor (an invite link, before they have an account); everything
-- else should require a real session, and the trigger function should
-- never be called directly at all.
-- ------------------------------------------------------------
revoke execute on function get_my_org_id() from public, anon;
revoke execute on function get_my_role() from public, anon;
revoke execute on function create_organization(text, text) from public, anon;
revoke execute on function accept_invite(uuid, text) from public, anon;
revoke execute on function protect_profile_privileged_fields() from public, anon, authenticated;

grant execute on function get_my_org_id() to authenticated;
grant execute on function get_my_role() to authenticated;
grant execute on function create_organization(text, text) to authenticated;
grant execute on function accept_invite(uuid, text) to authenticated;
-- get_invite_preview keeps its default anon + authenticated execute grant.

-- ------------------------------------------------------------
-- 2) Wrap auth.<function>() / helper-function calls in RLS policies
-- with `(select ...)` so Postgres evaluates them once per query
-- instead of once per row (see auth_rls_initplan advisor finding).
-- ------------------------------------------------------------
drop policy "profiles: self update" on profiles;
create policy "profiles: self update" on profiles
  for update using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

drop policy "org: members can view" on organizations;
create policy "org: members can view" on organizations
  for select using (id = (select get_my_org_id()));

drop policy "org: owner can update" on organizations;
create policy "org: owner can update" on organizations
  for update using (id = (select get_my_org_id()) and (select get_my_role()) = 'owner');

drop policy "divisions: members can view" on divisions;
create policy "divisions: members can view" on divisions
  for select using (org_id = (select get_my_org_id()));

drop policy "divisions: owner can manage" on divisions;
create policy "divisions: owner can manage" on divisions
  for all using (org_id = (select get_my_org_id()) and (select get_my_role()) = 'owner')
  with check (org_id = (select get_my_org_id()) and (select get_my_role()) = 'owner');

drop policy "profiles: members can view org" on profiles;
create policy "profiles: members can view org" on profiles
  for select using (org_id = (select get_my_org_id()));

drop policy "profiles: owner manages org members" on profiles;
create policy "profiles: owner manages org members" on profiles
  for update using (org_id = (select get_my_org_id()) and (select get_my_role()) = 'owner')
  with check (org_id = (select get_my_org_id()));

drop policy "invites: owner manages" on invites;
create policy "invites: owner manages" on invites
  for all using (org_id = (select get_my_org_id()) and (select get_my_role()) = 'owner')
  with check (org_id = (select get_my_org_id()) and (select get_my_role()) = 'owner');
