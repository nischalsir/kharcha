import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_l10n.dart';
import '../../providers/push_provider.dart';
import '../../services/app_permissions.dart';
import '../../services/push_notification_service.dart';
import '../../widgets/common/form_helpers.dart';
import '../../widgets/common/setting_row.dart';

/// Settings > App Permissions: what Kharcha may use on this phone, each as
/// a row with a switch that shows whether it is allowed.
///
/// Opening the page asks for nothing. Switching one on asks Android for it
/// (or, where Android will no longer ask, opens the app's page in the
/// phone's settings). Android does not let an app give a permission back, so
/// switching one off opens that page too. The states are read again whenever
/// the app comes back to the front, since they can be changed there.
///
/// Rows only, with a line between them: the card around them is the
/// Settings page's, shared with the notification switches.
class AppPermissionRows extends StatefulWidget {
  const AppPermissionRows({super.key, this.location = const LocationAccess()});

  final LocationAccess location;

  @override
  State<AppPermissionRows> createState() => _AppPermissionRowsState();
}

class _AppPermissionRowsState extends State<AppPermissionRows>
    with WidgetsBindingObserver {
  AccessState _location = AccessState.notAllowed;

  /// The permission a request or a trip to settings is in progress for.
  String? _busy;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the phone's settings, where any of these may have changed.
    if (state != AppLifecycleState.resumed) return;
    _refresh();
    // The notification permission is the push provider's to read again.
    final push = context.read<PushProvider>();
    if (push.isReady) push.initialize();
  }

  Future<void> _refresh() async {
    final location = await widget.location.status();
    if (!mounted) return;
    setState(() => _location = location);
  }

  Future<void> _run(String name, Future<void> Function() action) async {
    if (_busy != null) return;
    setState(() => _busy = name);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _couldNotOpen() => showMessage(
    context,
    context.t(
      'Could not open the phone’s settings.',
      'फोनको सेटिङ खोल्न सकिएन।',
    ),
  );

  Future<void> _notifications(PushProvider push, AccessState state) =>
      _run('notifications', () async {
        if (state == AccessState.notAllowed) {
          await push.enable();
          return;
        }
        // Allowed (to turn off) or blocked (to turn on): both are done on
        // the phone's settings page, and read again on the way back.
        if (!await push.openSystemSettings() && mounted) _couldNotOpen();
      });

  Future<void> _locationAction() => _run('location', () async {
    if (_location == AccessState.notAllowed) {
      final next = await widget.location.request();
      if (mounted) setState(() => _location = next);
      return;
    }
    if (!await widget.location.openSettings() && mounted) _couldNotOpen();
  });

  /// What a row says under its name: what the permission is for, and, where
  /// Android will not ask any more, where to go instead.
  String _about(AccessState? state, String purpose) => switch (state) {
    null => context.t(
      'Not available on this build.',
      'यो संस्करणमा उपलब्ध छैन।',
    ),
    AccessState.blocked => context.t(
      '$purpose Blocked: switch it on to open the phone’s settings.',
      '$purpose रोकिएको छ: फोनको सेटिङ खोल्न यसलाई खोल्नुहोस्।',
    ),
    _ => purpose,
  };

  @override
  Widget build(BuildContext context) {
    final push = context.watch<PushProvider>();
    final AccessState? notifications = !push.isReady
        ? null
        : switch (push.permission) {
            PushPermission.authorized ||
            PushPermission.provisional => AccessState.allowed,
            PushPermission.denied => AccessState.blocked,
            _ => AccessState.notAllowed,
          };

    return Column(
      key: const ValueKey<String>('app-permissions'),
      children: <Widget>[
        SettingSwitchRow(
          key: const ValueKey<String>('permission-notifications'),
          switchKey: const ValueKey<String>('permission-notifications-switch'),
          icon: Icons.notifications_active_rounded,
          color: const Color(0xFF30D158),
          title: context.t('Notifications', 'सूचनाहरू'),
          subtitle: _about(
            notifications,
            context.t(
              'Budget warnings, reminders and Flamey’s tips.',
              'बजेट चेतावनी, सम्झना र Flamey का सुझाव।',
            ),
          ),
          value: notifications == AccessState.allowed,
          onChanged: notifications == null || _busy != null
              ? null
              : (_) => _notifications(push, notifications),
        ),
        const Divider(height: 1),
        SettingSwitchRow(
          key: const ValueKey<String>('permission-location'),
          switchKey: const ValueKey<String>('permission-location-switch'),
          icon: Icons.location_on_rounded,
          color: const Color(0xFF0A84FF),
          title: context.t('Location', 'स्थान'),
          subtitle: _about(
            _location,
            context.t(
              'The weather for your town on the Calendar. Approximate only, '
                  'never saved.',
              'पात्रोमा तपाईंको शहरको मौसम। अनुमानित मात्र, कहिल्यै सुरक्षित '
                  'गरिँदैन।',
            ),
          ),
          value: _location == AccessState.allowed,
          onChanged: _busy != null ? null : (_) => _locationAction(),
        ),
      ],
    );
  }
}
