import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The app's pictures, kept on the phone once they have been fetched.
///
/// Cloudinary pictures (the logo, the guide slides, festival photographs,
/// profile pictures) are the same for a given address, so they are stored in
/// the app's own cache folder and shown from there on later launches, with or
/// without a connection. Anything else, such as a short-lived signed link, is
/// loaded the ordinary way.
class AppImages {
  const AppImages._();

  static const String _host = 'res.cloudinary.com';
  static const String _missingKey = 'images.missing.v1';
  static const Duration _retryMissingAfter = Duration(days: 7);
  static const int _parallel = 4;

  static CacheManager? _manager;

  /// Addresses already fetched, or being fetched, in this run of the app.
  static final Set<String> _seen = <String>{};

  /// Turns the on-disk cache on. Called once from `main`; until then (as in
  /// widget tests) pictures load straight from the network.
  static void enableDiskCache() {
    _manager ??= CacheManager(
      Config(
        'kharchaImages',
        // How long an unused picture is kept, not how long it is trusted:
        // a picture replaced on Cloudinary is still picked up when its own
        // cache headers say to look again.
        stalePeriod: const Duration(days: 90),
        maxNrOfCacheObjects: 1000,
      ),
    );
  }

  static bool _cached(String url) =>
      _manager != null && Uri.tryParse(url)?.host == _host;

  /// The provider to show [url] with.
  static ImageProvider provider(String url) => _cached(url)
      ? CachedNetworkImageProvider(url, cacheManager: _manager)
      : NetworkImage(url);

  /// Fetches every picture in [urls] that is not on the phone yet, a few at a
  /// time, in the background. Safe to call repeatedly: a picture is asked for
  /// once per launch, and one the server does not have is left alone for a
  /// week.
  static Future<void> preload(Iterable<String> urls) async {
    final manager = _manager;
    if (manager == null) return;
    final pending = <String>[
      for (final url in urls)
        if (_cached(url) && _seen.add(url)) url,
    ];
    if (pending.isEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final missing = _readMissing(prefs);
      final now = DateTime.now().millisecondsSinceEpoch;
      missing.removeWhere(
        (_, at) => now - at > _retryMissingAfter.inMilliseconds,
      );
      var changed = false;

      var next = 0;
      Future<void> worker() async {
        while (next < pending.length) {
          final url = pending[next++];
          if (missing.containsKey(url)) continue;
          try {
            if (await manager.getFileFromCache(url) != null) continue;
            await manager.downloadFile(url);
          } on HttpExceptionWithStatus catch (error) {
            // Not on the server (a festival without a photograph): remember,
            // so it is not asked for on every launch.
            if (error.statusCode == 404) {
              missing[url] = now;
              changed = true;
            }
          } catch (_) {
            // Offline or interrupted: tried again on the next launch.
            _seen.remove(url);
          }
        }
      }

      await Future.wait(<Future<void>>[
        for (var i = 0; i < _parallel; i++) worker(),
      ]);
      if (changed) await prefs.setString(_missingKey, jsonEncode(missing));
    } catch (error) {
      debugPrint('Images: preload stopped ($error)');
    }
  }

  static Map<String, int> _readMissing(SharedPreferences prefs) {
    try {
      final raw = prefs.getString(_missingKey);
      if (raw == null) return <String, int>{};
      return (jsonDecode(raw) as Map<String, dynamic>).map(
        (key, value) => MapEntry(key, (value as num).toInt()),
      );
    } catch (_) {
      return <String, int>{};
    }
  }
}
