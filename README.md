# Kharcha

**Nepali BS-calendar expense tracker with an AI mascot**

[![Download latest release](https://img.shields.io/badge/Download-APK-blue?logo=android)](https://github.com/nischalsir/kharcha/releases/latest)

---

## Features
- **Bikram Sambat calendar** in Nepali with gazetted festival dates from the Ministry of Home Affairs
- **Expense / income tracking** with categories, monthly budget, and "Spent this month" card showing total, % of income, and category breakdown
- **AI flame mascot**: glows gold when you're saving, turns blue/sad when overspending, reacts to every transaction with random lines ("Hmmmm… money!", "Save money!")
- **AI insights + chat** (API key stays on the server)
- **Daily AI greetings**: good morning at 6 AM, good night at 10 PM, random tips in between — toggle in Settings
- **Push notifications (FCM)**, friends owe/owed, pasal credit, recurring payments, reports
- **Offline-first sync**, encrypted backups, biometric lock
- **Security**: row-level security on every table, private storage, secrets only in edge functions, input limits matched to the database

## Screenshots
| Home | Calendar | Login | Sign Up |
|------|----------|-------|---------|
| <img src="assets/images/screenshots/home.jpg" width="200"> | <img src="assets/images/screenshots/calender.jpg" width="200"> | <img src="assets/images/screenshots/login.jpg" width="200"> | <img src="assets/images/screenshots/signup.jpg" width="200"> |

## Tech Stack
- **Frontend**: Flutter 3.47 (Dart 3.13)
- **Backend**: Supabase (Postgres + Edge Functions in Deno)
- **Push**: Firebase Cloud Messaging (FCM v1)
- **AI**: NVIDIA Nemotron / custom prompts via Supabase Edge Functions
- **Calendar**: Bikram Sambat (BS) with official Nepali festival data

## Project Structure
```
lib/                      Flutter app
  core/                   Theme, routing, l10n, constants, utils
  data/                   Generated credits
  models/                 Data models
  providers/              Riverpod providers (state)
  repositories/           Data access
  screens/                UI screens
  services/               Business logic
  widgets/                Reusable UI components
supabase/
  functions/              Edge Functions (Deno)
  migrations/             SQL migrations
  _tests/                 Deno tests
test/                     Flutter tests
tool/                     Build/run scripts
```

## Running the app
The backend configuration lives in `.env` and is passed to the app as `--dart-define` values, so the app must be launched through the wrapper scripts:

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

### Environment setup
1. Copy `.env.example` to `.env`
2. Fill in `SUPABASE_URL` and `SUPABASE_ANON_KEY` from your Supabase project (Dashboard → Project Settings → API)
3. Add `SYNC_EMAIL` / `SYNC_PASSWORD` to auto-sign-in, or leave blank and sign up in-app
4. Add AI keys only if you use AI features

> Running `flutter run` directly (without the wrapper) starts the app without a configured backend; the sync screen will report "Backend is not configured".

## Backend
The app syncs to Supabase in a table-per-entity layout with RLS policies. The `anon`, `authenticated`, and `service_role` roles must be granted access to tables in the `public` schema; restore standard grants with:

```sql
grant usage on schema public to anon, authenticated;
grant select on all tables in schema public to anon, authenticated, service_role;
grant insert, update, delete on all tables in schema public to anon, authenticated;
grant select, update, usage on all sequences in schema public to anon, authenticated;
grant execute on all functions in schema public to anon, authenticated;
```

## Backup & Restore
Settings → Backup & Restore offers two ways to back up and restore all local data:

1. **Cloud (Supabase Storage)** — snapshot uploaded as `kharcha-backup-<timestamp>.json` under the signed-in user's folder in the `kharcha-files` bucket (`<user-id>/backups/`). Ten most recent backups kept.
2. **Device file** — export a `.json` file (shared with any app) and import it back via system file picker.

Restoring merges rows by id: matching records overwritten, others untouched.