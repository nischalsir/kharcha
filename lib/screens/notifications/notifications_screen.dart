import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_l10n.dart';
import '../../core/router/route_paths.dart';
import '../../core/theme/app_theme.dart';
import '../../models/push_category.dart';
import '../../providers/notification_inbox_provider.dart';
import '../../services/notification_inbox.dart';
import '../../services/nepali_date_service.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/glass_background.dart';
import '../../widgets/common/glass_card.dart';

/// The bell on Home: how many notifications have not been read, and the way
/// to the page that lists them.
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context) {
    final unread = context.select<NotificationInboxProvider, int>(
      (inbox) => inbox.unreadCount,
    );
    return Badge(
      key: const ValueKey<String>('notification-badge'),
      isLabelVisible: unread > 0,
      label: Text(unread > 99 ? '99+' : '$unread'),
      offset: const Offset(-4, 4),
      child: IconButton(
        key: const ValueKey<String>('notification-bell'),
        tooltip: context.t('Notifications', 'सूचनाहरू'),
        onPressed: () =>
            Navigator.of(context).pushNamed(RoutePaths.notifications),
        icon: Icon(
          unread > 0
              ? Icons.notifications_active_rounded
              : Icons.notifications_none_rounded,
          size: 26,
        ),
      ),
    );
  }
}

/// Every notification the app has shown on this phone, newest first. The
/// ones not read yet are highlighted; they count as read once the page has
/// been looked at and left, or at once with "Mark all as read".
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  NotificationInboxProvider? _inbox;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _inbox ??= context.read<NotificationInboxProvider>()..refresh();
  }

  @override
  void dispose() {
    // Seen: leaving the page reads them. After this frame, since the
    // provider's listeners cannot be told while the page is being torn down.
    final inbox = _inbox;
    if (inbox != null) scheduleMicrotask(inbox.markAllRead);
    super.dispose();
  }

  void _open(InboxItem item) {
    final inbox = context.read<NotificationInboxProvider>();
    unawaited(inbox.markRead(item.id));
    final route = item.route;
    // The page it came from, or a route this version no longer has: reading
    // it is all there is to do.
    if (!RoutePaths.isKnown(route) || route == RoutePaths.notifications) return;
    Navigator.of(context).pushNamed(route!, arguments: item.routeArgs);
  }

  @override
  Widget build(BuildContext context) {
    final inbox = context.watch<NotificationInboxProvider>();
    final theme = Theme.of(context);
    final items = inbox.items;
    final unread = inbox.unreadCount;

    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(
            context.t('Notifications', 'सूचनाहरू'),
            style: theme.textTheme.titleLarge,
          ),
          actions: <Widget>[
            if (unread > 0)
              TextButton(
                key: const ValueKey<String>('notifications-read-all'),
                onPressed: inbox.markAllRead,
                child: Text(
                  context.t('Mark all as read', 'सबै पढिएको चिन्ह लगाउनुहोस्'),
                ),
              ),
          ],
        ),
        body: SafeArea(
          child: items.isEmpty
              ? EmptyState(
                  icon: Icons.notifications_none_rounded,
                  title: context.t('No notifications', 'कुनै सूचना छैन'),
                  message: context.t(
                    'Reminders, budget warnings and messages from Flamey '
                        'will be kept here.',
                    'सम्झना, बजेट चेतावनी र Flamey का सन्देश यहाँ राखिन्छन्।',
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) => _NotificationTile(
                    item: items[index],
                    onTap: () => _open(items[index]),
                  ),
                ),
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item, required this.onTap});

  final InboxItem item;
  final VoidCallback onTap;

  static IconData _icon(String category) {
    final channel = PushCategory.byId(category)?.channel;
    return switch (channel) {
      PushChannel.budget => Icons.account_balance_wallet_rounded,
      PushChannel.reminders => Icons.event_repeat_rounded,
      PushChannel.social => Icons.people_alt_rounded,
      PushChannel.insights => Icons.insights_rounded,
      PushChannel.buddy => Icons.local_fire_department_rounded,
      _ =>
        category == 'app_update'
            ? Icons.system_update_rounded
            : Icons.notifications_rounded,
    };
  }

  /// "5 min ago", "3 h ago", then the date.
  String _when(BuildContext context) {
    final age = DateTime.now().difference(item.receivedAt);
    if (age.inMinutes < 1) return context.t('Just now', 'भर्खरै');
    if (age.inHours < 1) {
      return context.t(
        '${age.inMinutes} min ago',
        '${L10n.neNumber(age.inMinutes)} मिनेट अघि',
      );
    }
    if (age.inHours < 24) {
      return context.t(
        '${age.inHours} h ago',
        '${L10n.neNumber(age.inHours)} घण्टा अघि',
      );
    }
    return context.read<NepaliDateService>().format(
      item.receivedAt,
      style: BsFormat.short,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    final unread = !item.read;
    final accent = theme.colorScheme.primary;

    return GlassCard(
      key: ValueKey<String>('notification-${item.id}'),
      strong: unread,
      onTap: onTap,
      // A new one stands out by its tint, its bold title and its dot.
      gradient: unread
          ? LinearGradient(
              colors: <Color>[
                accent.withValues(alpha: 0.10),
                accent.withValues(alpha: 0.10),
              ],
            )
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: (unread ? accent : glass.textSecondary).withValues(
                alpha: 0.14,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _icon(item.category),
              size: 20,
              color: unread ? accent : glass.textSecondary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  item.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: unread ? FontWeight.w800 : FontWeight.w500,
                  ),
                ),
                if (item.body.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      item.body,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: glass.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  _when(context),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: glass.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          if (unread)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 4),
              child: Container(
                key: ValueKey<String>('notification-dot-${item.id}'),
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
