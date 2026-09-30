-- Locks the AI push log and config down to the service role.
--
-- The first version of this schema shipped with RLS disabled, which left both
-- tables at Supabase's default grants: anon and authenticated could both read
-- and write them. The publishable anon key ships inside the app, so that meant
-- any user could read every other user's notification history, forge `sent`
-- rows to suppress somebody else's alerts, or delete rows to defeat
-- deduplication and make the daily job send them the same push over and over.

alter table public.ai_notification_log enable row level security;
alter table public.ai_push_config enable row level security;

revoke all on public.ai_notification_log from anon, authenticated;
revoke all on public.ai_push_config from anon, authenticated;

-- Deliberately no policies. Every read and write goes through the Edge
-- Functions' service-role client, which bypasses RLS, so deny-by-default is
-- exactly the intended behaviour: a policy here would only widen access.
grant all on public.ai_notification_log to service_role;
grant all on public.ai_push_config to service_role;

-- The previous migration also added two helper functions that nothing calls;
-- the worker reads the log directly with its service-role client. Left in
-- place they were an active privacy leak rather than dead weight: both are
-- SECURITY DEFINER, both are executable by PUBLIC, and both take an arbitrary
-- p_user_id, so any app user could read another user's recent fingerprints.
-- Those fingerprints embed bucketed message text, e.g.
-- 'budget|/budgets|Budget at risk|You spent NPR 13000 this month', which
-- discloses which alerts a person received and roughly how much they spend.
drop function if exists public.ai_push_seen_fingerprints(uuid, text, integer);
drop function if exists public.ai_push_recent_fingerprints(uuid, integer);
