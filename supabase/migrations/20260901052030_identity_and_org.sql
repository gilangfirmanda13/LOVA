-- ============================================================
-- LOVA Phase 1: Identity & Organization
-- organizations, divisions, profiles, invites + RLS
-- ============================================================

create table organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  onboarded_at timestamptz,
  created_at timestamptz not null default now()
);

create table divisions (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references organizations(id) on delete cascade,
  key text not null,
  name text not null,
  icon text,
  is_personal boolean not null default false,
  created_at timestamptz not null default now(),
  unique (org_id, key)
);

create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  org_id uuid references organizations(id) on delete cascade,
  name text not null,
  role text not null check (role in ('owner', 'manager', 'staff', 'finance_admin')),
  division_id uuid references divisions(id),
  avatar_url text,
  created_at timestamptz not null default now()
);

create index profiles_org_id_idx on profiles (org_id);
create index divisions_org_id_idx on divisions (org_id);

create table invites (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references organizations(id) on delete cascade,
  email text not null,
  role text not null check (role in ('owner', 'manager', 'staff', 'finance_admin')),
  division_id uuid references divisions(id),
  token uuid not null default gen_random_uuid(),
  invited_by uuid references profiles(id),
  accepted_at timestamptz,
  expires_at timestamptz not null default (now() + interval '14 days'),
  created_at timestamptz not null default now(),
  unique (org_id, email)
);

create index invites_token_idx on invites (token);

-- ------------------------------------------------------------
-- Helper: current user's org id, bypasses RLS to avoid recursion
-- ------------------------------------------------------------
create function get_my_org_id()
returns uuid
language sql
security definer
set search_path = public
stable
as $$
  select org_id from profiles where id = auth.uid();
$$;

create function get_my_role()
returns text
language sql
security definer
set search_path = public
stable
as $$
  select role from profiles where id = auth.uid();
$$;

-- ------------------------------------------------------------
-- Onboarding: create_organization (first user / Business Owner)
-- ------------------------------------------------------------
create function create_organization(org_name text, owner_name text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  new_org_id uuid;
begin
  if exists (select 1 from profiles where id = auth.uid()) then
    raise exception 'User already belongs to an organization';
  end if;

  insert into organizations (name) values (org_name) returning id into new_org_id;

  insert into divisions (org_id, key, name, icon) values
    (new_org_id, 'pbd', 'Project & Business Development', 'ti-briefcase'),
    (new_org_id, 'lnd', 'Learning & Development', 'ti-school'),
    (new_org_id, 'creative', 'Creative Team', 'ti-palette');

  insert into divisions (org_id, key, name, icon, is_personal) values
    (new_org_id, 'personal', 'Ruang Personal', 'ti-user', true);

  insert into profiles (id, org_id, name, role)
  values (auth.uid(), new_org_id, owner_name, 'owner');

  return new_org_id;
end;
$$;

-- ------------------------------------------------------------
-- Onboarding: accept_invite (invited team members)
-- ------------------------------------------------------------
create function accept_invite(invite_token uuid, member_name text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  inv invites%rowtype;
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

  insert into profiles (id, org_id, name, role, division_id)
  values (auth.uid(), inv.org_id, member_name, inv.role, inv.division_id);

  update invites set accepted_at = now() where id = inv.id;

  return inv.org_id;
end;
$$;

-- ------------------------------------------------------------
-- RLS
-- ------------------------------------------------------------
alter table organizations enable row level security;
alter table divisions enable row level security;
alter table profiles enable row level security;
alter table invites enable row level security;

-- organizations: members can see their own org; owner can update it
create policy "org: members can view" on organizations
  for select using (id = get_my_org_id());

create policy "org: owner can update" on organizations
  for update using (id = get_my_org_id() and get_my_role() = 'owner');

-- divisions: members can see divisions in their org; owner manages them
create policy "divisions: members can view" on divisions
  for select using (org_id = get_my_org_id());

create policy "divisions: owner can manage" on divisions
  for all using (org_id = get_my_org_id() and get_my_role() = 'owner')
  with check (org_id = get_my_org_id() and get_my_role() = 'owner');

-- profiles: members can see profiles in their own org
create policy "profiles: members can view org" on profiles
  for select using (org_id = get_my_org_id());

-- profiles: a user can update their own row (org_id/role changes are
-- blocked below by trigger, not by this policy, to avoid a self-
-- referential WITH CHECK subquery against the row being written)
create policy "profiles: self update" on profiles
  for update using (id = auth.uid())
  with check (id = auth.uid());

-- profiles: owner can update any profile in their own org (role/division
-- changes, e.g. promoting someone to manager)
create policy "profiles: owner manages org members" on profiles
  for update using (org_id = get_my_org_id() and get_my_role() = 'owner')
  with check (org_id = get_my_org_id());

-- Only an owner may change org_id or role on a profiles row; everyone
-- else's edits to those two columns are silently reverted to the prior
-- value (OLD is always safe to read here — triggers see the pre-update
-- row, unlike a fresh subquery run inside a WITH CHECK expression).
create function protect_profile_privileged_fields()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'owner') then
    new.org_id := old.org_id;
    new.role := old.role;
  end if;
  return new;
end;
$$;

create trigger profiles_protect_privileged
  before update on profiles
  for each row execute function protect_profile_privileged_fields();

-- profiles: allow inserting your own row only via the security-definer
-- onboarding functions above (they run as the table owner and bypass RLS),
-- so no direct insert policy is granted to authenticated users here.

-- invites: only the owner can create/view/manage invites for their org
create policy "invites: owner manages" on invites
  for all using (org_id = get_my_org_id() and get_my_role() = 'owner')
  with check (org_id = get_my_org_id() and get_my_role() = 'owner');

-- No public select policy on invites: an open "select where token = X"
-- policy would still let anyone omit the filter and enumerate every
-- pending invite (and every invited email) org-wide. A newly-signed-up
-- visitor instead calls get_invite_preview() below, which returns only
-- the one row matching their exact token and only the fields the
-- "you're joining <org>" confirmation screen needs.
create function get_invite_preview(invite_token uuid)
returns table (org_name text, role text, division_name text, email text)
language sql
security definer
set search_path = public
stable
as $$
  select o.name, i.role, d.name, i.email
  from invites i
  join organizations o on o.id = i.org_id
  left join divisions d on d.id = i.division_id
  where i.token = invite_token
    and i.accepted_at is null
    and i.expires_at > now();
$$;
