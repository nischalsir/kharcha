import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/env.dart';
import '../core/errors/app_failure.dart';

/// Pictures attached to pasal credit items.
///
/// They live in the private `kharcha-files` bucket under the owner's own
/// folder (`<user id>/pasal/<item id>.jpg`), which the bucket's policies
/// already restrict to that user. The item row stores only the path; a
/// short-lived signed URL is made when the picture is shown.
class PasalImageStore {
  const PasalImageStore();

  static const String bucket = 'kharcha-files';

  /// Largest picture accepted, after the picker has already downscaled it.
  static const int maxBytes = 5 * 1024 * 1024;

  static const Duration _urlLifetime = Duration(hours: 6);

  /// Signed URLs by path, so a list of items asks the server once per picture
  /// rather than on every rebuild.
  static final Map<String, ({String url, DateTime expires})> _urls =
      <String, ({String url, DateTime expires})>{};

  static String pathFor(String userId, String itemId) =>
      '$userId/pasal/$itemId.jpg';

  SupabaseClient? get _client {
    if (!Env.hasSupabase) return null;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  /// Uploads [bytes] as the picture for [itemId] and returns its path.
  Future<String> upload(Uint8List bytes, {required String itemId}) async {
    if (bytes.length > maxBytes) {
      throw const AppFailure(
        FailureKind.invalidData,
        'That picture is too large. Choose one under 5 MB.',
      );
    }
    final client = _client;
    final userId = client?.auth.currentUser?.id;
    if (client == null || userId == null) {
      throw const AppFailure(
        FailureKind.syncFailed,
        'Sign in to attach pictures.',
      );
    }
    final path = pathFor(userId, itemId);
    try {
      await client.storage
          .from(bucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              upsert: true,
              contentType: 'image/jpeg',
            ),
          );
    } catch (error) {
      throw AppFailure.from(error);
    }
    // The same path now holds a different picture.
    _urls.remove(path);
    return path;
  }

  /// Deletes a picture. Best effort: a leftover file is harmless and private.
  Future<void> remove(String path) async {
    _urls.remove(path);
    try {
      await _client?.storage.from(bucket).remove(<String>[path]);
    } catch (_) {
      // Offline or already gone.
    }
  }

  /// A URL the picture can be loaded from, or null when it cannot be reached
  /// (offline, signed out, or the file no longer exists).
  Future<String?> signedUrl(String path) async {
    final cached = _urls[path];
    if (cached != null && cached.expires.isAfter(DateTime.now())) {
      return cached.url;
    }
    final client = _client;
    final userId = client?.auth.currentUser?.id;
    // Only ever the signed-in user's own folder; the bucket enforces this too.
    if (client == null || userId == null || !path.startsWith('$userId/')) {
      return null;
    }
    try {
      final url = await client.storage
          .from(bucket)
          .createSignedUrl(path, _urlLifetime.inSeconds);
      _urls[path] = (
        url: url,
        // Refreshed a little early, so a URL never expires mid-display.
        expires: DateTime.now().add(_urlLifetime - const Duration(minutes: 10)),
      );
      return url;
    } catch (_) {
      return null;
    }
  }

  /// Forgets every cached URL. Called when a different account takes over.
  static void clearCache() => _urls.clear();
}
