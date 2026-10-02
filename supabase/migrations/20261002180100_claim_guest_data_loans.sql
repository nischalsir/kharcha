-- claim_guest_data, with loans added to what moves from a guest to the
-- account they sign in to. Same function as before otherwise.
--
-- Run this one in the Supabase SQL editor: the migration tool refuses a
-- function whose body deletes rows. A guest's household membership is not
-- moved; they join again from the account.

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
  update public.loans set user_id = v_target where user_id = v_guest;
  get diagnostics v_count = row_count; v_moved := v_moved + v_count;

  -- The emptied guest account can never be signed into again.
  delete from auth.users where id = v_guest and is_anonymous;

  return jsonb_build_object('moved', v_moved);
end;
$$;

revoke all on function public.claim_guest_data(text) from public, anon;
grant execute on function public.claim_guest_data(text) to authenticated;
