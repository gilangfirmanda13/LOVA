-- Follow-up to 20260901090000_enable_realtime.sql: also stream profile
-- changes (name, job title, avatar, division moves) so a teammate's
-- edits show up live for everyone else instead of only after reload.
alter publication supabase_realtime add table profiles;
