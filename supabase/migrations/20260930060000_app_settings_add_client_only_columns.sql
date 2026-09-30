-- Adds the three client-owned columns that `app_settings_model.dart` sends.
--
-- Before this, the Flutter client sent calendar_type / has_seen_introduction /
-- profile and PostgREST rejected the whole upsert with:
--   PGRST204 Could not find the 'calendar_type' column of 'app_settings'
--   in the schema cache
-- which made settings sync fail for every signed-in user.
--
-- calendar_type is a keyless accent toggle ("bs" | "ad"), not a Bikram Sambat
-- date conversion, so it is a constrained text rather than a bool.
alter table public.app_settings
  add column if not exists calendar_type text not null default 'bs',
  add column if not exists has_seen_introduction boolean not null default false,
  add column if not exists profile jsonb not null default '{}'::jsonb;

-- Guard the accent toggle so a bad client build cannot poison the column.
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'app_settings_calendar_type_check'
  ) then
    alter table public.app_settings
      add constraint app_settings_calendar_type_check
      check (calendar_type in ('bs', 'ad'));
  end if;
end $$;
