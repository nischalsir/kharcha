-- How many times an account has asked the AI today.
--
-- The AI function only had a limit kept in memory, per server instance: it
-- forgot everything whenever the instance restarted, and two instances each
-- kept their own count. One signed-in account could use up the whole AI
-- allowance. This is the same limit, counted where it survives.
--
-- Service-role only: nobody reads or writes it through the API. The one way
-- in is take_ai_use(), which can only ever count for the caller.
create table if not exists public.ai_usage (
  user_id uuid not null references auth.users (id) on delete cascade,
  day date not null,
  mode text not null,
  count integer not null default 0,
  primary key (user_id, day, mode)
);

alter table public.ai_usage enable row level security;
revoke all on public.ai_usage from anon, authenticated;
grant all on public.ai_usage to service_role;

comment on table public.ai_usage is
  'AI requests per account, per UTC day and mode. Written only by take_ai_use().';

-- Counts one AI request for the caller and says whether it is still within
-- today's allowance. The limits are here, not in an argument, so a caller
-- cannot raise their own; and the account is auth.uid(), so a caller cannot
-- spend someone else's.
create or replace function public.take_ai_use(p_mode text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_mode text := case when p_mode = 'chat' then 'chat' else 'insight' end;
  v_limit integer := case when p_mode = 'chat' then 60 else 40 end;
  v_day date := (now() at time zone 'utc')::date;
  v_count integer;
begin
  if v_user is null then
    return false;
  end if;

  insert into public.ai_usage as u (user_id, day, mode, count)
  values (v_user, v_day, v_mode, 1)
  on conflict (user_id, day, mode) do update set count = u.count + 1
  returning u.count into v_count;

  -- The first request of a day sweeps out that account's old days.
  if v_count = 1 then
    delete from public.ai_usage where user_id = v_user and day < v_day - 7;
  end if;

  return v_count <= v_limit;
end;
$$;

revoke all on function public.take_ai_use(text) from public, anon;
grant execute on function public.take_ai_use(text) to authenticated, service_role;
