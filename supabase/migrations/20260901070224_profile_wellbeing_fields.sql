-- ============================================================
-- Extend profiles with the fields the app's Account screen and
-- onboarding already know how to edit (job title, hobbies, love
-- language, attachment style, mood/burnout snapshot) + a
-- journal_entries table for the wellbeing journal feature.
--
-- Note: `profiles.role` is the PERMISSION role (owner/manager/
-- staff/finance_admin) — the app's own `userProfile.role` field
-- means something different (a free-text job title, e.g. "Project
-- Manager"). Do not confuse the two; job title gets its own column
-- here (`job_title`) precisely to avoid that collision client-side.
-- ============================================================

alter table profiles
  add column job_title text,
  add column email text,
  add column hobbies text[] not null default '{}',
  add column birth_place text,
  add column birth_date date,
  add column partner text,
  add column favorite_color text,
  add column love_lang_receiving text,
  add column love_lang_giving text,
  add column attach_style text,
  add column mood_key text,
  add column mood_date date,
  add column burnout_pct numeric,
  add column burnout_date date,
  add column profile_completed_at timestamptz;

create table journal_entries (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references profiles(id) on delete cascade,
  entry_date date not null default current_date,
  type text not null,
  note text,
  categories text[] not null default '{}',
  created_at timestamptz not null default now()
);

create index journal_entries_profile_idx on journal_entries (profile_id, entry_date desc);

alter table journal_entries enable row level security;

-- Journal is explicitly private — this is the one table in the whole
-- schema where not even the org owner can read another member's rows.
create policy "journal_entries: strictly your own" on journal_entries
  for all using (profile_id = (select auth.uid())) with check (profile_id = (select auth.uid()));
