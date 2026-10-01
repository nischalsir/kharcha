-- Data-driven reminders (budget alerts, upcoming bills, friend debts, overdue
-- payments, pasal month end, daily and weekly summaries), sent by the
-- push-reminders Edge Function.

-- One row per delivered reminder item. The primary key is the dedupe rule: the
-- worker claims a key before sending, so a retried or overlapping run cannot
-- notify twice for the same budget level, bill, or overdue week.
create table if not exists public.push_reminder_log (
  user_id uuid not null references auth.users (id) on delete cascade,
  key text not null,
  category text not null,
  created_at timestamptz not null default now(),
  primary key (user_id, key)
);

comment on table public.push_reminder_log is
  'Dedupe keys for push-reminders. Service-role only.';

create index if not exists push_reminder_log_user_created_idx
  on public.push_reminder_log (user_id, created_at desc);

-- Same posture as ai_notification_log: service role only, no client policies.
alter table public.push_reminder_log enable row level security;
revoke all on public.push_reminder_log from anon, authenticated;
grant all on public.push_reminder_log to service_role;

-- Same shape and secret as run_ai_daily_buddy().
create or replace function public.run_push_reminders()
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
    raise exception 'ai_push_worker has no secret; reminders cannot be invoked';
  end if;

  v_url := current_setting('app.settings.supabase_url', true);
  if v_url is null or v_url = '' then
    v_url := 'https://eazyeerunsxfyecjpyox.supabase.co';
  end if;

  perform net.http_post(
    url := v_url || '/functions/v1/push-reminders',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-kharcha-internal-secret', v_secret
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 120000
  );
end;
$$;

revoke all on function public.run_push_reminders() from public, anon, authenticated;
grant execute on function public.run_push_reminders() to service_role;

select cron.unschedule(jobid) from cron.job where jobname = 'push-reminders';

-- Hourly, a couple of minutes past so it does not start with ai-daily-buddy.
-- The worker matches each user's local hour, and every local hour falls inside
-- exactly one run, so hourly is the least frequent schedule that never skips a
-- user's reminder or summary hour.
select cron.schedule(
  'push-reminders',
  '2 * * * *',
  $$select public.run_push_reminders()$$
);
