# Google Play Protect and Kharcha

Kharcha is installed from an APK, not from Google Play, so Play Protect treats
it as an unknown app. This note records what was checked when Play Protect
went from offering a scan to blocking the install, and what to send Google.

## The scan prompt: "Play Protect hasn't seen this app before"

This is the prompt people meet most, and it is not a verdict on Kharcha.

Since October 2023 Play Protect offers a real-time scan for **any APK file it
has never seen**, whoever made it. It looks at the file itself, not at the
app's name or reputation. Tapping **Scan app** sends the file to Google, which
checks it and, a few seconds later, lets the install go on.

Why other open-source apps do not show it: their APKs have already been
installed by thousands of people, so Google has seen each file. Kharcha has few
installs, and **every release is a new file**, so the first people to install
each release are asked.

Nothing in the app or the build can switch this off. It runs in Google Play
services on the phone, before Kharcha's code is ever started, and an app that
tried to avoid it is exactly what it exists to catch. What does reduce it:

1. **Release less often.** Ten releases in a day are ten files Google has not
   seen. One release with ten changes is one.
2. **Scan each release yourself, first.** Right after publishing, install the
   release's APK on a phone and choose **Scan app**. Once Google has checked
   that file, people who install the same file later are usually not asked.
3. **Publish on Google Play** (a one-time USD 25). Apps installed from Play are
   not prompted at all. This is the only way to remove it for everyone.
4. **Register as a developer** (see "What to do" below). It ties the package
   name and the signing key to a known developer.

The rest of this note is about the stronger case, where Play Protect blocks
the install instead of offering a scan.

## The block in v1.6 to v2.1.1: the SMS permission

From v1.6 the app asked for `READ_SMS`, to find bank and wallet payment
alerts among the phone's messages. People installing those versions were
stopped by Play Protect with a warning that the app may be a scam, and could
not install it at all.

That is Play Protect doing what it says it does. For an app installed from a
file (not from Google Play), it blocks the install when the app declares one
of the permissions fraud apps use to steal one-time passwords: `READ_SMS`,
`RECEIVE_SMS`, the notification listener, or accessibility. It does not look
at what the app does with the permission, only that it asks. An app that can
also install packages (`REQUEST_INSTALL_PACKAGES`, for the in-app updater)
and reads SMS has the same outline as a banking trojan.

v2.2 removes it:

- `READ_SMS` is no longer in the manifest, and the code that read the inbox
  (`SmsReader.kt`, the `sms` method channel) is deleted.
- More > Import from SMS still exists. The messages are copied in the
  messages app and pasted in, which needs no permission.
- `test/v2_2_features_test.dart` fails if any of those permissions is ever
  declared again.

**Do not add an SMS, notification-listener or accessibility permission back**
while the app is distributed as an APK. Only an app on Google Play, with the
SMS use declared and approved there, can hold it.

## v2.3: no install permission either

`REQUEST_INSTALL_PACKAGES` is the other permission Play Protect counts
against an app installed from a file. Up to v2.2 the app used it to hand an
update it had downloaded to Android's installer. v2.3 removes it, with the
code that used it (`AppUpdates.kt`, the `app_update` channel, the file
provider and `app_updater.dart`):

- "Download update" opens the release's APK in the browser. The browser
  downloads it and the user opens the file; the browser, not Kharcha, is what
  Android asks about installing from.
- The app picks the APK made for the phone's processor when a release has
  one, otherwise the one for every phone (`UpdateService.pickApk`).
- `test/v2_3_features_test.dart` fails if the permission comes back.

After v2.3 the app asks for nothing Play Protect singles out: internet,
notifications, vibration, biometrics and approximate location.

## Register as a developer (do this before 2027)

Google is bringing in developer verification for Android: on certified
phones, an app installed from a file will have to come from a developer who
has registered the app's package name and signing key. It began on
30 September 2026 in Brazil, Indonesia, Singapore and Thailand and is due
everywhere else during 2027. An unregistered app will then be refused at
install time, whatever its permissions.

What to do, once, from a computer:

1. Open <https://developer.android.com/developer-verification> and choose
   the Android Developer Console (the one for apps distributed outside Google
   Play). Students and hobbyists get a free account with a limit on how many
   devices can install; a full account is a one-time USD 25 (it needs a
   card).

   The free account cannot register Kharcha as it is. Tried on 7 October
   2026: "The package name you've entered already exists on Android. You
   can only register new package names that have never been seen before on
   Android using a limited distribution Android Developer Console account."
   `com.nischalpandey.kharcha` has been installed on phones, so it needs the
   full account, or the app would have to take a new package name, which
   makes it a different app that nobody can update to.
2. Verify your identity as it asks.
3. Register the app: package name `com.nischalpandey.kharcha` and the signing
   certificate's SHA-256 fingerprint (it is in the table below). Proving
   ownership means uploading an APK signed with the release key; use the
   latest `kharcha-vX.apk` from GitHub Releases.
