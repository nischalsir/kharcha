-- Savings goals, wallet balances, transfers between wallets and festival
-- budgets (app version 1.5).
--
-- Everything here is additive, so older app versions keep working: they
-- neither send nor read the new columns, and an upsert that omits a column
-- leaves it untouched. It must be applied BEFORE a build that sends the new
-- columns is released, because PostgREST rejects an upsert that names a
-- column it does not know (PGRST204).
--
-- Written to be safely re-runnable.

-- --- Transfers between wallets ----------------------------------------------
-- A transfer is a transaction of type 'transfer': `payment_method` is the
-- wallet the money leaves and `transfer_to` the wallet it arrives in.
alter table public.transactions
  add column if not exists transfer_to text;

comment on column public.transactions.transfer_to is
  'For type = transfer: the wallet (payment method code) the money moved to.';

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'transactions_transfer_to_check'
  ) then
    alter table public.transactions
      add constraint transactions_transfer_to_check
      check (
        transfer_to is null
        or (
          type = 'transfer'
          and transfer_to <> payment_method
          and transfer_to in
            ('cash', 'bank', 'esewa', 'khalti', 'card', 'qr', 'other')
        )
      );
  end if;
end $$;

-- --- Wallet balances ---------------------------------------------------------
-- What each wallet held before the first recorded transaction, by payment
-- method code: {"cash": 1500, "esewa": 320.5}. A wallet's balance is this
-- plus everything recorded against it since.
alter table public.app_settings
  add column if not exists wallet_balances jsonb not null default '{}'::jsonb;

comment on column public.app_settings.wallet_balances is
  'Opening balance per payment method code. Missing means zero.';

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'app_settings_wallet_balances_check'
  ) then
    alter table public.app_settings
      add constraint app_settings_wallet_balances_check
      check (jsonb_typeof(wallet_balances) = 'object');
  end if;
end $$;

-- --- Savings goals -----------------------------------------------------------
create table if not exists public.savings_goals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  name text not null check (char_length(name) between 1 and 80),
  target_amount numeric(14,2) not null check (target_amount > 0),
  saved_amount numeric(14,2) not null default 0 check (saved_amount >= 0),
  target_date date,
  notes text check (notes is null or char_length(notes) <= 500),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  server_updated_at timestamptz not null default clock_timestamp(),
  deleted_at timestamptz
);

comment on table public.savings_goals is
  'Money a user is putting aside towards something, with how much is saved.';

create index if not exists savings_goals_user_cursor_idx
  on public.savings_goals (user_id, server_updated_at);

-- --- Festival budgets --------------------------------------------------------
-- A spending limit for one festival in one BS year. Spending is whatever the
-- user spent between start_date and end_date, so the row carries its own
-- window and stays meaningful in a year the bundled calendar does not cover.
create table if not exists public.festival_budgets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  festival_id text not null check (char_length(festival_id) between 1 and 80),
  festival_name text not null
    check (char_length(festival_name) between 1 and 120),
  bs_year integer not null check (bs_year between 1970 and 2200),
  amount numeric(14,2) not null check (amount > 0),
  start_date date not null,
  end_date date not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  server_updated_at timestamptz not null default clock_timestamp(),
  deleted_at timestamptz,
  constraint festival_budgets_window_check check (end_date >= start_date)
);

comment on table public.festival_budgets is
  'A spending limit for one festival in one BS year, with its date window.';

create index if not exists festival_budgets_user_cursor_idx
  on public.festival_budgets (user_id, server_updated_at);

create unique index if not exists festival_budgets_festival_uq
  on public.festival_budgets (user_id, festival_id, bs_year)
  where deleted_at is null;

-- --- Row level security, as on every other synced table ----------------------
alter table public.savings_goals enable row level security;
alter table public.festival_budgets enable row level security;

revoke all on public.savings_goals from anon;
revoke all on public.festival_budgets from anon;
grant select, insert, update, delete on public.savings_goals to authenticated;
grant select, insert, update, delete on public.festival_budgets to authenticated;

do $$
declare
  t text;
begin
  foreach t in array array['savings_goals', 'festival_budgets'] loop
    if not exists (
      select 1 from pg_policies
      where schemaname = 'public' and tablename = t
        and policyname = t || '_select_own'
    ) then
      execute format(
        'create policy %I on public.%I for select to authenticated '
        'using ((select auth.uid()) = user_id)',
        t || '_select_own', t);
      execute format(
        'create policy %I on public.%I for insert to authenticated '
        'with check ((select auth.uid()) = user_id)',
        t || '_insert_own', t);
      execute format(
        'create policy %I on public.%I for update to authenticated '
        'using ((select auth.uid()) = user_id) '
        'with check ((select auth.uid()) = user_id)',
        t || '_update_own', t);
      execute format(
        'create policy %I on public.%I for delete to authenticated '
        'using ((select auth.uid()) = user_id)',
        t || '_delete_own', t);
    end if;

    -- Stamps server_updated_at and drops a write older than the stored row.
    if not exists (
      select 1 from pg_trigger
      where tgname = t || '_guard' and tgrelid = ('public.' || t)::regclass
    ) then
      execute format(
        'create trigger %I before insert or update on public.%I '
        'for each row execute function private.sync_guard()',
        t || '_guard', t);
    end if;
  end loop;
end $$;

-- --- Guest data moves with the rest ------------------------------------------
-- Same function as in 20260930130000_guest_claims.sql, with the two new
-- tables added.
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

  -- Festival budgets: one per festival per year. The account's own wins.
  delete from public.festival_budgets g
  where g.user_id = v_guest and g.deleted_at is null and exists (
    select 1 from public.festival_budgets t
    where t.user_id = v_target and t.deleted_at is null
      and t.festival_id = g.festival_id and t.bs_year = g.bs_year
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
  update public.savings_goals set user_id = v_target where user_id = v_guest;
  get diagnostics v_count = row_count; v_moved := v_moved + v_count;
  update public.festival_budgets set user_id = v_target where user_id = v_guest;
  get diagnostics v_count = row_count; v_moved := v_moved + v_count;

  -- The emptied guest account can never be signed into again.
  delete from auth.users where id = v_guest and is_anonymous;

  return jsonb_build_object('moved', v_moved);
end;
$$;

revoke all on function public.claim_guest_data(text) from public, anon;
grant execute on function public.claim_guest_data(text) to authenticated;
