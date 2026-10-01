# Google Play Protect and Kharcha

Kharcha is installed from an APK, not from Google Play, so Play Protect treats
it as an unknown app. This note records what was checked when Play Protect
went from offering a scan to blocking the install, and what to send Google.

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
  `USE_FINGERPRINT`, `WAKE_LOCK`, and the FCM receive permission. None of the
  permissions Play Protect blocks sideloaded apps for (`READ_SMS`,
  `RECEIVE_SMS`, notification listener, accessibility) is requested.
- **Components** no accessibility service, device admin, notification
  listener, or package installer. The app does not request
  `REQUEST_INSTALL_PACKAGES`; "Update" opens the download in the browser.
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
