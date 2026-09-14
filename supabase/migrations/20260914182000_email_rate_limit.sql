-- SECURITY FIX: send-notification-email and send-invite-email had no
-- throttling at all -- any authenticated org member (not just owners)
-- could loop task-reassignment/@mentions to spam Resend calls, and an
-- owner could loop invite creation to spam arbitrary addresses. This is a
-- minimal log-and-count table the two edge functions check before sending
-- and write to after every attempt (successful or not, so retry-looping
-- past a failure doesn't bypass the limit). Not exposed via any client
-- policy -- only ever touched by edge functions using the service-role
-- key, so RLS on it is enabled with zero policies (deny-all to anon/
-- authenticated, exactly as intended).
create table email_rate_limit (
  id uuid primary key default gen_random_uuid(),
  caller_id uuid not null references profiles(id) on delete cascade,
  fn text not null,
  created_at timestamptz not null default now()
);
alter table email_rate_limit enable row level security;
create index email_rate_limit_caller_fn_idx on email_rate_limit (caller_id, fn, created_at);
