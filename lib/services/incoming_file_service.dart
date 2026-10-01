import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A file another app handed to Kharcha, through Android's Share sheet or
/// "Open with".
class IncomingFile {
  const IncomingFile({
    required this.name,
    this.path,
    this.mimeType,
    this.size = 0,
    this.error,
  });

  /// The file's own name, e.g. `Statement_Jan.pdf`.
  final String name;

  /// Where Android copied it inside the app's private cache. Null when it
  /// could not be copied; see [error].
  final String? path;
  final String? mimeType;
  final int size;

  /// `too_large`, `unreadable` or `unsupported` when the file could not be
  /// taken.
  final String? error;

  static const Set<String> _extensions = <String>{'pdf', 'csv', 'xls', 'xlsx'};
  static const Set<String> _mimeTypes = <String>{
    'application/pdf',
    'text/csv',
    'text/comma-separated-values',
    'application/csv',
    'application/vnd.ms-excel',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  };

  /// Whether the name or type says this could be a statement. The contents
  /// are what finally decide; this only filters out the obvious.
  bool get looksSupported {
    final dot = name.lastIndexOf('.');
    final extension = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
    if (_extensions.contains(extension)) return true;
    return _mimeTypes.contains(mimeType?.toLowerCase());
  }

  static IncomingFile? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    final path = raw['path'];
    final error = raw['error'];
    if (path is! String && error is! String) return null;
    return IncomingFile(
      name: name is String && name.isNotEmpty ? name : 'Shared file',
      path: path is String ? path : null,
      mimeType: raw['mimeType'] as String?,
      size: (raw['size'] as num?)?.toInt() ?? 0,
      error: error is String ? error : null,
    );
  }
}

/// Receives files shared into the app.
///
/// Android grants access to a shared file only briefly, and only to the
/// activity it was sent to. The native side therefore copies the file into
/// the app's own cache straight away and hands over that copy, so nothing
/// here depends on storage permissions or on the grant still being alive.
class IncomingFileService {
  IncomingFileService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName) {
    _channel.setMethodCallHandler(_onCall);
  }

  static const String channelName = 'com.nischalpandey.kharcha/incoming_file';

  final MethodChannel _channel;
  final StreamController<IncomingFile> _files =
      StreamController<IncomingFile>.broadcast();

  /// Files shared while the app is already running.
  Stream<IncomingFile> get files => _files.stream;

  Future<void> _onCall(MethodCall call) async {
    if (call.method != 'incomingFile') return;
    final file = IncomingFile.fromMap(call.arguments);
    if (file != null) _files.add(file);
  }

  /// The file the app was opened with, if it was opened by a share. Returned
  /// once; a second call gives null.
  Future<IncomingFile?> takeInitial() async {
    try {
      return IncomingFile.fromMap(await _channel.invokeMethod('takeInitial'));
    } on MissingPluginException {
      // Not Android, or a test: nothing can be shared in.
      return null;
    } catch (error) {
      debugPrint('Incoming file: could not read the shared file ($error)');
      return null;
    }
  }

  /// Reads the copy and removes it: the bytes are all that is needed, and a
  /// statement should not be left lying in the cache.
  Future<Uint8List> read(IncomingFile file) async {
    final path = file.path;
    if (path == null) throw const FileSystemException('No file was received');
    final copy = File(path);
    try {
      return await copy.readAsBytes();
    } finally {
      unawaited(discard(file));
    }
  }

  Future<void> discard(IncomingFile file) async {
    final path = file.path;
    if (path == null) return;
    try {
      await File(path).delete();
    } catch (_) {
      // Already gone, or the cache was cleared: nothing to do.
    }
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
    _files.close();
  }
}
