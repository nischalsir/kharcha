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
  `RECEIVE_BOOT_COMPLETED`, `VIBRATE`, `SCHEDULE_EXACT_ALARM`, `USE_BIOMETRIC`,
  `USE_FINGERPRINT`, `WAKE_LOCK`, `ACCESS_COARSE_LOCATION` (weather only, optional), and the FCM receive permission. None of the
  permissions Play Protect blocks sideloaded apps for (`READ_SMS`,
  `RECEIVE_SMS`, notification listener, accessibility) is requested.
- **Components** no accessibility service, device admin or notification
  listener. Up to v1.0.21 the app did not request `REQUEST_INSTALL_PACKAGES`
  and "Update" opened the download in the browser.
- **From v1.1** the app downloads its own update and hands it to Android's
  installer, which needs `REQUEST_INSTALL_PACKAGES`. Android still asks the
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
