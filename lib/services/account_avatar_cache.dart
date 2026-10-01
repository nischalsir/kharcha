import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Keeps a copy of the profile picture of each account that can sign in here
/// with a fingerprint, so the account chooser can show it.
///
/// The chooser appears while nobody is signed in, when an account's picture
/// cannot be fetched: its URL is either private or about to expire. So the
/// picture is saved while that account is signed in, as a file named after a
/// hash of the account's own email. Looking up one account can therefore never
/// return another account's picture, and showing the chooser costs no network
/// request at all.
class AccountAvatarCache {
  AccountAvatarCache({
    Future<Directory> Function()? directory,
    http.Client? client,
  }) : _directory = directory ?? _defaultDirectory,
       _http = client;

  final Future<Directory> Function() _directory;
  final http.Client? _http;

  /// Pictures larger than this are not kept; an avatar never needs to be.
  static const int maxBytes = 2 * 1024 * 1024;

  static Future<Directory> _defaultDirectory() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}/account_avatars');
  }

  /// A stable, filename-safe key for an email, so the address itself is not
  /// written to disk as a file name.
  static String keyFor(String email) {
    // FNV-1a over the normalized address.
    var hash = 0x811c9dc5;
    for (final unit in email.trim().toLowerCase().codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  Future<File> _file(String email) async {
    final dir = await _directory();
    return File('${dir.path}/${keyFor(email)}.img');
  }

  /// The saved picture for [email], or null when there is none.
  Future<File?> fileFor(String email) async {
    try {
      final file = await _file(email);
      return await file.exists() && await file.length() > 0 ? file : null;
    } catch (_) {
      return null;
    }
  }

  /// Saves [bytes] as the picture for [email], replacing any earlier one.
  Future<void> store(String email, Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > maxBytes) return;
    try {
      final file = await _file(email);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
      // The path is reused, so the decoded copy of the old picture must go.
      await FileImage(file).evict();
    } catch (_) {
      // Best effort: the chooser falls back to the account's initial.
    }
  }

  /// Forgets the picture for [email].
  Future<void> remove(String email) async {
    try {
      final file = await _file(email);
      if (await file.exists()) {
        await FileImage(file).evict();
        await file.delete();
      }
    } catch (_) {
      // Nothing to remove.
    }
  }

  /// Fetches the picture at [url] and saves it for [email]. A null [url]
  /// means the account has no picture, so any saved one is dropped. A failed
  /// download leaves the previous copy alone.
  Future<void> capture(String email, String? url) async {
    if (url == null || url.isEmpty) {
      await remove(email);
      return;
    }
    final client = _http ?? http.Client();
    try {
      final response = await client
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return;
      final type = response.headers['content-type'] ?? '';
      if (type.isNotEmpty && !type.startsWith('image/')) return;
      await store(email, response.bodyBytes);
    } catch (_) {
      // Offline or slow: keep whatever was saved before.
    } finally {
      if (_http == null) client.close();
    }
  }
}
