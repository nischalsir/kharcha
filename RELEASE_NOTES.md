# Kharcha v1.0.1

## Fixes
- **User data isolation fixed**: Added explicit `user_id` filter to sync pull queries for defense-in-depth. Every user now only sees their own transactions, budgets, friends, categories, and settings.
- **Database cleaned**: All previous test accounts and data removed for a fresh start.

## Highlights (from v1.0.0)
- **Bikram Sambat calendar** in Nepali with gazetted festival dates from the Ministry of Home Affairs
- **Expense / income tracking** with categories, monthly budget, and "Spent this month" card showing total, % of income, and category breakdown
- **AI flame mascot**: glows gold when you're saving, turns blue/sad when overspending, reacts to every transaction with random lines ("Hmmmm… money!", "Save money!")
- **AI insights + chat** (API key stays on the server)
- **Daily AI greetings**: good morning at 6 AM, good night at 10 PM, random tips in between — toggle in Settings
- **Push notifications (FCM)**, friends owe/owed, pasal credit, recurring payments, reports
- **Offline-first sync**, encrypted backups, biometric lock
- **Security**: row-level security on every table, private storage, secrets only in edge functions, input limits matched to the database

## Install
1. Download the APK below (`kharcha-v1.0.1.apk`)
2. Enable *Install unknown apps* for your browser / file manager
3. Open the APK → Install

> ⚠️ **Warning**: This APK is **debug-signed** (same key as development builds). If you have any previous Kharcha build installed with a different signature (e.g., a release-signed build), you must **uninstall it first** — Android blocks updates with mismatched signatures.

## Minimum SDK
- **minSdk 21** (Android 5.0 Lollipop)

## Tech Stack
- **Frontend**: Flutter 3.47 (Dart 3.13)
- **Backend**: Supabase (Postgres + Edge Functions in Deno)
- **Push**: Firebase Cloud Messaging (FCM v1)
- **AI**: NVIDIA Nemotron / custom prompts via Supabase Edge Functions
- **Calendar**: Bikram Sambat (BS) with official Nepali festival data