-- AI push notification delivery log, dedupe, and scheduling.
--
-- The AI decides *whether* a notification is worth sending, but the model is
-- not a reliable rate limiter. This table is the durable record that makes the
-- "important things only" promise survive a prompt regression: every decision
-- (sent or skipped) is written here, and the RPCs below read it to enforce
-- cooldowns and deduplication server-side.
--
-- Only the service role reads or writes this table. It deliberately has no
-- policy for the `authenticated` role, so the app cannot read other users'
-- delivery history or forge a row to bypass its own cooldown.

create table if not exists public.ai_notification_log (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  -- 'sent' | 'skipped' | 'failed'; see _shared/notification_decision.ts
  status text not null check (status in ('sent', 'skipped', 'failed')),
  -- Why a push was not sent, or null when it was.
  skip_reason text,
  -- Model's own category (spending/saving/budget/income/general).
  category text,
  priority text,
  deep_link text,
  -- Digit-bucketed hash of the message. Stable across days so the same insight
  -- does not arrive twice; see fingerprintInsight().
  fingerprint text,
  title text,
  body text,
  prompt_version text not null,
  -- The summary window the insight was generated from, e.g. '30d'.
  window_days integer,
  -- How many devices the push reached, and how many were pruned as invalid.
  tokens_sent integer not null default 0,
  tokens_pruned integer not null default 0,
  created_at timestamptz not null default now()
);

-- The cooldown lookup reads one user's most recent rows in time order.
create index if not exists ai_notification_log_user_created_idx
  on public.ai_notification_log (user_id, created_at desc);

-- Dedupe checks a short window of recent fingerprints for one user.
create index if not exists ai_notification_log_user_fingerprint_idx
  on public.ai_notification_log (user_id, fingerprint)
  where fingerprint is not null;

comment on table public.ai_notification_log is
  'Per-decision audit trail for AI push notifications. Service-role only; enforces cooldown and dedupe.';

-- Configurable schedule, so the cron interval is a data change rather than a
-- migration. A single-row table keyed on id = 1.
create table if not exists public.ai_push_config (
  id boolean primary key default true check (id),
  -- pg_cron expression, e.g. '17 6 * * *'. Off by default: enabling a recurring
  -- AI job that calls an external model should be a deliberate act.
  schedule text not null default '17 6 * * *',
  enabled boolean not null default false,
  -- Summary window handed to the model, in days.
  window_days integer not null default 30 check (window_days between 1 and 365),
  -- Overrides for _shared/notification_decision.ts defaults.
  min_priority text not null default 'normal'
    check (min_priority in ('low', 'normal', 'high')),
  min_hours_between_pushes integer not null default 20,
  min_hours_per_category integer not null default 72,
  dedupe_window integer not null default 10,
  respect_quiet_hours boolean not null default true,
  updated_at timestamptz not null default now()
);

comment on table public.ai_push_config is
  'Runtime configuration for the AI push worker: schedule, cooldowns, and dedupe window.';

insert into public.ai_push_config (id) values (true) on conflict (id) do nothing;

-- The only read the worker needs: has this exact message been sent recently?
-- SECURITY DEFINER because the caller is the service role, which could query
-- directly, but routing every read through one function keeps the dedupe rule
-- in a single place.
create or replace function public.ai_push_seen_fingerprints(
  p_user_id uuid,
  p_fingerprint text,
  p_limit integer default 10
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.ai_notification_log
    where user_id = p_user_id
      and fingerprint = p_fingerprint
      and created_at > now() - interval '30 days'
    limit 1
  );
$$;

comment on function public.ai_push_seen_fingerprints is
  'True when this fingerprint was already logged for the user in the last 30 days.';

-- The most recent fingerprints, newest first, for the worker's dedupe check.
create or replace function public.ai_push_recent_fingerprints(
  p_user_id uuid,
  p_limit integer default 10
)
returns text[]
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    array_agg(fingerprint order by created_at desc)
      filter (where fingerprint is not null),
    '{}'
  )
  from (
    select fingerprint, created_at
    from public.ai_notification_log
    where user_id = p_user_id
      and fingerprint is not null
    order by created_at desc
    limit greatest(p_limit, 1)
  ) recent;
$$;

comment on function public.ai_push_recent_fingerprints is
  'The most recent AI push fingerprints for a user, newest first, for dedupe.';
