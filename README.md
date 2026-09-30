# Kharcha

**Nepali BS-calendar expense tracker with an AI mascot**

[![Download latest release](https://img.shields.io/badge/Download-APK-blue?logo=android)](https://github.com/nischalsir/kharcha/releases/latest)
[![Flutter](https://img.shields.io/badge/Flutter-3.47-02569B?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.13-0175C2?logo=dart)](https://dart.dev)
[![Supabase](https://img.shields.io/badge/Supabase-Backend-3ECF8E?logo=supabase)](https://supabase.com)
[![Firebase](https://img.shields.io/badge/FCM-Push%20Notifications-FFCA28?logo=firebase)](https://firebase.google.com)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

---

## Screenshots

| Home | Calendar | Login | Sign Up |
|------|----------|-------|---------|
| <img src="assets/images/screenshots/home.jpg" width="200" alt="Home screen"> | <img src="assets/images/screenshots/calender.jpg" width="200" alt="Calendar screen"> | <img src="assets/images/screenshots/login.jpg" width="200" alt="Login screen"> | <img src="assets/images/screenshots/signup.jpg" width="200" alt="Sign up screen"> |

---

## Features

| Feature | Description |
|---------|-------------|
| 🗓 **Bikram Sambat Calendar** | Official Nepali calendar with gazetted festival dates from the Ministry of Home Affairs |
| 💰 **Expense & Income Tracking** | Categories, monthly budget, "Spent this month" card with % of income & category breakdown |
| 🔥 **AI Flame Mascot** | Glows gold when saving, turns blue/sad when overspending, reacts to every transaction |
| 🤖 **AI Insights & Chat** | Server-side AI (API keys never leave the backend) |
| 🌅 **Daily AI Greetings** | Good morning at 6 AM, good night at 10 PM, random tips — toggle in Settings |
| 🔔 **Push Notifications (FCM)** | Budget alerts, reminders, daily greetings, transaction notifications |
| 👥 **Friends & Pasal Credit** | Track who owes you, Pasal (shop) credit, recurring payments |
| 📊 **Reports** | Visual spending charts, category analysis, monthly summaries |
| 🔐 **Biometric Lock** | Fingerprint/Face ID with encrypted keystore storage |
| ☁️ **Offline-First Sync** | Works offline, syncs securely via Supabase when online |
| 🛡 **Security First** | Row-level security on every table, private storage, secrets only in Edge Functions |

---

## Tech Stack

| Layer | Technology |
|-------|------------|
| **Frontend** | Flutter 3.47 · Dart 3.13 · Provider (state) |
| **Backend** | Supabase (PostgreSQL + Edge Functions in Deno) |
| **Push** | Firebase Cloud Messaging v1 |
| **AI** | NVIDIA Nemotron / custom prompts via Supabase Edge Functions |
| **Calendar** | Bikram Sambat (BS) with official Nepali festival data |
| **Auth** | Supabase Auth (email/password, MFA) |
| **Storage** | Supabase Storage (private, per-user buckets) |

---

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
assets/
  images/
    screenshots/          App screenshots
    festivals/            Festival images with attributions
```

---

## Running the App

The backend configuration lives in `.env` and is passed to the app as `--dart-define` values, so the app **must** be launched through the wrapper scripts:

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

### Environment Setup

1. Copy `.env.example` to `.env`
2. Fill in `SUPABASE_URL` and `SUPABASE_ANON_KEY` from your Supabase project  
   (Dashboard → Project Settings → API)
3. Add `SYNC_EMAIL` / `SYNC_PASSWORD` to auto-sign-in, or leave blank and sign up in-app
4. Add AI keys only if you use AI features

> ⚠️ Running `flutter run` directly (without the wrapper) starts the app without a configured backend; the sync screen will report "Backend is not configured".

---

## Backend

The app syncs to Supabase in a table-per-entity layout with RLS policies. The `anon`, `authenticated`, and `service_role` roles must be granted access to tables in the `public` schema; restore standard grants with:

```sql
grant usage on schema public to anon, authenticated;
grant select on all tables in schema public to anon, authenticated, service_role;
grant insert, update, delete on all tables in schema public to anon, authenticated;
grant select, update, usage on all sequences in schema public to anon, authenticated;
grant execute on all functions in schema public to anon, authenticated;
```

### Edge Functions Deployed

| Function | Schedule | JWT Verify |
|----------|----------|------------|
| `ai-daily-buddy` | `*/15 * * * *` (cron) | ❌ |
| `ai-push-digest` | `17 6 * * *` (cron) | ❌ |
| `parse-statement` | On-demand | ✅ |
| `send-push` | Triggered | ❌ |
| `register-push-token` | On-demand | ✅ |

---

## Backup & Restore

**Settings → Backup & Restore** offers two ways to back up and restore all local data (transactions, budgets, friends, Pasal credit, settings):

1. **Cloud (Supabase Storage)** — snapshot uploaded as `kharcha-backup-<timestamp>.json` under the signed-in user's folder in the `kharcha-files` bucket (`<user-id>/backups/`). Ten most recent backups kept.
2. **Device file** — export a `.json` file (shared with any app) and import it back via system file picker.

Restoring merges rows by id: matching records overwritten, others untouched.

---

## Security

- **Row-Level Security (RLS)** on every table — users only see their own data
- **Private Storage** — avatars & backups in per-user folders, no public access
- **Secrets in Edge Functions only** — `FIREBASE_SERVICE_ACCOUNT_JSON`, `NVIDIA_API_KEY` never touch the client
- **Input Validation** — limits matched to database constraints (e.g., max 500 chars for notes)
- **Biometric** — credentials encrypted in device keystore, never in app data
- **MFA** — TOTP via authenticator app

---

## Minimum Requirements

| Platform | Version |
|----------|---------|
| Android | 5.0 (API 21) |
| Flutter | 3.47+ |
| Dart | 3.13+ |

---

## Build

```bash
# Debug APK
flutter build apk --debug

# Release APK (debug-signed)
flutter build apk --release
# or via wrapper
.\tool\run.ps1 build apk
```

> ⚠️ The release APK is **debug-signed** (same key as development builds). If you have any previous Kharcha build installed with a different signature, you must **uninstall it first** — Android blocks updates with mismatched signatures.

---

## Download

**Latest Release:** [https://github.com/nischalsir/kharcha/releases/latest](https://github.com/nischalsir/kharcha/releases/latest)

Direct APK: [`kharcha-v1.0.0.apk`](https://github.com/nischalsir/kharcha/releases/download/v1.0.0/kharcha-v1.0.0.apk) (~67 MB)

---

## License

MIT License — see [LICENSE](LICENSE) for details.

---

## Acknowledgments

- Nepali festival data from [Ministry of Home Affairs, Nepal](https://moha.gov.np)
- Festival images from freely licensed sources (see `assets/images/festivals/ATTRIBUTION.md`)
- Built with ❤️ using Flutter, Supabase, and Firebase

---

## Contact

**Developer:** Nischal Pandey  
**GitHub:** [@nischalsir](https://github.com/nischalsir)  
**Instagram:** [@nischalsir](https://instagram.com/nischalsir)