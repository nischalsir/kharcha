import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/notification_inbox.dart';

/// The notifications the app has shown, for the bell on Home and the
/// Notifications page.
class NotificationInboxProvider extends ChangeNotifier {
  NotificationInboxProvider() {
    _sub = NotificationInbox.changes.listen((_) => refresh());
    refresh();
  }

  StreamSubscription<void>? _sub;
  List<InboxItem> _items = <InboxItem>[];
  bool _disposed = false;

  /// Newest first.
  List<InboxItem> get items => _items;

  int get unreadCount => _items.where((item) => !item.read).length;

  /// Reads the inbox again. Called when the app comes back to the front,
  /// since a push that arrived while it was closed was kept by another
  /// isolate.
  Future<void> refresh() async {
    try {
      final items = await NotificationInbox.load();
      if (_disposed) return;
      _items = items;
      notifyListeners();
    } catch (error) {
      debugPrint('Inbox: could not be read ($error)');
    }
  }

  Future<void> markRead(String id) => NotificationInbox.markRead(id: id);

  Future<void> markAllRead() => NotificationInbox.markRead();

  Future<void> clear() => NotificationInbox.clear();

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    super.dispose();
  }
}
