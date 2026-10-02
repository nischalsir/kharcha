-- Loans and the shared household ledger (app version 1.6).
--
-- Additive and re-runnable. Apply BEFORE releasing a build that syncs these
-- tables: PostgREST refuses a table it does not know.

-- --- Loans -------------------------------------------------------------------
-- A loan the user is repaying in equal monthly instalments. The instalments
-- themselves are the transactions of the linked recurring payment, so paying
-- one from either place counts once.
create table if not exists public.loans (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  name text not null check (char_length(name) between 1 and 80),
  lender text check (lender is null or char_length(lender) <= 80),
  principal numeric(14,2) not null check (principal > 0),
  annual_rate numeric(6,3) not null default 0
    check (annual_rate >= 0 and annual_rate <= 100),
  tenure_months integer not null check (tenure_months between 1 and 600),
  emi_amount numeric(14,2) not null check (emi_amount > 0),
  first_due_date date not null,
  paid_before integer not null default 0 check (paid_before >= 0),
  recurring_id uuid references public.recurring_transactions (id)
    on delete set null,
  notes text check (notes is null or char_length(notes) <= 500),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  server_updated_at timestamptz not null default clock_timestamp(),
  deleted_at timestamptz
);

comment on table public.loans is
  'A loan repaid in equal monthly instalments (EMI).';

create index if not exists loans_user_cursor_idx
  on public.loans (user_id, server_updated_at);
create index if not exists loans_recurring_idx
  on public.loans (recurring_id);

alter table public.loans enable row level security;
revoke all on public.loans from anon;
grant select, insert, update, delete on public.loans to authenticated;

-- --- Households --------------------------------------------------------------
-- A ledger several accounts share. Nobody writes households or members
-- directly: creating, joining and leaving go through the functions below, so
-- membership cannot be forged from the client.
create table if not exists public.households (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 60),
  owner_id uuid references auth.users (id) on delete set null,
  invite_code text not null unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  server_updated_at timestamptz not null default clock_timestamp(),
  deleted_at timestamptz
);

create table if not exists public.household_members (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null
    references public.households (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 60),
  role text not null default 'member' check (role in ('owner', 'member')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  server_updated_at timestamptz not null default clock_timestamp(),
  deleted_at timestamptz
);

-- One household per account, for now: the app shows a single ledger.
create unique index if not exists household_members_user_uq
  on public.household_members (user_id) where deleted_at is null;
create index if not exists household_members_household_idx
  on public.household_members (household_id);

-- An entry in the shared ledger. `user_id` is who wrote it down; `paid_by` is
-- the member whose money it was. Entries stay when their author leaves.
create table if not exists public.household_transactions (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null
    references public.households (id) on delete cascade,
  user_id uuid default auth.uid() references auth.users (id) on delete set null,
  paid_by uuid not null,
  title text not null check (char_length(title) between 1 and 200),
  amount numeric(14,2) not null check (amount > 0),
  occurred_at timestamptz not null,
  notes text check (notes is null or char_length(notes) <= 500),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  server_updated_at timestamptz not null default clock_timestamp(),
  deleted_at timestamptz
);

create index if not exists household_transactions_household_idx
  on public.household_transactions (household_id, occurred_at desc);
create index if not exists household_transactions_user_idx
  on public.household_transactions (user_id);

alter table public.households enable row level security;
alter table public.household_members enable row level security;
alter table public.household_transactions enable row level security;

revoke all on public.households from anon, authenticated;
revoke all on public.household_members from anon, authenticated;
revoke all on public.household_transactions from anon, authenticated;
grant select on public.households to authenticated;
grant select on public.household_members to authenticated;
grant select, insert, update on public.household_transactions to authenticated;

-- Whether the caller belongs to a household. Definer rights, so the policies
-- on household_members can ask it without recursing into themselves.
create or replace function public.is_household_member(p_household uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.household_members m
    where m.household_id = p_household
      and m.user_id = (select auth.uid())
      and m.deleted_at is null
  );
$$;

revoke all on function public.is_household_member(uuid) from public, anon;
grant execute on function public.is_household_member(uuid) to authenticated;

do $$
declare
  t text;
begin
  -- Loans: the owner only, as on every other personal table.
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'loans'
      and policyname = 'loans_select_own'
  ) then
    create policy loans_select_own on public.loans for select to authenticated
      using ((select auth.uid()) = user_id);
    create policy loans_insert_own on public.loans for insert to authenticated
      with check ((select auth.uid()) = user_id);
    create policy loans_update_own on public.loans for update to authenticated
      using ((select auth.uid()) = user_id)
      with check ((select auth.uid()) = user_id);
    create policy loans_delete_own on public.loans for delete to authenticated
      using ((select auth.uid()) = user_id);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'households'
      and policyname = 'households_select_member'
  ) then
    create policy households_select_member on public.households
      for select to authenticated
      using (public.is_household_member(id));
    create policy household_members_select_member on public.household_members
      for select to authenticated
      using (public.is_household_member(household_id));
    create policy household_transactions_select_member
      on public.household_transactions for select to authenticated
      using (public.is_household_member(household_id));
    create policy household_transactions_insert_member
      on public.household_transactions for insert to authenticated
      with check (
        public.is_household_member(household_id)
        and user_id = (select auth.uid())
      );
    -- Any member may correct or remove (soft delete) any entry: it is one
    -- family's book, not a ledger between strangers.
    create policy household_transactions_update_member
      on public.household_transactions for update to authenticated
      using (public.is_household_member(household_id))
      with check (public.is_household_member(household_id));
  end if;

  foreach t in array array[
    'loans', 'households', 'household_members', 'household_transactions'
  ] loop
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