4. Keep signing every release with the same key (`android/app/kharcha-release.jks`).
   A copy of it and its passwords is in `C:\Users\nisch\Kharcha-keys`; put
   that folder on a USB drive as well. Without the key the registration, and
   every installed copy of the app, is stranded.

## What changed

The block started with v1.0.8. Comparing the published v1.0.7 APK with v1.0.8
and later builds, exactly one thing differs:

| | v1.0.7 | v1.0.8 and later |
| --- | --- | --- |
| Signing certificate | `CN=Android Debug, O=Android, C=US` | `CN=Nischal Pandey, O=Kharcha, C=NP` |

Everything else is identical: application id, permissions, SDK levels, native
libraries and components. The v1.0.8 key is new, so Google has never seen an
app signed with it.

## What was ruled out

Checked on the built release APK with `aapt2` and `apksigner`:

- **Application id** `com.nischalpandey.kharcha`, unchanged.
- **Build type** release; `android:debuggable` is absent.
- **Signing** the release key from `android/key.properties`, APK Signature
  Scheme v2, RSA 2048. Not debug-signed.
- **SDK levels** min 24, target 36, compile 36. Play Protect's "built for an
  older version of Android" block does not apply.
- **Permissions** `INTERNET`, `ACCESS_NETWORK_STATE`, `POST_NOTIFICATIONS`,
  `VIBRATE`, `USE_BIOMETRIC`,
  `USE_FINGERPRINT`, `WAKE_LOCK`, `ACCESS_COARSE_LOCATION` (weather only, optional), and the FCM receive permission. None of the
  permissions Play Protect blocks sideloaded apps for (`READ_SMS`,
  `RECEIVE_SMS`, notification listener, accessibility) is requested. (True
  up to v1.5 and again from v2.2; v1.6 to v2.1.1 asked for `READ_SMS`, see
  above.)
- **Components** no accessibility service, device admin or notification
  listener. Up to v1.0.21 the app did not request `REQUEST_INSTALL_PACKAGES`
  and "Update" opened the download in the browser.
- **From v1.1 to v2.2** the app downloaded its own update and handed it to
  Android's installer, which needs `REQUEST_INSTALL_PACKAGES` (removed in
  v2.3, see above). Android still asks the
  user to confirm each install and to allow Kharcha as a source the first
  time, and only accepts an APK signed with the same key. This permission is
  one Play Protect looks at for apps installed from outside Google Play; if
  its warnings get worse after v1.1, this is the change to look at first. It
  has nothing to do with the scan prompt above, which looks only at whether
  the file has been seen.
- **Network** no cleartext traffic and no custom network security config.
- **Code** standard Flutter release build, no dynamic code loading.

Nothing in the project asks for the block, so there is nothing to change in
the code or the build to remove it. It is a verdict on Google's side about an
app and a signing key it does not know.

## What to do

Do not work around Play Protect. The legitimate routes are:

1. **Appeal.** File a Play Protect appeal:
   <https://support.google.com/googleplay/android-developer/contact/protectappeals>.
   It asks for the details in the next section and a public link to the APK.
2. **Keep signing with the same key.** Changing the key again resets what
   Google knows about the app. `android/app/kharcha-release.jks` and
   `android/key.properties` must be backed up and never committed.
3. **Register as a developer.** Google's Android developer verification lets a
   developer register a package name and signing key. The limited distribution
   account is free and needs no ID, but covers 20 devices. Publishing on Google
   Play removes the warning entirely and costs a one-time USD 25.

The exact wording on the block screen matters for the appeal. "Harmful app
blocked" and "App blocked to protect your device" are different verdicts; note
which one is shown.

## Details for the appeal

| Field | Value |
| --- | --- |
| App name | Kharcha |
| Package name | `com.nischalpandey.kharcha` |
| Signing certificate subject | `CN=Nischal Pandey, O=Kharcha, C=NP` |
| Certificate SHA-256 | `A1:22:24:3E:56:0E:DB:C3:34:68:A5:5C:6A:43:EB:B3:83:3C:58:DC:58:43:22:40:D3:49:FF:93:2D:2D:4C:E5` |
| Certificate SHA-1 | `92:07:B4:D8:76:07:FB:53:30:1E:FA:F8:74:06:0B:18:8D:0C:43:58` |
| Signature scheme | APK Signature Scheme v2, RSA 2048 |
| APK download | the `.apk` asset on <https://github.com/nischalsir/kharcha/releases/latest> |
| Source | <https://github.com/nischalsir/kharcha> |
| Use case | Personal expense tracker for Nepal: records spending, budgets and shop credit, synced to the user's own account. |

To re-check a build:

```bash
aapt2 dump badging build/app/outputs/flutter-apk/app-release.apk
apksigner verify --verbose --print-certs build/app/outputs/flutter-apk/app-release.apk
```
