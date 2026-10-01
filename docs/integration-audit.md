# Integration audit — Kharcha v1.0.15 (1 October 2026)

What the app expects, compared with what the backend actually provides:
Flutter app ↔ Supabase (database, RLS, storage, auth, Edge Functions) ↔
Firebase ↔ Google Cloud ↔ GitHub. Everything was read from the live
projects, not from the repository alone.

Legend: **Broken** · **Misconfigured** · **Frontend mismatch** ·
**Backend mismatch** · **Security** · **Needs console** (an external setting
the repository cannot change) · **Working**.

## Found and fixed

| # | Area | Class | Finding | Fix |
|---|------|-------|---------|-----|
| 1 | Push notifications | Backend mismatch / Broken | Six push fixes (data-only FCM messages, escaped key newlines, pruning dead tokens, the `push-reminders` worker and its migration, BS calendar years) lived only on the unmerged branch `claude/cool-feynman-mzcaeo`, yet were deployed. Deploying `ai-daily-buddy` from `main` had silently removed the data-only fix again, so daily-buddy pushes in the background could arrive blank or doubled. | Branch commits brought into `main`; every function redeployed from one source. |
| 2 | Guest mode | Backend mismatch / Broken | The app calls the RPCs `create_guest_claim` / `claim_guest_data`, but their migration had never been applied: "save my guest data into my existing account" failed. | Migration applied to the live database. |
| 3 | Guest mode | Frontend mismatch | Guest sign-in failing showed "Could not sign in to sync." | Says plainly that guest mode is switched off (see Needs console). |
| 4 | Sign in | Frontend mismatch | A wrong password flashed the full-screen "Signing in as …" before the error. | That screen now appears only after the server accepts the password. |
| 5 | Google Drive | Misconfigured / Broken | The Firebase project has **no OAuth client** (no Web client, no Android client); only the debug key's SHA-1 is registered, not the release key's. Google Sign-In fails before any picker. | App detects the missing client and says Drive is not available yet instead of showing a dead button; accepts `GOOGLE_SERVER_CLIENT_ID`; exact console steps in `docs/google-drive-setup.md`. |
| 6 | Google Drive | Security | Drive state was per device, not per Kharcha account: a second account on the phone could be silently reconnected to the first account's Google Drive, and see/prune its backups. | Google account linked per Kharcha user; forgotten on sign-out; backups tagged with their owner and filtered; only own backups pruned. |
| 7 | Google Drive | Performance | A new access token was requested for every Drive call. | Token reused while fresh; refreshed once on 401. |
| 8 | Budgets in Flamey/AI | Frontend + backend mismatch | The overall budget was added to its own category budgets (double counted). On the server, **every month's** budgets were summed, not this month's. | Overall budget used when present; server filters to the current Bikram Sambat month. |
| 9 | Statement import | Backend mismatch | Transaction titles over 200 characters (long wrapped PDF descriptions) are refused by a database check, leaving the row stuck in the sync queue. | Titles clamped to 200 characters; never empty. |
| 10 | Statement import | Backend mismatch | Older app versions would have read Bikram Sambat dates (now extracted from PDFs) as AD dates 57 years ahead. | Server only returns BS dates to clients that say they convert them. |
| 11 | AI suggestions | Frontend mismatch | Suggestions needed the Refresh button; app opens could each call the AI. | Scheduled windows + data-change triggers, cached per window and data state, gap and daily ceiling. Button removed. |
| 12 | AI suggestions | Security / data quality | Nothing stopped the model quoting figures that are not in the user's data. | Server rejects any reply with an amount or percentage not found in the summary; the app keeps its own, local suggestion. |
| 13 | AI server | Backend mismatch | `dailyExpense`/"today" were UTC days; for Nepal the day turned at 05:45. | New time-aware figures use the user's own offset. |
| 14 | `media-sign` | Backend mismatch | The app calls `media-sign` for Cloudinary avatar upload; the function was not deployed (the app fell back to Supabase Storage silently). | Deployed. Still needs the Cloudinary secret (see Needs console); the fallback keeps avatars working meanwhile. |
| 15 | `pasal_balances()` | Security (minor) | Executable by the anonymous role. RLS made it return nothing, but it had no use before sign-in. | Revoked from `anon`. |

## Checked and working

