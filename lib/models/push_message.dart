import 'dart:convert';

import '../models/push_category.dart';

/// A notification the backend wants to show, as delivered over FCM.
///
/// The sender (`send-push`) builds these on the server, so the wire shape is a
/// contract: the Edge Function validates incoming messages against it and this
/// class is the Dart side of the same contract.
///
/// Every Kharcha notification is a **data** message, never a `notification`
/// payload. That is deliberate:
///  - the app then renders it itself, so the foreground, background and
///    terminated cases all go through one code path and always use Kharcha's
///    channels, accent and icon;
///  - a `notification` payload would be drawn by the OS, bypassing that, and
///    would double up with the Dart-rendered foreground copy.
class PushMessage {
  const PushMessage({
    required this.category,
    required this.title,
    required this.body,
    this.data = const <String, String>{},
  });

  /// Wire values of [PushCategory.id].
  final String category;

  final String title;
  final String body;

  /// Arbitrary routing/display extras, all strings because FCM data payloads
  /// are string-only.
  ///
  /// Recognised keys:
  ///  - `route`: a `RoutePaths` value to open on tap
  ///  - `route_args`: JSON-encoded single argument for the route, if it needs one
  final Map<String, String> data;

  PushCategory? get resolvedCategory => PushCategory.byId(category);

  PushChannel get channel => resolvedCategory?.channel ?? PushChannel.fallback;

  PushImportance get importance =>
      resolvedCategory?.importance ?? PushImportance.defaultImportance;

  /// Route to open on tap, or null to just foreground the app.
  String? get route {
    final value = data['route'];
    if (value == null || value.isEmpty) return null;
    return value;
  }

  /// Single positional argument for [route], e.g. a friend or pasal id.
  String? get routeArgs {
    final value = data['route_args'];
    if (value == null || value.isEmpty) return null;
    return _tryDecode(value);
  }

  /// Parses a message delivered by FCM, returning null when it is not one of
  /// ours or is too malformed to render.
  ///
  /// Returns null (rather than throwing) for an unrecognised category so an
  /// unknown category from a newer server still shows in the fallback channel
  /// instead of being silently dropped.
  static PushMessage? fromData(Map<String, dynamic> data) {
    final title = (data['title'] as String?)?.trim();
    final body = (data['body'] as String?)?.trim();
    final category = (data['category'] as String?)?.trim();
    if (title == null || title.isEmpty) return null;
    if (body == null || body.isEmpty) return null;
    if (category == null || category.isEmpty) return null;

    final extras = <String, String>{};
    for (final entry in data.entries) {
      if (entry.key == 'title' ||
          entry.key == 'body' ||
          entry.key == 'category') {
        continue;
      }
      final value = entry.value;
      if (value is String) {
        extras[entry.key] = value;
      } else if (value != null) {
        extras[entry.key] = value.toString();
      }
    }

    return PushMessage(
      category: category,
      title: title,
      body: body,
      data: extras,
    );
  }

  /// `route_args` is JSON-encoded so it can carry a string or an int; every
  /// current route takes a single String id, so decode then stringify.
  ///
  /// Returns null for anything else, and never throws: a malformed
  /// `route_args` must degrade to "no argument" rather than drop the tap
  /// target entirely.
  static String? _tryDecode(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.length >= 2 &&
        trimmed.startsWith('"') &&
        trimmed.endsWith('"')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is String) return decoded;
      } catch (_) {
        return null;
      }
    }
    if (int.tryParse(trimmed) != null) return trimmed;
    return null;
  }
}
