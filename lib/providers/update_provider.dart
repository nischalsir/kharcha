import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_info.dart';
import '../services/update_service.dart';

/// Where the update check stands.
enum UpdateStatus {
  /// Not checked yet this launch.
  unknown,
  checking,

  /// Checked: the installed version is the latest.
  upToDate,

  /// Checked: a newer release exists.
  available,

  /// The check could not be made (offline, service unavailable).
  failed,
}

/// The one source of truth about app updates.
///
/// The startup prompt, the update notification and the About page all read
/// this, so they cannot disagree about whether there is an update. The check
/// runs once per launch from here; nothing else compares versions.
class UpdateProvider extends ChangeNotifier {
  UpdateProvider({
    UpdateService? service,
    String? installedVersion,
    this.onUpdateFound,
    Future<Directory> Function()? cacheDirectory,
  }) : _service = service ?? UpdateService(),
       _cacheDirectory = cacheDirectory ?? getTemporaryDirectory,
       installedVersion = installedVersion ?? AppInfo.version;

  final UpdateService _service;
  final Future<Directory> Function() _cacheDirectory;

  /// The version of the app that is running.
  final String installedVersion;

  /// Called once per launch when an update the user has not silenced is
  /// found. The app posts the update notification from here.
  final Future<void> Function(UpdateInfo update)? onUpdateFound;

  static const String _dontRemindKey = 'update.dont_remind_version';
  static const String _informedKey = 'update.informed_version';

  UpdateStatus _status = UpdateStatus.unknown;
  UpdateInfo? _latest;
  String? _dontRemindForVersion;
  String? _informedVersion;
  Future<void>? _launchCheck;
  bool _promptTaken = false;
  bool _notified = false;

  UpdateStatus get status => _status;

  /// The latest published release, once known.
  UpdateInfo? get latest => _latest;
  String? get latestVersion => _latest?.version;
  String? get updateUrl => _latest?.downloadUrl;
  String? get releaseNotes => _latest?.notes;

  /// True only when a check succeeded and found a newer release. An
  /// unavailable or failed check never claims an update.
  bool get isUpdateAvailable {
    final latest = _latest;
    return latest != null &&
        UpdateService.isNewer(latest.version, installedVersion);
  }

  /// The release the user asked not to be reminded about, if any.
  String? get dontRemindForVersion => _dontRemindForVersion;

  /// The release the user last pressed Download for. It records that they
  /// were told, nothing more: the app only counts as updated when
  /// [installedVersion] itself changes.
  String? get informedVersion => _informedVersion;

  /// Whether the user should be reminded: there is an update, and it is not
  /// the one they silenced. A newer release than the silenced one prompts
  /// again, because it is a different version.
  bool get shouldRemind {
    final latest = _latest;
    if (latest == null || !isUpdateAvailable) return false;
    final silenced = _dontRemindForVersion;
    return silenced == null ||
        UpdateService.compareVersions(latest.version, silenced) > 0;
  }

  /// Whether the startup prompt is still owed this launch.
  bool get promptPending => shouldRemind && !_promptTaken;

  /// Claims the startup prompt. Returns true exactly once per launch, and
  /// only when there is something to prompt about, so rebuilds, navigation
  /// and auth changes cannot show it twice.
  bool takePrompt() {
    if (!promptPending) return false;
    _promptTaken = true;
    return true;
  }

  /// The launch check. Safe to call from anywhere, any number of times: the
  /// first call does the work and every later one gets the same result.
  Future<void> checkOnLaunch() => _launchCheck ??= _check();

  /// Checks again on request (the About page's button).
  Future<void> refresh() => _check();

  Future<void> _check() async {
    _status = UpdateStatus.checking;
    notifyListeners();

    await _loadPreferences();
    final latest = await _service.fetchLatest();
    if (latest == null) {
      // Keep what an earlier check found; just report this one failed.
      _status = _latest == null ? UpdateStatus.failed : _statusFor(_latest!);
      notifyListeners();
      return;
    }
    _latest = latest;
    _status = _statusFor(latest);
    await _dropStaleSuppression();
    notifyListeners();
    unawaited(_removeOldDownloads());

    if (shouldRemind && !_notified) {
      _notified = true;
      final notify = onUpdateFound;
      if (notify != null) {
        try {
          await notify(latest);
        } catch (error) {
          debugPrint('Update: could not post the notification ($error)');
        }
      }
    }
  }

  UpdateStatus _statusFor(UpdateInfo latest) =>
      UpdateService.isNewer(latest.version, installedVersion)
      ? UpdateStatus.available
      : UpdateStatus.upToDate;

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _dontRemindForVersion = prefs.getString(_dontRemindKey);
      _informedVersion = prefs.getString(_informedKey);
    } catch (_) {
      // No preferences store: behave as if nothing was ever silenced.
    }
  }

  /// A silenced version that is now installed (or older) has done its job.
  Future<void> _dropStaleSuppression() async {
    final silenced = _dontRemindForVersion;
    if (silenced == null) return;
    if (UpdateService.compareVersions(silenced, installedVersion) > 0) return;
    _dontRemindForVersion = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_dontRemindKey);
    } catch (_) {
      // Best effort.
    }
  }

  /// "Don't remind": stop prompting about this release. Only this release;
  /// the next one prompts again.
  Future<void> dontRemind() async {
    final version = latestVersion;
    if (version == null) return;
    _dontRemindForVersion = version;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_dontRemindKey, version);
    } catch (_) {
      // Kept for this run at least.
    }
  }

  /// "Download" was pressed for the latest release.
  Future<void> markInformed() async {
    final version = latestVersion;
    if (version == null) return;
    _informedVersion = version;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_informedKey, version);
    } catch (_) {
      // Informational only.
    }
  }

  /// Up to v2.2 the app downloaded its own update into its cache, to hand
  /// to Android's installer. Updates are downloaded by the browser now, so
  /// whatever such a version left behind (the size of the whole app) is
  /// removed.
  Future<void> _removeOldDownloads() async {
    try {
      final folder = Directory('${(await _cacheDirectory()).path}/updates');
      if (folder.existsSync()) folder.deleteSync(recursive: true);
    } catch (_) {
      // Only space; Android clears the cache itself when it needs to.
    }
  }
}
