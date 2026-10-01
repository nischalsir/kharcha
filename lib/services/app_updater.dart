import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'update_service.dart';

/// Why an update could not be downloaded or handed to the installer.
enum UpdateProblem {
  /// The download did not finish: no connection, or it was cut short.
  download,

  /// The file arrived but Android would not open its installer on it.
  install,
}

/// A download or an install that did not go through.
class UpdateFailure implements Exception {
  const UpdateFailure(this.problem, [this.detail = '']);

  final UpdateProblem problem;
  final String detail;

  @override
  String toString() => 'UpdateFailure(${problem.name}, $detail)';
}

/// The download was stopped by the user.
class UpdateCancelled implements Exception {
  const UpdateCancelled();
}

/// Updates the app from inside the app: downloads the release's APK into the
/// app's own cache and hands it to Android's installer.
///
/// Nothing is installed silently. Android asks the user to confirm, asks them
/// to allow Kharcha as a source the first time, and refuses any APK that is
/// not signed with the key the installed app was signed with, so a file that
/// was swapped or damaged on the way cannot be installed.
class AppUpdater {
  AppUpdater({
    http.Client? client,
    MethodChannel? channel,
    Future<Directory> Function()? cacheDirectory,
  }) : _client = client ?? http.Client(),
       _channel = channel ?? const MethodChannel(channelName),
       _cacheDirectory = cacheDirectory ?? getTemporaryDirectory;

  static const String channelName = 'com.nischalpandey.kharcha/app_update';

  /// The folder inside the app's cache the update is kept in. The Android
  /// side only ever hands the installer a file from this folder.
  static const String folderName = 'updates';

  final http.Client _client;
  final MethodChannel _channel;
  final Future<Directory> Function() _cacheDirectory;

  /// Whether this device can be updated from inside the app. Elsewhere the
  /// update is opened in the browser, as before.
  bool get supported => Platform.isAndroid;

  Future<Directory> _folder() async =>
      Directory('${(await _cacheDirectory()).path}/$folderName');

  /// Where the APK of [version] is kept once downloaded.
  Future<File> fileFor(String version) async {
    final safe = version.replaceAll(RegExp(r'[^0-9A-Za-z.]'), '_');
    return File('${(await _folder()).path}/kharcha-$safe.apk');
  }

  /// Downloads the APK of [update] and returns it.
  ///
  /// [onProgress] is told how many bytes have arrived, and how many there
  /// will be when that is known. Returning true from [cancelled] stops the
  /// download with [UpdateCancelled]. A file already downloaded in full is
  /// returned at once.
  Future<File> download(
    UpdateInfo update, {
    void Function(int received, int? total)? onProgress,
    bool Function()? cancelled,
  }) async {
    final url = update.apkUrl;
    final uri = url == null ? null : Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') {
      throw const UpdateFailure(UpdateProblem.download, 'no APK to download');
    }
    final folder = await _folder();
    final target = await fileFor(update.version);
    final expected = update.apkSize;

    try {
      if (expected != null &&
          target.existsSync() &&
          target.lengthSync() == expected) {
        onProgress?.call(expected, expected);
        return target;
      }
      // Anything else in the folder is an older update or a download that
      // was cut short.
      if (folder.existsSync()) folder.deleteSync(recursive: true);
      folder.createSync(recursive: true);

      final response = await _client
          .send(http.Request('GET', uri))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw UpdateFailure(
          UpdateProblem.download,
          'HTTP ${response.statusCode}',
        );
      }
      final total = expected ?? response.contentLength;
      final part = File('${target.path}.part');
      final sink = part.openWrite();
      var received = 0;
      try {
        // A connection that goes quiet is treated as lost rather than left
        // to hang with a progress bar that never moves.
        await for (final chunk in response.stream.timeout(
          const Duration(seconds: 30),
        )) {
          if (cancelled?.call() ?? false) throw const UpdateCancelled();
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
      } finally {
        await sink.close();
      }
      if (received == 0 || (expected != null && received != expected)) {
        throw UpdateFailure(
          UpdateProblem.download,
          'got $received of ${expected ?? '?'} bytes',
        );
      }
      return part.renameSync(target.path);
    } on UpdateCancelled {
      await cleanUp();
      rethrow;
    } on UpdateFailure {
      await cleanUp();
      rethrow;
    } catch (error) {
      await cleanUp();
      throw UpdateFailure(UpdateProblem.download, '$error');
    }
  }

  /// Opens Android's installer on [apk]. Returns once the installer is on
  /// screen; the install itself is the user's to confirm.
  Future<void> install(File apk) async {
    String? outcome;
    try {
      outcome = await _channel.invokeMethod<String>('install', <String, String>{
        'path': apk.path,
      });
    } catch (error) {
      throw UpdateFailure(UpdateProblem.install, '$error');
    }
    if (outcome != 'started') {
      throw UpdateFailure(UpdateProblem.install, outcome ?? 'no answer');
    }
  }

  /// Removes downloaded updates. Called once the app is up to date, so an
  /// installed update does not stay behind taking space.
  Future<void> cleanUp() async {
    try {
      final folder = await _folder();
      if (folder.existsSync()) folder.deleteSync(recursive: true);
    } catch (_) {
      // Only space; Android clears the cache itself when it needs to.
    }
  }
}
