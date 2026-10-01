import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/errors/app_failure.dart';
import 'supabase_service.dart';

/// A backup file stored in Supabase Storage.
class CloudBackupFile {
  const CloudBackupFile({
    required this.name,
    required this.path,
    required this.updatedAt,
    this.size,
  });

  final String name;
  final String path;
  final DateTime updatedAt;
  final int? size;
}

/// Stores Kharcha backups in the app's Supabase Storage bucket.
///
/// Files live under `<user-id>/backups/`, the same per-user folder scheme used
/// for avatars, so the existing storage policies cover them. Sign-in reuses the
/// app's normal session (anonymous or the configured sync account), so there is
/// nothing extra to configure.
class SupabaseBackupService {
  SupabaseBackupService({SupabaseService? remote})
    : _remote = remote ?? SupabaseService();

  /// Shared bucket used for avatars and backups.
  static const String bucket = 'kharcha-files';
  static const String folderName = 'backups';

  /// How many cloud backups to keep before pruning the oldest.
  static const int maxBackups = 10;

  final SupabaseService _remote;

  bool get isConfigured => _remote.isConfigured;
  String? get userId => _remote.userId;

  SupabaseClient get _client {
    if (!_remote.isConfigured) {
      throw const AppFailure(
        FailureKind.syncFailed,
        'Backend is not configured.',
      );
    }
    return Supabase.instance.client;
  }

  Future<String> _ensureUser() async {
    final uid = _remote.hasSession ? _remote.userId : null;
    if (uid == null) {
      throw const AppFailure(
        FailureKind.syncFailed,
        'Sign in to use cloud backup.',
      );
    }
    return uid;
  }

  String _folderFor(String uid) => '$uid/$folderName';

  /// Uploads [jsonText] as a new timestamped backup and prunes old ones.
  Future<CloudBackupFile> upload(String jsonText) async {
    final uid = await _ensureUser();
    final name = 'kharcha-backup-${_timestamp(DateTime.now())}.json';
    final path = '${_folderFor(uid)}/$name';
    final bytes = Uint8List.fromList(utf8.encode(jsonText));
    try {
      await _client.storage
          .from(bucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              upsert: true,
              contentType: 'application/json',
              cacheControl: '60',
            ),
          );
    } catch (error) {
      throw AppFailure.from(error);
    }
    await _prune(uid);
    return CloudBackupFile(
      name: name,
      path: path,
      updatedAt: DateTime.now(),
      size: bytes.length,
    );
  }

  /// Lists cloud backups newest-first.
  Future<List<CloudBackupFile>> listBackups() async {
    final uid = await _ensureUser();
    return _list(uid);
  }

  Future<List<CloudBackupFile>> _list(String uid) async {
    try {
      final objects = await _client.storage
          .from(bucket)
          .list(path: _folderFor(uid));
      final result = <CloudBackupFile>[];
      for (final object in objects) {
        final name = object.name;
        if (!name.endsWith('.json')) continue;
        result.add(
          CloudBackupFile(
            name: name,
            path: '${_folderFor(uid)}/$name',
            updatedAt:
                DateTime.tryParse(object.updatedAt ?? object.createdAt ?? '')
                    ?.toLocal() ??
                DateTime.fromMillisecondsSinceEpoch(0),
            size: _sizeOf(object.metadata),
          ),
        );
      }
      result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return result;
    } catch (error) {
      throw AppFailure.from(error);
    }
  }

  /// Downloads a backup's raw JSON text.
  Future<String> download(CloudBackupFile file) async {
    await _ensureUser();
    try {
      final bytes = await _client.storage.from(bucket).download(file.path);
      return utf8.decode(bytes);
    } catch (error) {
      throw AppFailure.from(error);
    }
  }

  Future<void> delete(CloudBackupFile file) async {
    await _ensureUser();
    try {
      await _client.storage.from(bucket).remove(<String>[file.path]);
    } catch (error) {
      throw AppFailure.from(error);
    }
  }

  Future<void> _prune(String uid) async {
    try {
      final backups = await _list(uid);
      if (backups.length <= maxBackups) return;
      final paths = backups
          .skip(maxBackups)
          .map((file) => file.path)
          .toList(growable: false);
      await _client.storage.from(bucket).remove(paths);
    } on Object {
      // Pruning is best-effort and must never fail a successful upload.
    }
  }

  int? _sizeOf(Map<String, dynamic>? metadata) {
    if (metadata == null) return null;
    final value = metadata['size'] ?? metadata['contentLength'];
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  String _timestamp(DateTime value) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${value.year}${two(value.month)}${two(value.day)}'
        '-${two(value.hour)}${two(value.minute)}${two(value.second)}';
  }
}
