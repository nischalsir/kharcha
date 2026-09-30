-- Moving a guest's data into an existing account.
--
-- A guest who signs up with a NEW email is converted in place by the app
-- (auth.updateUser on the anonymous user), keeps the same user id, and needs
-- nothing here. This covers the other case: the guest enters an email that
-- already has an account. Their records belong to the anonymous user id, and
-- after signing in to the real account RLS makes them invisible, so they must
-- be moved server side.
--
-- Ownership has to be proven from BOTH sides, which is why this is two calls:
--   1. create_guest_claim()   - called while still signed in as the guest;
--                               returns a short-lived one-time token.
--   2. claim_guest_data(tok)  - called after signing in to the real account;
--                               moves the guest's rows to the caller.
-- Neither user id is ever accepted as a parameter, so one account cannot
-- claim another's data by guessing an id.

create table if not exists public.guest_claims (
  token text primary key,
  anon_user_id uuid not null references auth.users (id) on delete cascade,
  expires_at timestamptz not null default now() + interval '30 minutes'
);

comment on table public.guest_claims is
  'One-time tokens proving a session owned a guest account. Service/definer only.';

alter table public.guest_claims enable row level security;
revoke all on public.guest_claims from anon, authenticated;

create or replace function public.create_guest_claim()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_token text;
begin
  if v_uid is null
     or coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) is false then
    raise exception 'Only a guest session can start a claim.'
      using errcode = '42501';
  end if;

  delete from public.guest_claims
  where anon_user_id = v_uid or expires_at < now();

  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  insert into public.guest_claims (token, anon_user_id) values (v_token, v_uid);
  return v_token;
end;
$$;

create or replace function public.claim_guest_data(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_target uuid := auth.uid();
  v_guest uuid;
  v_moved integer := 0;
  v_count integer;
begin
  if v_target is null
     or coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then
    raise exception 'Sign in to a permanent account to claim guest data.'
      using errcode = '42501';
  end if;

  delete from public.guest_claims
  where token = p_token and expires_at > now()
  returning anon_user_id into v_guest;

  if v_guest is null then
    raise exception 'This guest claim is invalid or has expired.'
      using errcode = '22023';
  end if;
  if v_guest = v_target then
    return jsonb_build_object('moved', 0);
  end if;
  -- Refuse to strip data from a real account, even with a valid token.
  if not exists (
    select 1 from auth.users where id = v_guest and is_anonymous
  ) then
    raise exception 'Only guest accounts can be claimed.' using errcode = '42501';
  end if;

  -- Categories: one per name per user. A guest category whose name the
  -- account already has is folded into the account's one.
  create temporary table _cat_map on commit drop as
    select g.id as guest_id, t.id as target_id
    from public.categories g
    join public.categories t
      on t.user_id = v_target
     and t.deleted_at is null
     and lower(t.name) = lower(g.name)
    where g.user_id = v_guest and g.deleted_at is null;

  update public.transactions x set category_id = m.target_id
  from _cat_map m where x.category_id = m.guest_id;
  update public.recurring_transactions x set category_id = m.target_id
  from _cat_map m where x.category_id = m.guest_id;
  update public.budgets x set category_id = m.target_id
  from _cat_map m where x.category_id = m.guest_id;
  delete from public.categories c using _cat_map m where c.id = m.guest_id;

  -- Budgets: one per period (and category). The account's own wins.
  delete from public.budgets g
  where g.user_id = v_guest and g.deleted_at is null and exists (
    select 1 from public.budgets t
    where t.user_id = v_target and t.deleted_at is null
      and t.period = g.period and t.bs_year = g.bs_year
      and t.bs_month = g.bs_month
      and coalesce(t.week_start, '1900-01-01'::date)
        = coalesce(g.week_start, '1900-01-01'::date)
      and coalesce(t.category_id, '00000000-0000-0000-0000-000000000000'::uuid)
        = coalesce(g.category_id, '00000000-0000-0000-0000-000000000000'::uuid)
  );

  -- Payment methods: one per code. Transactions refer to the code, not the
  -- row, so the guest's duplicate can simply go.
  delete from public.payment_methods g
  where g.user_id = v_guest and exists (
    select 1 from public.payment_methods t
    where t.user_id = v_target and t.code = g.code
  );

  -- Per-account state that must not be merged: the account keeps its own.
  delete from public.app_settings where user_id = v_guest;
  delete from public.sync_metadata where user_id = v_guest;
  delete from public.push_tokens where user_id = v_guest;
  delete from public.ai_notification_log where user_id = v_guest;

  -- Everything else moves as-is. Ids are UUIDs, so nothing can collide, and
  -- the sync guard bumps server_updated_at so the account's devices pull it.
  update public.categories set user_id = v_target where user_id = v_guest;
  get diagnostics v_count = row_count; v_moved := v_moved + v_count;
  update public.payment_methods set user_id = v_target where user_id = v_guest;
  get diagnostics v_count = row_count; v_moved := v_moved + v_count;
  update public.recurring_transactions set user_id = v_target where user_id = v_guest;
  get diagnostics v_count = row_count; v_moved := v_moved + v_count;
  update public.transactions set user_id = v_target where user_id = v_guest;
  get diagnostics v_count = row_count; v_moved := v_moved + v_count;
  update public.budgets set user_id = v_target where user_id = v_guest;
  get diagnostics v_count = row_count; v_moved := v_moved + v_count;
  update public.friends set user_id = v_target where user_id = v_guest;
  get diagnostics v_count = row_count; v_moved := v_moved + v_count;
  update public.friend_credits set user_id = v_target where user_id = v_guest;
  get diagnostics v_count = row_count; v_moved := v_moved + v_count;
  update public.friend_payments set user_id = v_target where user_id = v_guest;
  get diagnostics v_count = row_count; v_moved := v_moved + v_count;
  update public.pasals set user_id = v_target where user_id = v_guest;
  get diagnostics v_count = row_count; v_moved := v_moved + v_count;
  update public.pasal_credits set user_id = v_target where user_id = v_guest;
  get diagnostics v_count = row_count; v_moved := v_moved + v_count;
  update public.pasal_credit_items set user_id = v_target where user_id = v_guest;
  get diagnostics v_count = row_count; v_moved := v_moved + v_count;
  update public.pasal_payments set user_id = v_target where user_id = v_guest;
  get diagnostics v_count = row_count; v_moved := v_moved + v_count;

  -- The emptied guest account can never be signed into again.
  delete from auth.users where id = v_guest and is_anonymous;

  return jsonb_build_object('moved', v_moved);
end;
$$;

revoke all on function public.create_guest_claim() from public, anon;
revoke all on function public.claim_guest_data(text) from public, anon;
grant execute on function public.create_guest_claim() to authenticated;
grant execute on function public.claim_guest_data(text) to authenticated;
