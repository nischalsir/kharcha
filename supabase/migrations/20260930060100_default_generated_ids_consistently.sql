-- Gives every user-owned table a database-generated `id`.
--
-- Only the four pasal tables defaulted `gen_random_uuid()`; the rest had
-- `id uuid primary key default gen_random_uuid()` removed, so any client insert
-- that omitted the id failed with:
--   23502 null value in column "id" violates not-null constraint
-- Categories, payment methods, friends, friend credits, friend payments,
-- transactions, recurring transactions and budgets are all affected.
--
-- `profiles` is intentionally excluded: its id is the auth.users id, so a
-- default would be wrong.
alter table public.categories
  alter column id set default gen_random_uuid();
alter table public.payment_methods
  alter column id set default gen_random_uuid();
alter table public.friends
  alter column id set default gen_random_uuid();
alter table public.friend_credits
  alter column id set default gen_random_uuid();
alter table public.friend_payments
  alter column id set default gen_random_uuid();
alter table public.transactions
  alter column id set default gen_random_uuid();
alter table public.recurring_transactions
  alter column id set default gen_random_uuid();
alter table public.budgets
  alter column id set default gen_random_uuid();