* **Every user table** (`transactions`, `budgets`, `categories`, `payment_methods`, `app_settings`, `friends`, `friend_credits`, `friend_payments`, `pasals`, `pasal_credits`, `pasal_credit_items`, `pasal_payments`, `recurring_transactions`, `sync_metadata`, `profiles`, `push_tokens`): RLS on, and select/insert/update/delete restricted to `auth.uid() = user_id` (or `id` for profiles). One signed-in user cannot read or write another's rows.
* **Service-only tables** (`ai_notification_log`, `ai_push_config`, `ai_push_worker`, `push_reminder_log`, `guest_claims`, `admin_push_log`): RLS on, no policies, no grants to `anon`/`authenticated`.
* **Schema vs models**: every column the app writes exists; the generated columns (`remaining_amount`, `total_price`) are never written; every enum value the app sends (payment methods, types, statuses, theme, calendar, language) is allowed by the database's check constraints.
* **Storage**: one private bucket, `kharcha-files`, policies limited to the user's own folder. Every upload path starts with the user id: avatars `uid/avatar.png`, backups `uid/backups/…json`, pasal pictures `uid/pasal/<item>.jpg`. Allowed types cover all three. Statement files are never stored. Festival and help pictures are on Cloudinary (public, not user data).
* **Edge Functions** the app calls — `ai-insight`, `parse-statement`, `register-push-token`, `send-push`, `media-sign` — exist, are deployed, check the caller's JWT, take the request fields the app sends and answer `{error}` the way the app reads it. Scheduled ones (`ai-daily-buddy`, `ai-push-digest`, `push-reminders`) authenticate with the internal secret; their cron jobs last ran successfully.
* **Secrets**: the service-role key, Firebase service account and AI key exist only as function secrets. The app ships only the Supabase URL and publishable key.
* **Firebase**: the app uses Firebase **only for Cloud Messaging** (`firebase_core`, `firebase_messaging`). Package name in `google-services.json` matches; the server sends through FCM HTTP v1 with the service-account secret. Firebase Auth, Firestore and Firebase Storage are not used, so no rules apply.
* **Update system**: reads GitHub `releases/latest`, first `.apk` asset; checked once per launch.

## Not in this repository

* **`admin-push`** (Edge Function) and its `admin_push_log` table appeared in the live project during this audit. It is a push console backend, not used by the app. It fails closed: only callers whose email is in the `ADMIN_EMAILS` secret are accepted. Its source should be committed wherever the console lives.

## Needs console configuration

| Where | What | Why |
|-------|------|-----|
| Firebase + Google Cloud (`kharcha-35c62`) | Add the release SHA-1/SHA-256, create the Web + Android OAuth clients, enable the Drive API, set up the consent screen with `drive.appdata`. Exact steps: `docs/google-drive-setup.md`. | Google Drive backup cannot work without them. |
| Supabase → Authentication → Sign In / Providers | Turn on **Allow anonymous sign-ins** (ideally with CAPTCHA). | "Explore as guest" is refused by the server until then. The app now says so. |
| Supabase → Edge Functions → Secrets | Set `CLOUDINARY_URL` (`cloudinary://<key>:<secret>@dh3rzo7bt`). | Profile pictures go to Cloudinary only then; until then Supabase Storage is used. |
| Supabase → Authentication → SMTP | A custom SMTP sender (any free tier). | Supabase's built-in mailer only reaches team members, so password-reset codes may not reach users. Not verifiable from here. |
| Supabase → Authentication → Passwords | Leaked-password protection. | Flagged by the security advisor; it is a paid-plan feature. |
| GitHub | Billing lock on the account. | Actions cannot run; releases are built locally with `tool/release.ps1`. |
| GitHub | `gh auth refresh -h github.com -s write:packages` | Needed once to publish to GitHub Packages. |

## Known limitation, unchanged

Two-factor authentication is enforced by the app, not by RLS: a fingerprint
sign-in on a trusted device keeps an `aal1` session by design. Requiring
`aal2` in RLS would end that feature.

## How it was tested

* 415 Flutter tests and 115 server tests, including: the route behind every
  More-page row and every named route; Drive isolation between two accounts;
  shared files (initial, while running, too large, wrong type); the
  suggestion scheduler (no requests on rebuild, new window, data changes with
  gap, failing backend, stale replies, daily ceiling); grounding of AI
  figures; two bank PDF layouts generated as real PDFs plus the user's real
  statement, through the same PDF reader the server uses.
* No phone or emulator was available: nothing here was tried on a device.
