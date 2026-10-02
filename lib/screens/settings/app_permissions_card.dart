import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/push_provider.dart';
import '../../services/app_permissions.dart';
import '../../services/push_notification_service.dart';
import '../../services/sms_service.dart';
import '../../widgets/common/form_helpers.dart';
import '../../widgets/common/glass_card.dart';

/// Settings > App Permissions: what Kharcha may use on this phone, whether
/// it is allowed to right now, and the way to change that.
///
/// Opening this card asks for nothing. A permission is only requested when
/// its Allow button is pressed (or by the feature that needs it, when that
/// feature is used). The states are read again whenever the app comes back
/// to the front, since they can be changed in the phone's settings.
class AppPermissionsCard extends StatefulWidget {
  const AppPermissionsCard({
    super.key,
    this.location = const LocationAccess(),
    this.sms,
  });

  final LocationAccess location;

  /// Replaced in tests.
  final SmsService? sms;

  @override
  State<AppPermissionsCard> createState() => _AppPermissionsCardState();
}

class _AppPermissionsCardState extends State<AppPermissionsCard>
    with WidgetsBindingObserver {
  late final SmsService _sms = widget.sms ?? SmsService();

  AccessState _location = AccessState.notAllowed;
  AccessState _smsState = AccessState.notAllowed;

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
    final sms = await _sms.hasPermission();
    if (!mounted) return;
    setState(() {
      _location = location;
      // Once Android has refused to ask, only the settings page can change
      // it; a plain "not allowed" would offer a button that does nothing.
      _smsState = sms
          ? AccessState.allowed
          : _smsState == AccessState.blocked
          ? AccessState.blocked
          : AccessState.notAllowed;
    });
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

  Future<void> _smsAction() => _run('sms', () async {
    if (_smsState == AccessState.notAllowed) {
      final granted = await _sms.requestPermission();
      if (!mounted) return;
      // Refused, or Android would not show its prompt (it holds this
      // permission back from apps installed outside the Play Store until
      // "Allow restricted settings" is chosen on the settings page).
      setState(
        () => _smsState = granted ? AccessState.allowed : AccessState.blocked,
      );
      return;
    }
    if (!await _sms.openAppSettings() && mounted) _couldNotOpen();
  });

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

    return GlassCard(
      key: const ValueKey<String>('app-permissions'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: <Widget>[
          _PermissionRow(
            rowKey: 'permission-notifications',
            icon: Icons.notifications_active_rounded,
            color: const Color(0xFF30D158),
            name: context.t('Notifications', 'सूचनाहरू'),
            why: context.t(
              'Budget warnings, reminders and Flamey’s tips.',
              'बजेट चेतावनी, सम्झना र Flamey का सुझाव।',
            ),
            state: notifications,
            busy: _busy == 'notifications',
            onAction: notifications == null
                ? null
                : () => _notifications(push, notifications),
          ),
          const Divider(height: 1),
          _PermissionRow(
            rowKey: 'permission-location',
            icon: Icons.location_on_rounded,
            color: const Color(0xFF0A84FF),
            name: context.t('Location', 'स्थान'),
            why: context.t(
              'The weather for your town on the Calendar. Approximate '
                  'only, and never saved.',
              'पात्रोमा तपाईंको शहरको मौसम। अनुमानित मात्र, र कहिल्यै '
                  'सुरक्षित गरिँदैन।',
            ),
            state: _location,
            busy: _busy == 'location',
            onAction: _locationAction,
          ),
          const Divider(height: 1),
          _PermissionRow(
            rowKey: 'permission-sms',
            icon: Icons.sms_rounded,
            color: const Color(0xFFFF9F0A),
            name: 'SMS',
            why: context.t(
              'Reads bank and wallet payment messages so you can import '
                  'them. Read on this phone, only when you start a scan.',
              'बैंक र वालेटका भुक्तानी सन्देश पढेर आयात गर्न। यही फोनमा, '
                  'तपाईंले स्क्यान सुरु गर्दा मात्र पढिन्छ।',
            ),
            state: _smsState,
            busy: _busy == 'sms',
            onAction: _smsAction,
          ),
        ],
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.rowKey,
    required this.icon,
    required this.color,
    required this.name,
    required this.why,
    required this.state,
    required this.busy,
    required this.onAction,
  });

  final String rowKey;
  final IconData icon;
  final Color color;
  final String name;

  /// What the app uses it for, in a line.
  final String why;

  /// Null when the permission does not exist on this build.
  final AccessState? state;
  final bool busy;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    final state = this.state;
    final allowed = state == AccessState.allowed;
    final statusColor = state == null
        ? glass.textTertiary
        : allowed
        ? glass.success
        : glass.warning;
    final status = state == null
        ? context.t('Not available', 'उपलब्ध छैन')
        : allowed
        ? context.t('Allowed', 'अनुमति छ')
        : context.t('Not allowed', 'अनुमति छैन');
    final action = switch (state) {
      null => null,
      AccessState.allowed => context.t('Manage', 'व्यवस्थापन'),
      AccessState.notAllowed => context.t('Allow', 'अनुमति दिनुहोस्'),
      AccessState.blocked => context.t('Open settings', 'सेटिङ खोल्नुहोस्'),
    };

    return Padding(
      key: ValueKey<String>(rowKey),
      padding: const EdgeInsets.fromLTRB(16, 12, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(name, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      why,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: glass.textSecondary,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Under the words, on a line of its own: the state at the start,
          // the way to change it at the end. It fits a narrow phone and a
          // long translation alike.
          Padding(
            padding: const EdgeInsets.only(left: 54),
            child: Row(
              children: <Widget>[
                Icon(
                  allowed
                      ? Icons.check_circle_rounded
                      : Icons.remove_circle_outline_rounded,
                  size: 16,
                  color: statusColor,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    status,
                    key: ValueKey<String>('$rowKey-state'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (action != null)
                  TextButton(
                    key: ValueKey<String>('$rowKey-action'),
                    onPressed: busy ? null : onAction,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    child: Text(action),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
