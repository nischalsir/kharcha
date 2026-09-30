# Kharcha App

A Bikram Sambat expense tracker with a Nepali-language calendar, festival dates
gazetted by the Ministry of Home Affairs, and an offline-first sync backend.

## Running the app

The backend configuration lives in `.env` and is passed to the app as
`--dart-define` values, so the app must be launched through the wrapper scripts:

```powershell
# Windows
.\tool\run.ps1
.\tool\run.ps1 build apk
```

```bash
# macOS / Linux
./tool/run.sh
./tool/run.sh build apk
```

Setting up the environment:

1. Copy `.env.example` to `.env`.
2. Fill in `SUPABASE_URL` and `SUPABASE_ANON_KEY` from your Supabase project
   (Dashboard → Project Settings → API).
3. Add `SYNC_EMAIL` / `SYNC_PASSWORD` to sign in to a sync account automatically,
   or leave them blank and sign up on the login screen.
4. Add the AI keys only if you use the AI features.

> Running `flutter run` directly (without the wrapper) will start the app without
> a backend configured and the sync screen will report "Backend is not
> configured".

## Backend

The app syncs to Supabase in a table-per-entity layout with RLS policies.
The `anon`, `authenticated`, and `service_role` roles must be granted access to
the tables in the `public` schema; restore the standard grants with:

```sql
grant usage on schema public to anon, authenticated;
grant select on all tables in schema public to anon, authenticated, service_role;
grant insert, update, delete on all tables in schema public to anon, authenticated;
grant select, update, usage on all sequences in schema public to anon, authenticated;
grant execute on all functions in schema public to anon, authenticated;
```

## Backup & restore

Settings → Backup & Restore offers two ways to back up and restore all local
data (transactions, budgets, friends, Pasal credit, settings):

1. **Cloud (Supabase Storage)** — the snapshot is uploaded as
   `kharcha-backup-<timestamp>.json` under the signed-in user's folder in the
   `kharcha-files` bucket (`<user-id>/backups/`), the same per-user scheme used
   for avatars. The ten most recent backups are kept. Cloud backup reuses the
   app's normal Supabase session, so there is nothing extra to configure beyond
   the existing Supabase setup, but the bucket's storage policies must allow a
   user to read/write objects under their own `<user-id>/` prefix.
2. **Device file** — export a `.json` file (shared with any app) and import it
   back with the system file picker.

Restoring merges rows by id: matching records are overwritten and everything
else is left untouched.
