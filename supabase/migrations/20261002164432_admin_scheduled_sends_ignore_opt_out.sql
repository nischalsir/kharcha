-- Lets a queued console send carry the operator's "send even to people who
-- turned this type off" choice through to the moment it fires.
--
-- An immediate send passes the flag on the request. A scheduled one is read back
-- from this table by the dispatcher minutes or days later, so without a column
-- the override would silently be dropped and the send would skip the very
-- people the operator asked to include.
--
-- Defaults to false: every row queued before this column existed, and every
-- send from a console that does not know the flag, keeps honouring opt-outs.
alter table public.admin_scheduled_sends
  add column if not exists ignore_opt_out boolean not null default false;

comment on column public.admin_scheduled_sends.ignore_opt_out is
  'When true the dispatcher delivers to users who switched this category off in Settings.';
