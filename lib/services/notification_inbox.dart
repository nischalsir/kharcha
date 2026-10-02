import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/push_message.dart';

/// A notification the app has shown, kept so it can be read again inside the
/// app after it has gone from the phone's notification shade.
@immutable
class InboxItem {
  const InboxItem({
    required this.id,
    required this.title,
    required this.body,
    required this.category,
    required this.receivedAt,
    this.route,
    this.routeArgs,
    this.read = false,
  });

  final String id;
  final String title;
  final String body;
  final String category;
  final DateTime receivedAt;

  /// The page the notification opens, when it names one.
  final String? route;
  final String? routeArgs;
  final bool read;

  InboxItem asRead() => InboxItem(
    id: id,
    title: title,
    body: body,
    category: category,
    receivedAt: receivedAt,
    route: route,
    routeArgs: routeArgs,
    read: true,
  );

  static InboxItem? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final title = raw['title'];
    final at = DateTime.tryParse((raw['at'] as String?) ?? '');
    if (id is! String || title is! String || at == null) return null;
    return InboxItem(
      id: id,
      title: title,
      body: (raw['body'] as String?) ?? '',
      category: (raw['category'] as String?) ?? '',
      receivedAt: at.toLocal(),
      route: raw['route'] as String?,
      routeArgs: raw['route_args'] as String?,
      read: raw['read'] == true,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'body': body,
    'category': category,
    'at': receivedAt.toUtc().toIso8601String(),
    if (route != null) 'route': route,
    if (routeArgs != null) 'route_args': routeArgs,
    'read': read,
  };
}

/// Where shown notifications are kept: on this phone, newest first.
///
/// Everything is static and goes straight to the phone's preferences, because
/// a push that arrives while the app is closed is drawn by a separate
/// background isolate that shares nothing with the app but its storage. The
/// app reads the list again when it comes back to the front.
class NotificationInbox {
  const NotificationInbox._();

  static const String _key = 'notifications.inbox';

  /// More than anyone scrolls back through; older ones fall off the end.
  static const int capacity = 100;

  /// The same notification raised again this soon is the same notification:
  /// "Update available" is posted on every launch until the app is updated.
  static const Duration repeatWindow = Duration(hours: 12);

  static final StreamController<void> _changes =
      StreamController<void>.broadcast();

  /// Fires when this isolate adds to or changes the inbox.
  static Stream<void> get changes => _changes.stream;

  static List<InboxItem> _decode(String? raw) {
    if (raw == null) return <InboxItem>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <InboxItem>[];
      return <InboxItem>[
        for (final item in decoded) ?InboxItem.tryFromJson(item),
      ];
    } catch (_) {
      return <InboxItem>[];
    }
  }

  static Future<void> _write(
    SharedPreferences prefs,
    List<InboxItem> items,
  ) async {
    await prefs.setString(
      _key,
      jsonEncode(<Object?>[for (final item in items) item.toJson()]),
    );
    if (!_changes.isClosed) _changes.add(null);
  }

  /// The inbox as it is on disk right now, newest first.
  static Future<List<InboxItem>> load() async {
    final prefs = await SharedPreferences.getInstance();
    // Another isolate may have written since this one last looked.
    await prefs.reload();
    return _decode(prefs.getString(_key));
  }

  /// Adds a notification that is being shown. Never throws: keeping a copy
  /// must not stop the notification itself.
  static Future<void> record(PushMessage message, {DateTime? at}) async {
    try {
      final now = at ?? DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final items = _decode(prefs.getString(_key));
      final repeated = items.any(
        (item) =>
            item.category == message.category &&
            item.title == message.title &&
            item.body == message.body &&
            (!item.read || now.difference(item.receivedAt) < repeatWindow),
      );
      if (repeated) return;
      items.insert(
        0,
        InboxItem(
          id: '${now.microsecondsSinceEpoch}',
          title: message.title,
          body: message.body,
          category: message.category,
          receivedAt: now,
          route: message.route,
          routeArgs: message.routeArgs,
        ),
      );
      if (items.length > capacity) items.removeRange(capacity, items.length);
      await _write(prefs, items);
    } catch (error) {
      debugPrint('Inbox: could not keep the notification ($error)');
    }
  }

  /// Marks one notification, or with no [id] all of them, as read.
  static Future<void> markRead({String? id}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final items = _decode(prefs.getString(_key));
    if (!items.any((item) => !item.read && (id == null || item.id == id))) {
      return;
    }
    await _write(prefs, <InboxItem>[
      for (final item in items)
        if (id == null || item.id == id) item.asRead() else item,
    ]);
  }

  /// Empties the inbox, when the account it belongs to signs out.
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    if (!_changes.isClosed) _changes.add(null);
  }
}
