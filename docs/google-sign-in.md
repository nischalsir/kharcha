# Continue with Google

How it works, and the one setting outside this repository it depends on.

## The flow

1. The app asks Google for an account with `google_sign_in`, using the
   project's **Web** OAuth client as `serverClientId`
   (`GOOGLE_SERVER_CLIENT_ID` in `.env`, compiled in by `tool/run.ps1`).
2. Google returns an ID token whose audience (`aud`) is that Web client id.
3. The app hands the token to Supabase (`signInWithIdToken`). Supabase checks
   the audience against the client ids saved in its Google provider, then
   creates or opens the account and returns a session.
4. `_AuthWrapper` ties the local cache to that account and starts the sync.

There is no redirect, deep link or callback URL in this flow, and Firebase
Authentication is not used. Firebase is in the project for push notifications
(FCM) only.

## What has to match

| Where | What |
| --- | --- |
| Google Cloud → Clients → Android | package `com.nischalpandey.kharcha`, the release key's SHA-1 |
| Google Cloud → Clients → Web | its client id is `GOOGLE_SERVER_CLIENT_ID` |
| Supabase → Authentication → Sign In / Providers → Google → **Client IDs** | the same Web client id first, then the Android one, comma-separated, no spaces |
| Supabase → same page → **Client Secret** | the secret of that same Web client |

## The failure seen in October 2026

`Unacceptable audience in id_token` in the Supabase auth log, shown in the app
as "Google sign-in is not fully set up for Kharcha yet". The Google side was
right; Supabase's provider held the client id of a different Google Cloud
project, so it refused every token issued for Kharcha's.

To see which client id Supabase is using without opening the dashboard:

```
curl -s -o /dev/null -D - "https://<project>.supabase.co/auth/v1/authorize?provider=google" | grep -i location
```

The `client_id=` in the redirect is the one saved in the provider. It must be
Kharcha's Web client id.

## Guest mode

"Explore as guest" needs nothing on the server. A guest has no account and no
session; what they enter stays on the phone. Supabase's "Allow anonymous
sign-ins" can stay off.