-- --- Creating, joining and leaving -------------------------------------------
create or replace function public.create_household(
  p_name text,
  p_display_name text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_id uuid;
begin
  if v_uid is null then
    raise exception 'Sign in first.' using errcode = '42501';
  end if;
  if exists (
    select 1 from public.household_members
    where user_id = v_uid and deleted_at is null
  ) then
    raise exception 'You are already in a household.' using errcode = '22023';
  end if;

  insert into public.households (name, owner_id, invite_code)
  values (
    btrim(p_name),
    v_uid,
    upper(encode(extensions.gen_random_bytes(5), 'hex'))
  )
  returning id into v_id;

  insert into public.household_members (household_id, user_id, display_name, role)
  values (v_id, v_uid, btrim(p_display_name), 'owner');
  return v_id;
end;
$$;

create or replace function public.join_household(
  p_code text,
  p_display_name text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_id uuid;
begin
  if v_uid is null then
    raise exception 'Sign in first.' using errcode = '42501';
  end if;
  if exists (
    select 1 from public.household_members
    where user_id = v_uid and deleted_at is null
  ) then
    raise exception 'You are already in a household.' using errcode = '22023';
  end if;

  select id into v_id from public.households
  where invite_code = upper(btrim(p_code)) and deleted_at is null;
  if v_id is null then
    raise exception 'No household has that code.' using errcode = '22023';
  end if;
  if (
    select count(*) from public.household_members
    where household_id = v_id and deleted_at is null
  ) >= 12 then
    raise exception 'This household is full.' using errcode = '22023';
  end if;

  insert into public.household_members (household_id, user_id, display_name)
  values (v_id, v_uid, btrim(p_display_name));
  return v_id;
end;
$$;

-- Leaves a household, or (for its owner) removes another member. Memberships
-- are closed rather than erased, so the entries they paid for keep a name.
create or replace function public.leave_household(
  p_household uuid,
  p_member uuid default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_target uuid := coalesce(p_member, auth.uid());
  v_owner uuid;
  v_next uuid;
begin
  if v_uid is null then
    raise exception 'Sign in first.' using errcode = '42501';
  end if;
  select owner_id into v_owner from public.households
  where id = p_household and deleted_at is null;
  if not public.is_household_member(p_household) then
    raise exception 'You are not in this household.' using errcode = '42501';
  end if;
  if v_target <> v_uid and v_owner is distinct from v_uid then
    raise exception 'Only the owner can remove a member.' using errcode = '42501';
  end if;

  update public.household_members
  set deleted_at = now(), updated_at = now()
  where household_id = p_household and user_id = v_target and deleted_at is null;

  if v_owner = v_target then
    select user_id into v_next from public.household_members
    where household_id = p_household and deleted_at is null
    order by created_at limit 1;
    if v_next is null then
      -- The last one out closes the book.
      update public.households
      set deleted_at = now(), updated_at = now(), owner_id = null
      where id = p_household;
    else
      update public.households
      set owner_id = v_next, updated_at = now() where id = p_household;
      update public.household_members
      set role = 'owner', updated_at = now()
      where household_id = p_household and user_id = v_next
        and deleted_at is null;
    end if;
  end if;
end;
$$;

create or replace function public.rename_household(
  p_household uuid,
  p_name text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.households
  set name = btrim(p_name), updated_at = now()
  where id = p_household and deleted_at is null
    and owner_id = (select auth.uid());
  if not found then
    raise exception 'Only the owner can rename the household.'
      using errcode = '42501';
  end if;
end;
$$;

revoke all on function public.create_household(text, text) from public, anon;
revoke all on function public.join_household(text, text) from public, anon;
revoke all on function public.leave_household(uuid, uuid) from public, anon;
revoke all on function public.rename_household(uuid, text) from public, anon;
grant execute on function public.create_household(text, text) to authenticated;
grant execute on function public.join_household(text, text) to authenticated;
grant execute on function public.leave_household(uuid, uuid) to authenticated;
grant execute on function public.rename_household(uuid, text) to authenticated;

-- A guest's loans are moved by claim_guest_data, which is replaced in
-- 20261002180100_claim_guest_data_loans.sql.
