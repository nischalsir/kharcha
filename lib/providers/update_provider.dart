import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_info.dart';
import '../services/app_updater.dart';
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

/// Where an update the app is installing itself stands.
enum UpdateInstallState {
  /// Nothing started.
  idle,
  downloading,

  /// Downloaded and handed to Android's installer, which asks the user to
  /// confirm. Stays here so the installer can be opened again.
  ready,

  /// The download or the hand-over did not go through.
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
    AppUpdater? updater,
    String? installedVersion,
    this.onUpdateFound,
  }) : _service = service ?? UpdateService(),
       _updater = updater ?? AppUpdater(),
       installedVersion = installedVersion ?? AppInfo.version;

  final UpdateService _service;
  final AppUpdater _updater;

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

  UpdateInstallState _installState = UpdateInstallState.idle;
  UpdateProblem? _installProblem;
  double? _downloadProgress;
  int _shownPercent = -1;
  bool _cancelRequested = false;
  File? _downloaded;

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

  /// Whether the update can be downloaded and installed from inside the app:
  /// on Android, when the release has an APK. Otherwise it is opened in the
  /// browser.
  bool get canInstallInApp =>
      _updater.supported && isUpdateAvailable && _latest?.apkUrl != null;

  UpdateInstallState get installState => _installState;

  /// What went wrong, when [installState] is [UpdateInstallState.failed].
  UpdateProblem? get installProblem => _installProblem;

  /// How much of the update has arrived, 0 to 1, or null while the size is
  /// not known yet.
  double? get downloadProgress => _downloadProgress;

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
    // An update that has been installed leaves its file behind.
    if (_status == UpdateStatus.upToDate && _updater.supported) {
      unawaited(_updater.cleanUp());
    }

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

  /// Downloads the latest release inside the app and opens Android's
  /// installer on it. The user confirms the install there.
  Future<void> downloadAndInstall() async {
    final update = _latest;
    if (update == null || _installState == UpdateInstallState.downloading) {
      return;
    }
    _cancelRequested = false;
    _installProblem = null;
    _downloadProgress = null;
    _shownPercent = -1;
    _installState = UpdateInstallState.downloading;
    notifyListeners();
    unawaited(markInformed());
    try {
      final file = await _updater.download(
        update,
        onProgress: _onProgress,
        cancelled: () => _cancelRequested,
      );
      _downloaded = file;
      _downloadProgress = 1;
      _installState = UpdateInstallState.ready;
      notifyListeners();
      await _updater.install(file);
    } on UpdateCancelled {
      _installState = UpdateInstallState.idle;
      _downloadProgress = null;
      notifyListeners();
    } on UpdateFailure catch (failure) {
      debugPrint('Update: $failure');
      _fail(failure.problem);
    } catch (error) {
      debugPrint('Update: $error');
      _fail(UpdateProblem.download);
    }
  }

  /// Opens the installer again on the update that is already downloaded,
  /// for a user who backed out of it.
  Future<void> installDownloaded() async {
    final file = _downloaded;
    if (file == null) return downloadAndInstall();
    try {
      await _updater.install(file);
    } on UpdateFailure catch (failure) {
      debugPrint('Update: $failure');
      _fail(failure.problem);
    }
  }

  /// Stops a download that is under way.
  void cancelDownload() {
    if (_installState == UpdateInstallState.downloading) {
      _cancelRequested = true;
    }
  }

  void _fail(UpdateProblem problem) {
    _installProblem = problem;
    _installState = UpdateInstallState.failed;
    notifyListeners();
  }

  // Listeners hear about each whole percent, not each chunk.
  void _onProgress(int received, int? total) {
    if (total == null || total <= 0) return;
    _downloadProgress = (received / total).clamp(0, 1).toDouble();
    final percent = (_downloadProgress! * 100).floor();
    if (percent == _shownPercent) return;
    _shownPercent = percent;
    notifyListeners();
  }
}
