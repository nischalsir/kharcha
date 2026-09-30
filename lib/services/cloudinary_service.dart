import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/errors/app_failure.dart';

/// Uploads and serves user photos through Cloudinary.
///
/// Uploads are signed by the `media-sign` Edge Function, which also decides
/// the storage path from the verified user id - the app never holds the API
/// secret and cannot choose where a file lands.
class CloudinaryService {
  CloudinaryService({this._client, http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  final SupabaseClient? _client;
  final http.Client _http;

  SupabaseClient get _supabase => _client ?? Supabase.instance.client;

  /// Uploads [bytes] as the signed-in user's avatar and returns its
  /// Cloudinary `secure_url` (versioned, so a new photo busts caches).
  Future<String> uploadAvatar(Uint8List bytes, {required String filename}) async {
    final signed = await _supabase.functions.invoke(
      'media-sign',
      body: const <String, String>{'action': 'upload', 'kind': 'avatar'},
    );
    final data = signed.data;
    if (data is! Map || data['uploadUrl'] is! String || data['params'] is! Map) {
      throw const AppFailure(
        FailureKind.syncFailed,
        'Could not prepare the photo upload.',
      );
    }

    final request = http.MultipartRequest('POST', Uri.parse(data['uploadUrl'] as String))
      ..fields.addAll(<String, String>{
        for (final entry in (data['params'] as Map).entries)
          '${entry.key}': '${entry.value}',
      })
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));

    final response = await http.Response.fromStream(await _http.send(request));
    final decoded = jsonDecode(response.body);
    if (response.statusCode != 200 || decoded is! Map || decoded['secure_url'] is! String) {
      final message = decoded is Map && decoded['error'] is Map
          ? '${(decoded['error'] as Map)['message']}'
          : 'HTTP ${response.statusCode}';
      throw AppFailure(FailureKind.syncFailed, 'Photo upload failed ($message).');
    }
    return decoded['secure_url'] as String;
  }

  /// Deletes the signed-in user's avatar on Cloudinary (server side).
  Future<void> deleteAvatar() async {
    await _supabase.functions.invoke(
      'media-sign',
      body: const <String, String>{'action': 'destroy', 'kind': 'avatar'},
    );
  }

  /// Inserts a delivery transformation into a Cloudinary URL, e.g.
  /// `f_auto,q_auto,w_800`. Non-Cloudinary URLs are returned unchanged, so
  /// callers can pass any URL through this.
  static String transform(String url, String transformation) {
    const marker = '/image/upload/';
    final index = url.indexOf(marker);
    if (index < 0 || !url.contains('res.cloudinary.com')) return url;
    final split = index + marker.length;
    return '${url.substring(0, split)}$transformation/${url.substring(split)}';
  }

  /// Square, face-centred avatar in the best format the device accepts.
  static String avatarUrl(String url, {int size = 256}) =>
      transform(url, 'c_fill,g_face,w_$size,h_$size,f_auto,q_auto');

  /// Width-limited image in the best format and quality for the device.
  static String optimized(String url, {int width = 800}) =>
      transform(url, 'f_auto,q_auto,w_$width,c_limit');
}
