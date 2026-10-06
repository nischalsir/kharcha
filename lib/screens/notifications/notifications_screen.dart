import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_l10n.dart';
import '../../core/router/route_paths.dart';
import '../../core/theme/app_theme.dart';
import '../../models/push_category.dart';
import '../../providers/notification_inbox_provider.dart';
import '../../services/nepali_date_service.dart';
import '../../services/notification_inbox.dart';
import '../../widgets/common/glass_card.dart';
import '../../widgets/common/mornye_chrome.dart';

/// The bell on Home: how many notifications have not been read, and the way
/// to the sheet that lists them.
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
        onPressed: () => showNotificationsSheet(context),
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

/// Opens the notifications over Home, as a sheet rising from the bottom.
///
/// With only a few it comes up to the middle of the screen; with more it
/// grows, but never past the user's name at the top of Home, so the page it
/// was opened from stays in sight. What was new is marked as read once the
/// sheet has been looked at and closed.
Future<void> showNotificationsSheet(BuildContext context) async {
  final inbox = context.read<NotificationInboxProvider>();
  unawaited(inbox.refresh());
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    barrierColor: const Color(0x66000000),
    builder: (_) => const _NotificationsSheet(),
  );
  await inbox.markAllRead();
}

class _NotificationsSheet extends StatelessWidget {
  const _NotificationsSheet();

  /// The room left above the sheet at its tallest: the greeting and the
  /// name on Home.
  static const double _homeHeading = 96;

  void _open(BuildContext context, InboxItem item) {
    final navigator = Navigator.of(context);
    unawaited(context.read<NotificationInboxProvider>().markRead(item.id));
    final route = item.route;
    // No page to go to, or one this version does not have: reading it is all
    // there is to do.
    if (!RoutePaths.isKnown(route)) return;
    navigator.pop();
    navigator.pushNamed(route!, arguments: item.routeArgs);
  }

  @override
  Widget build(BuildContext context) {
    final inbox = context.watch<NotificationInboxProvider>();
    final theme = Theme.of(context);
    final glass = context.glass;
    final media = MediaQuery.of(context);
    final dark = theme.brightness == Brightness.dark;

    final fresh = <InboxItem>[
      for (final item in inbox.items)
        if (!item.read) item,
    ];
    final earlier = <InboxItem>[
      for (final item in inbox.items)
        if (item.read) item,
    ];

    // useSafeArea has already taken the status bar off the height on offer.
    final available = media.size.height - media.padding.top;
    final half = media.size.height * 0.5;
    final tallest = math.max(half, available - _homeHeading);

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: glass.textTertiary,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      ),
    );

    Widget tile(InboxItem item) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _NotificationTile(item: item, onTap: () => _open(context, item)),
    );

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: half, maxHeight: tallest),
      child: MornyeGlass.navigation(
        blurEnabled: true,
        radius: 32,
        child: Material(
          color: dark ? Colors.black : const Color(0xfff2f2f7),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Center(
                    child: Container(
                      width: 36,
                      height: 5,
                      decoration: BoxDecoration(
                        color: dark
                            ? Colors.white.withValues(alpha: 0.2)
                            : Colors.black.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          context.t('Notifications', 'सूचनाहरू'),
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (fresh.isNotEmpty)
                        TextButton(
                          key: const ValueKey<String>('notifications-read-all'),
                          onPressed: inbox.markAllRead,
                          child: Text(
                            context.t(
                              'Mark all as read',
                              'सबै पढिएको चिन्ह लगाउनुहोस्',
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (inbox.items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Column(
                        children: <Widget>[
                          Icon(
                            Icons.notifications_none_rounded,
                            size: 44,
                            color: glass.textTertiary,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            context.t('No notifications', 'कुनै सूचना छैन'),
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            context.t(
                              'Reminders, budget warnings and messages from '
                                  'Flamey will be kept here.',
                              'सम्झना, बजेट चेतावनी र Flamey का सन्देश यहाँ '
                                  'राखिन्छन्।',
                            ),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: glass.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Flexible(
                      child: ListView(
                        key: const ValueKey<String>('notifications-list'),
                        shrinkWrap: true,
                        padding: const EdgeInsets.only(bottom: 8),
                        children: <Widget>[
                          if (fresh.isNotEmpty) ...<Widget>[
                            heading(context.t('New', 'नयाँ')),
                            for (final item in fresh) tile(item),
                          ],
                          // A line between what is new and what was already
                          // read.
                          if (fresh.isNotEmpty && earlier.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(4, 2, 4, 12),
                              child: Divider(
                                key: const ValueKey<String>(
                                  'notifications-divider',
                                ),
                                height: 1,
                                thickness: 1,
                                color: glass.border,
                              ),
                            ),
                          if (earlier.isNotEmpty) ...<Widget>[
                            heading(context.t('Earlier', 'पहिलेका')),
                            for (final item in earlier) tile(item),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
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
                    fontWeight: unread ? FontWeight.w600 : FontWeight.w500,
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
