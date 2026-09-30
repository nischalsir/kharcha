-- Fill profiles.display_name from the name given at sign-up.
--
-- handle_new_user() only inserted the id, so every profile had a null
-- display_name even though the app sends `full_name` in the sign-up metadata.
-- It now copies the name on sign-up, and a second trigger keeps it current when
-- the user edits their profile (which updates the same metadata).

create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''))
  on conflict (id) do nothing;
  return new;
end;
$$;

create or replace function private.sync_profile_display_name()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.raw_user_meta_data ->> 'full_name'
     is distinct from old.raw_user_meta_data ->> 'full_name' then
    update public.profiles
    set display_name = nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''),
        updated_at = now()
    where id = new.id;
  end if;
  return new;
end;
$$;

drop trigger if exists on_auth_user_updated_name on auth.users;
create trigger on_auth_user_updated_name
  after update of raw_user_meta_data on auth.users
  for each row execute function private.sync_profile_display_name();

-- Backfill profiles created before this fix.
update public.profiles p
set display_name = nullif(trim(u.raw_user_meta_data ->> 'full_name'), ''),
    updated_at = now()
from auth.users u
where u.id = p.id
  and p.display_name is null
  and nullif(trim(u.raw_user_meta_data ->> 'full_name'), '') is not null;
