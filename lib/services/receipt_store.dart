import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/env.dart';
import '../core/errors/app_failure.dart';
import 'pasal_image_store.dart';

/// Receipt pictures attached to transactions.
///
/// They live beside the pasal pictures in the private `kharcha-files` bucket,
/// under the owner's own folder (`<user id>/receipts/<transaction id>.jpg`).
/// The transaction row stores only the path, in `attachment_path`; reading
/// and deleting go through [PasalImageStore], which works on any path in the
/// user's folder.
class ReceiptStore {
  const ReceiptStore();

  static String pathFor(String userId, String transactionId) =>
      '$userId/receipts/$transactionId.jpg';

  SupabaseClient? get _client {
    if (!Env.hasSupabase) return null;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  /// Uploads [bytes] as the receipt of [transactionId] and returns its path.
  Future<String> upload(
    Uint8List bytes, {
    required String transactionId,
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
        'Sign in to attach receipts.',
      );
    }
    final path = pathFor(userId, transactionId);
    try {
      await client.storage
          .from(PasalImageStore.bucket)
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
    // The same path may now hold a different picture; drop its cached URL.
    PasalImageStore.forget(path);
    return path;
  }

  /// Deletes a receipt. Best effort: a leftover file is harmless and private.
  Future<void> remove(String path) => const PasalImageStore().remove(path);

  /// A URL the receipt can be loaded from, or null when it cannot be reached.
  Future<String?> signedUrl(String path) =>
      const PasalImageStore().signedUrl(path);
}
