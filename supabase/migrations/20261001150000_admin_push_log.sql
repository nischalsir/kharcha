-- Audit log for notifications sent from the Kharcha Push Console.
--
-- `send-push` already has `ai_push_log` for its own automated sends. This is a
-- separate table because the console is an operator tool: its rows answer
-- "what did I send, to whom, and did it land", and mixing them with the
-- machine-generated digest log would make that question harder to answer.
--
-- Service-role only, like `ai_push_worker`. The console reads history through
-- the `admin-push` Edge Function, never directly, so no client policy is needed
-- and there is no path by which a user could read or forge an audit row.
create table if not exists public.admin_push_log (
  id uuid primary key default gen_random_uuid(),
  admin_email text not null,
  category text not null,
  channel_id text,
  title text not null,
  body text not null,
  -- 'broadcast' | 'users': which audience selector was used.
  audience text not null,
  -- Token count after preference filtering, i.e. what FCM was actually asked to
  -- deliver to.
  recipients integer not null default 0,
  sent integer not null default 0,
  failed integer not null default 0,
  removed_tokens integer not null default 0,
  -- Extra data-string fields the operator attached, for diagnosis after the fact.
  payload_data jsonb,
  started_at timestamptz not null default now()
);

comment on table public.admin_push_log is
  'Operator-initiated push sends from the Kharcha Push Console. Written by the admin-push Edge Function.';

-- The console lists newest-first and filters by category in the UI.
create index if not exists admin_push_log_started_at_idx
  on public.admin_push_log (started_at desc);

create index if not exists admin_push_log_category_idx
  on public.admin_push_log (category);

revoke all on public.admin_push_log from anon, authenticated;

alter table public.admin_push_log enable row level security;

-- No policies on purpose: service role bypasses RLS, and no client role should
-- ever read this table. Access is exclusively via the admin-push function, which
-- re-checks the caller's admin email on every request.
