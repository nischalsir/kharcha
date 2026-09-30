-- Schedules the AI push digest through pg_cron.
--
-- The job authenticates with a shared secret held in this table rather than
-- with the service_role key. Two reasons: the service key is not readable from
-- SQL, and putting it in the database to satisfy a scheduler would be a strictly
-- larger blast radius than a single-purpose secret. The matching Edge Function
-- is deployed with --no-verify-jwt, so this secret is the only thing standing
-- between the public internet and the function that can send notifications to
-- every user. It is therefore generated at full length here and the function
-- env is set to the same value.
--
-- To rotate: update the row below, then redeploy the function env with the new
-- value. Both must change together or the job 401s and sends nothing.
create table if not exists public.ai_push_worker (
  id boolean primary key default true,
  internal_secret text not null,
  updated_at timestamptz not null default now(),
  constraint ai_push_worker_singleton check (id)
);

comment on table public.ai_push_worker is
  'Shared secret for the scheduled AI push worker. Never exposed to clients.';

-- Generated once, on first migration. ON CONFLICT DO NOTHING keeps a re-run
-- stable, so a replayed migration does not silently break a deployed function.
insert into public.ai_push_worker (id, internal_secret)
values (true, encode(gen_random_bytes(32), 'hex'))
on conflict (id) do nothing;

-- Same posture as ai_notification_log: service role only, no client policies.
alter table public.ai_push_worker enable row level security;
revoke all on public.ai_push_worker from anon, authenticated;
grant all on public.ai_push_worker to service_role;

-- Performs the HTTP call. Deliberately returns void and does not inspect the
-- response: pg_net dispatches asynchronously, so the reply lands in
-- net._http_response after this function has already returned. Failures show up
-- there, keyed by request id, and in the function's own logs.
create or replace function public.run_ai_push_digest()
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
    raise exception 'ai_push_worker has no secret; the digest cannot be invoked';
  end if;

  v_url := current_setting('app.settings.supabase_url', true);
  if v_url is null or v_url = '' then
    v_url := 'https://eazyeerunsxfyecjpyox.supabase.co';
  end if;

  perform net.http_post(
    url := v_url || '/functions/v1/ai-push-digest',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-kharcha-internal-secret', v_secret
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 120000
  );
end;
$$;

-- The job runs as its owner only; no client or anon role may invoke the
-- function behind it.
revoke all on function public.run_ai_push_digest() from public, anon, authenticated;
grant execute on function public.run_ai_push_digest() to service_role;

-- Replaces any earlier registration so the migration is re-runnable.
select cron.unschedule(jobid) from cron.job where jobname = 'ai-push-digest';

-- The schedule is read from ai_push_config rather than repeated as a literal,
-- so the row that documents the intended schedule and the job that runs cannot
-- disagree at creation time. Changing it later needs a migration: cron.schedule
-- takes its expression at DDL time and cannot read it from a table per run.
-- Note this is UTC. The per-user quiet-hours window is applied downstream using
-- each user's reported UTC offset, so the run time is a fixed trigger and not
-- itself a user-facing time.
select cron.schedule(
  'ai-push-digest',
  (select schedule from public.ai_push_config limit 1),
  $$select public.run_ai_push_digest()$$
);
