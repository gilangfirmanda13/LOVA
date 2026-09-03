-- CRITICAL: "profiles: self update" only ever checked `id = auth.uid()` --
-- i.e. "you may update your own row" -- with NO restriction on WHICH
-- columns you're allowed to change. Since `role` (owner/manager/staff/
-- finance_admin) and `org_id` live on the same row, any authenticated
-- user -- including the lowest-privilege 'staff' account -- could call
--   supabase.from('profiles').update({ role: 'owner' }).eq('id', myId)
-- and self-promote to full org-owner control (invite/remove members,
-- see everything), or worse, rewrite their own `org_id` to hop into a
-- completely different organization's tenant, bypassing every other
-- RLS policy in the schema (all of which trust profiles.role/org_id
-- as the source of truth via get_my_role()/get_my_org_id()).
--
-- RLS alone can't restrict individual columns on an UPDATE policy (the
-- WITH CHECK clause only sees the proposed new row, not a diff against
-- the old one), so this needs a trigger. The "owner manages org
-- members" policy is unaffected: it only fires when an owner edits a
-- DIFFERENT member's row, so the id=auth.uid() guard below doesn't
-- apply to that legitimate path.
create or replace function prevent_self_role_org_escalation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.id = (select auth.uid()) then
    if new.role is distinct from old.role then
      raise exception 'cannot change your own role';
    end if;
    if new.org_id is distinct from old.org_id then
      raise exception 'cannot change your own org_id';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_prevent_self_role_org_escalation on profiles;
create trigger trg_prevent_self_role_org_escalation
before update on profiles
for each row execute function prevent_self_role_org_escalation();

-- HIGH: "approval_requests: approver or owner can decide" let the
-- REQUESTER update their own request (USING included requested_by =
-- auth.uid(), for legitimate reasons like editing/withdrawing a still-
-- pending request), but WITH CHECK only verified org_id -- nothing
-- stopped the requester from directly setting status='approved' (or
-- populating approved_by_ids with their own id) on their own budget/
-- leave/overtime request, self-approving it without any real approver
-- ever acting. Owners and listed approvers still need full latitude to
-- change status; a plain requester now may only touch their request
-- while it stays 'pending'.
drop policy "approval_requests: approver or owner can decide" on approval_requests;
create policy "approval_requests: approver or owner can decide" on approval_requests
  for update using (
    org_id = (select get_my_org_id())
    and (
      (select get_my_role()) = 'owner'
      or requested_by = (select auth.uid())
      or (select auth.uid()) = any (approver_ids)
    )
  )
  with check (
    org_id = (select get_my_org_id())
    and (
      (select get_my_role()) = 'owner'
      or (select auth.uid()) = any (approver_ids)
      or (requested_by = (select auth.uid()) and status = 'pending')
    )
  );
