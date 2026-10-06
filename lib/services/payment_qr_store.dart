import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/env.dart';
import '../core/errors/app_failure.dart';
import 'pasal_image_store.dart';

/// Whose payment QR a picture is.
enum PaymentQrOwner {
  pasal('pasal'),
  friend('friend');

  const PaymentQrOwner(this.code);

  final String code;
}

/// Payment QR pictures of shops and friends: the code a wallet app scans to
/// pay them.
///
/// They live beside the receipts in the private `kharcha-files` bucket, under
/// the owner's own folder (`<user id>/qr/<pasal|friend>-<id>-<time>.jpg`).
/// The pasal or friend row stores only the path, in `qr_path`; reading and
/// deleting go through [PasalImageStore], which works on any path in the
/// user's folder.
class PaymentQrStore {
  const PaymentQrStore();

  /// A new path for every upload: a replaced QR must never be shown from a
  /// phone's cache of the old one, least of all for something that is paid.
  static String pathFor(
    String userId,
    PaymentQrOwner owner,
    String id, {
    DateTime? now,
  }) =>
      '$userId/qr/${owner.code}-$id-'
      '${(now ?? DateTime.now()).millisecondsSinceEpoch}.jpg';

  SupabaseClient? get _client {
    if (!Env.hasSupabase) return null;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  /// Uploads [bytes] as the QR of the pasal or friend [id] and returns its
  /// path.
  Future<String> upload(
    Uint8List bytes, {
    required PaymentQrOwner owner,
    required String id,
  }) async {
    if (bytes.length > PasalImageStore.maxBytes) {
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
        'Sign in to save a payment QR.',
      );
    }
    final path = pathFor(userId, owner, id);
    try {
      await client.storage
          .from(PasalImageStore.bucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(contentType: 'image/jpeg'),
          );
    } catch (error) {
      throw AppFailure.from(error);
    }
    return path;
  }

  /// Deletes a QR. Best effort: a leftover file is harmless and private.
  Future<void> remove(String path) => const PasalImageStore().remove(path);

  /// A URL the QR can be loaded from, or null when it cannot be reached.
  Future<String?> signedUrl(String path) =>
      const PasalImageStore().signedUrl(path);
}
