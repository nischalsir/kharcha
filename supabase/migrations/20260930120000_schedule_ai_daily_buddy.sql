-- The flame's daily greetings: good morning at 06:00, good night at 22:00, and
-- a couple of AI-written nudges at random times in between, all in the user's
-- local time.
--
-- The job runs every 15 minutes because the worker decides per user whether a
-- slot is due in *their* local quarter-hour (Nepal is +5:45, so its 06:00 is
-- 00:15 UTC). Runs where nothing is due cost two small queries and no model
-- call.

alter table public.ai_push_config
  add column if not exists buddy_enabled boolean not null default true,
  add column if not exists buddy_daytime_per_day integer not null default 2
    check (buddy_daytime_per_day between 0 and 6);

comment on column public.ai_push_config.buddy_enabled is
  'Kill switch for the ai-daily-buddy worker (morning/night/daytime greetings).';
comment on column public.ai_push_config.buddy_daytime_per_day is
  'How many random daytime nudges each user gets between 09:00 and 21:00 local.';

-- Same shape and secret as run_ai_push_digest().
create or replace function public.run_ai_daily_buddy()
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
    raise exception 'ai_push_worker has no secret; the buddy cannot be invoked';
  end if;

  v_url := current_setting('app.settings.supabase_url', true);
  if v_url is null or v_url = '' then
    v_url := 'https://eazyeerunsxfyecjpyox.supabase.co';
  end if;

  perform net.http_post(
    url := v_url || '/functions/v1/ai-daily-buddy',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-kharcha-internal-secret', v_secret
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 120000
  );
end;
$$;

revoke all on function public.run_ai_daily_buddy() from public, anon, authenticated;
grant execute on function public.run_ai_daily_buddy() to service_role;

select cron.unschedule(jobid) from cron.job where jobname = 'ai-daily-buddy';

select cron.schedule(
  'ai-daily-buddy',
  '*/15 * * * *',
  $$select public.run_ai_daily_buddy()$$
);
