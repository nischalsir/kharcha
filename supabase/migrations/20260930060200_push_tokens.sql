-- One row per device that can receive a push.
--
-- Registration goes through the `register-push-token` edge function rather than
-- a client insert, so the table needs no insert policy and grants none. That is
-- deliberate: a token is a bearer credential for a device, and letting a
-- compromised client write arbitrary token strings would let it plant one and
-- receive another user's notifications. The client only ever reads and deletes
-- its own rows, which is what it needs to clean up on sign-out.
create table if not exists public.push_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  -- Sent verbatim to FCM, so it is unique globally rather than per user: the
  -- same physical device that signs in as someone else must update that row
  -- instead of accumulating a second copy of a token it no longer owns.
  token text not null unique,
  platform text not null default 'android',
  app_version text,
  device_label text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);

comment on column public.push_tokens.user_id is 'Owner. Cascades on account deletion.';
comment on column public.push_tokens.last_seen_at is
  'Last confirmed delivery, used to prune devices that have gone quiet.';

create index if not exists push_tokens_user_id_idx on public.push_tokens (user_id);

-- Supports the staleness sweep that deletes tokens FCM has stopped accepting.
create index if not exists push_tokens_last_seen_idx on public.push_tokens (last_seen_at);

alter table public.push_tokens enable row level security;

-- The two operations the app performs on its own behalf. Written in terms of
-- auth.uid() rather than current_setting so a client cannot assert its own id.
create policy push_tokens_select_own
  on public.push_tokens
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy push_tokens_delete_own
  on public.push_tokens
  for delete
  to authenticated
  using ((select auth.uid()) = user_id);

-- RLS above is the real gate, but the broad table grants a default install
-- hands out include insert and update, which nothing here needs. Narrowing them
-- means a future policy added in a hurry is not the only thing standing between
-- a client and someone else's token.
revoke all on public.push_tokens from anon;
revoke all on public.push_tokens from authenticated;
grant select, delete on public.push_tokens to authenticated;
grant all on public.push_tokens to service_role;
