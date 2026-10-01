# Kharcha v1.0.13

## 🔔 Notifications that actually arrive

- **Push notifications fixed.** Flame reactions, good-morning / good-night greetings and AI tips now reach your phone as real notifications, including when the app is closed.
- **No more blank or doubled notifications** when the app is in the background. Every notification now uses Kharcha's own channels, icon and tap routing.
- **Notifications stack instead of replacing each other** when several arrive while the app is closed.

## ✨ Seven new reminder types

These were in Settings before but never fired. They all work now, in your own local time and Nepali calendar months:

| | Reminder | When |
|---|---|---|
| 🚨 | **Budget alerts** | Within the hour your monthly or weekly budget passes 80% or 100% (8 am–10 pm) |
| 📅 | **Upcoming payments** | 9 am, for recurring bills due today or tomorrow |
| 🤝 | **Friend reminders** | 9 am, when money you lent or borrowed is due today or tomorrow |
| ⏰ | **Overdue payments** | 9 am, a weekly nudge for past-due friend and pasal payments |
| 🏪 | **Pasal month end** | 9 am, the day before the Nepali month ends, if you still owe a pasal |
| 📊 | **Daily summary** | 9 pm (off by default: turn it on in Settings) |
| 📈 | **Weekly summary** | Sunday 9 am (off by default) |

Each one respects its switch in **Settings → Notifications** and is never sent twice.

## 🛠 Under the hood

- Devices from old installs are cleaned up automatically, so notifications stop being sent to phones that no longer have the app.

## Install

1. Download `kharcha-v1.0.13.apk` below.
2. Allow *Install unknown apps* for your browser or file manager if asked.
3. Open the APK → **Update**.

> Signed with the same release key as v1.0.8, so it installs over v1.0.8–v1.0.12 without losing data. If you are still on v1.0.7 or older (signed with the development key), uninstall that first.
