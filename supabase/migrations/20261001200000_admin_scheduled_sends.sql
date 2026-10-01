-- Scheduled sends for the Kharcha Push Console.
--
-- The console can already send immediately, but several of its categories are
-- inherently future-dated: a weekly summary is worth sending Monday morning, not
-- at the moment the operator remembers it. This table is the queue for those.
--
-- Separate from `admin_push_log`, which is an append-only record of what already
-- went out. Keeping them apart matters: history must never be mutated or deleted
-- by a reschedule, whereas a pending send is expected to change or be cancelled
-- right up until it fires.
--
-- Service-role only, same posture as `admin_push_log`. There is no path by which
-- a client role reads or writes this table; the `admin-push` function re-checks
-- the caller's admin email on every request.
create table if not exists public.admin_scheduled_sends (
  id uuid primary key default gen_random_uuid(),
  -- Who queued it. An audit field rather than an authorization one: the
  -- function re-validates the caller on the request, not against this column.
  admin_email text not null,
  category text not null,
  title text not null,
  body text not null,
  -- 'broadcast' | 'users', matching admin_push_log so one renderer reads both.
  audience text not null default 'users',
  -- Empty for a broadcast. Kept as a jsonb array of uuid-as-text rather than a
  -- join table: the set is fixed at queue time and read exactly once when the
  -- send fires, so normalising it would buy nothing and cost a second write path.
  user_ids text[] not null default '{}',
  -- Extra FCM data-string fields, forwarded verbatim at send time.
  payload_data jsonb,
  -- Operator-facing zone context ('Asia/Kathmandu', or the UTC offset the console
  -- reads from the device when the phone reports no IANA name). Stored alongside
  -- the instant so a row stays interpretable if it is ever inspected by hand.
  -- `send_at` is the authoritative value and the only one dispatch reads;
  -- `timezone` is context, never a second source of truth for the fire time.
  send_at timestamptz not null,
  timezone text not null default 'UTC',
  -- 'pending' | 'sending' | 'sent' | 'cancelled' | 'failed'
  --
  -- 'sending' is the dispatcher's claim: it is written before any FCM call so a
  -- second cron tick that overlaps a slow one cannot pick up the same row. It is
  -- transient and never meant to be observed, but it has to be a legal value or
  -- the claim write fails.
  --
  -- Terminal states are kept rather than deleted, so an operator can see that a
  -- send they queued at 09:00 was cancelled at 09:01 instead of watching it
  -- silently vanish from the list.
  status text not null default 'pending'
    check (status in ('pending', 'sending', 'sent', 'cancelled', 'failed')),
  -- Populated when the dispatcher runs. Null while pending.
  completed_at timestamptz,
  -- Dispatcher outcome, so a failure is diagnosable in the list rather than
  -- only in function logs.
  result jsonb,
  created_at timestamptz not null default now()
);

comment on table public.admin_scheduled_sends is
  'Future-dated push sends queued from the Kharcha Push Console. Dispatched by the admin-push function via run_admin_scheduled_sends().';

-- Serves both pending-row lookups: the dispatcher's claim query (pending rows due
-- at or before now, oldest first) and the console's "upcoming" list. Partial,
-- because the table is append-mostly and terminal rows are never scanned again --
-- keeping them out of the index keeps it small.
create index if not exists admin_scheduled_sends_due_idx
  on public.admin_scheduled_sends (send_at)
  where status = 'pending';

alter table public.admin_scheduled_sends enable row level security;
revoke all on public.admin_scheduled_sends from anon, authenticated;
grant all on public.admin_scheduled_sends to service_role;

-- pg_cron -> admin-push dispatcher.
--
-- Same shape and secret as run_push_reminders(): the database holds the only
-- copy of the shared secret and posts it server-to-server, so there is no window
-- where the two sides disagree and every tick silently 401s.
create or replace function public.run_admin_scheduled_sends()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_secret text;
  v_url text;
begin
  select internal_secret into v_secret from public.ai_push_worker where id;
  if v_secret is null then
    raise exception 'ai_push_worker has no secret; scheduled sends cannot be invoked';
  end if;

  v_url := current_setting('app.settings.supabase_url', true);
  if v_url is null or v_url = '' then
    v_url := 'https://eazyeerunsxfyecjpyox.supabase.co';
  end if;

  perform net.http_post(
    url := v_url || '/functions/v1/admin-push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-kharcha-internal-secret', v_secret
    ),
    body := jsonb_build_object('action', 'dispatch', 'internal', true)::jsonb,
    timeout_milliseconds := 120000
  );
end;
$$;

revoke all on function public.run_admin_scheduled_sends() from public, anon, authenticated;
grant execute on function public.run_admin_scheduled_sends() to service_role;

select cron.unschedule(jobid) from cron.job where jobname = 'admin-scheduled-sends';

-- Every minute. A send queued for 10:07 should leave at 10:07, not at 10:15,
-- and the claim query is a single indexed scan over pending rows, so the cost
-- of an empty tick is one index lookup.
select cron.schedule(
  'admin-scheduled-sends',
  '* * * * *',
  $$select public.run_admin_scheduled_sends()$$
);
