# Google Drive backup: what has to be set up

Google Drive backup uses Google Sign-In, and Google Sign-In only works for an
app that Google has been told about. As of v1.0.15 the Firebase / Google Cloud
project behind Kharcha (`kharcha-35c62`) has **no OAuth client at all**, which
is why "Connect Google Drive" could not work: sign-in failed before the
account picker was ever shown.

None of this can be done from the repository. It is a few minutes in two web
consoles, once.

## What was found

| Check | Result |
| --- | --- |
| App id in `google-services.json` | `com.nischalpandey.kharcha` (matches the app) |
| OAuth clients in `google-services.json` | **none** (no Web client, no Android client) |
| SHA-1 registered in Firebase | only `C7:53:EB:C0:4D:0B:BF:BA:97:11:08:14:C0:7E:FA:A4:DE:E7:C8:EA`, the **debug** key of the development PC |
| SHA-1 of the release key (every published APK since v1.0.8) | `92:07:B4:D8:76:07:FB:53:30:1E:FA:F8:74:06:0B:18:8D:0C:43:58`, **not registered** |
| Supabase "Google" sign-in provider | off, and not used: Kharcha signs in with email, Drive is separate |
| Firebase Authentication | not used by the app (Firebase is only used for push notifications) |

## What to do

All in the project `kharcha-35c62`.

1. **Register the release key** — Firebase console → Project settings → Your
   apps → Kharcha (Android) → *Add fingerprint*, and add the release SHA-1:

   ```
   92:07:B4:D8:76:07:FB:53:30:1E:FA:F8:74:06:0B:18:8D:0C:43:58
   ```

   and its SHA-256:

   ```
   A1:22:24:3E:56:0E:DB:C3:34:68:A5:5C:6A:43:EB:B3:83:3C:58:DC:58:43:22:40:D3:49:FF:93:2D:2D:4C:E5
   ```

2. **Create the Web client** — the simplest way is Firebase console →
   Authentication → Sign-in method → Google → Enable. That creates a "Web
   client (auto created by Google Service)" and an Android client for each
   registered fingerprint. Kharcha does not use Firebase Authentication to
   sign anyone in; enabling the provider is only the quickest way to get the
   clients made.

   (The same can be done by hand in Google Cloud console → APIs & Services →
   Credentials → Create credentials → OAuth client ID: one of type *Web
   application*, and one of type *Android* with package
   `com.nischalpandey.kharcha` and the release SHA-1.)

3. **Switch on the Drive API** — Google Cloud console → APIs & Services →
   Library → *Google Drive API* → Enable.

4. **Consent screen** — Google Cloud console → APIs & Services → OAuth consent
   screen (Google Auth Platform). User type *External*. Under *Data access*
   add the scope `https://www.googleapis.com/auth/drive.appdata`. While the
   app is in *Testing*, only the Google accounts listed under *Test users* can
   connect; press *Publish app* to let anyone. `drive.appdata` is not a
   sensitive scope, so publishing does not need Google's verification review.

5. **Give the app the Web client id**, one of two ways:

   * download the new `google-services.json` from Firebase (it now contains
     the clients) and replace `android/app/google-services.json`; or
   * put the Web client id in `.env`:

     ```
     GOOGLE_SERVER_CLIENT_ID=1234567890-abc123.apps.googleusercontent.com
     ```

   Then build and release as usual (`tool\release.ps1`). An OAuth client id is
   public; it is not a secret.

## How the app behaves meanwhile

A build without a Web client id shows, under Settings → Backup & restore →
Google Drive, a note that Drive backup is not available yet, instead of a
Connect button that cannot work. Cloud backup (Supabase) and backup files are
unaffected.

## How Drive is kept to one account

* The Google account is remembered **per Kharcha account**. On a phone with
  two Kharcha accounts, the Google account one of them connected is never
  reused for the other.
* Signing out of Kharcha also forgets the Google account on the device.
* Every backup in Drive is tagged with the Kharcha account that wrote it, and
  only that account's backups are listed, pruned and offered for restore.
* A backup file itself names its owner, and restoring one into a different
  account is refused.
