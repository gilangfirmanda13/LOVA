-- SECURITY FIX: accept_invite() previously let anyone holding a valid invite
-- token accept it under ANY email address they control, not just the email
-- the invite was actually sent to. The token's unguessability (a random
-- uuid) was the only real barrier -- if a link ever leaked (forwarded
-- message, screenshot, misdirected email), the holder could sign up with a
-- throwaway email and instantly join the org at whatever role the invite
-- carried (including manager/finance_admin). This binds acceptance to the
-- authenticated user's own verified email matching the invite's target
-- email, case-insensitively (Postgres citext-style comparison via lower()
-- since the column is plain text).
create or replace function accept_invite(invite_token uuid, member_name text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  inv invites%rowtype;
  caller_email text;
begin
  if exists (select 1 from profiles where id = auth.uid()) then
    raise exception 'User already belongs to an organization';
  end if;

  select * into inv from invites where token = invite_token for update;

  if inv.id is null then
    raise exception 'Invalid invite';
  end if;
  if inv.accepted_at is not null then
    raise exception 'Invite already used';
  end if;
  if inv.expires_at < now() then
    raise exception 'Invite expired';
  end if;

  caller_email := auth.email();
  if caller_email is null or lower(caller_email) <> lower(inv.email) then
    raise exception 'This invite was sent to a different email address. Please sign in with % to accept it.', inv.email;
  end if;

  insert into profiles (id, org_id, name, role, division_id)
  values (auth.uid(), inv.org_id, member_name, inv.role, inv.division_id);

  update invites set accepted_at = now() where id = inv.id;

  return inv.org_id;
end;
$$;
