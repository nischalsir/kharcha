import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../models/financial_summary.dart';
import '../../providers/auth_provider.dart';
import '../../services/app_lock.dart';
import 'flame_mascot.dart';
import 'form_helpers.dart';
import 'glass_background.dart';
import 'primary_button.dart';
import 'setting_row.dart';

String _unlockReason(BuildContext context) =>
    context.t('Unlock Kharcha', 'खर्चा खोल्नुहोस्');

/// Covers the whole app, every page and dialog, while the app lock is on
/// and has not been passed. Sits above the navigator for that reason: a
/// page left open when the phone was put down must not show through.
class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final lock = context.read<AppLockController>();
    if (state == AppLifecycleState.resumed) {
      lock.onShown();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      lock.onHidden();
    }
  }

  @override
  Widget build(BuildContext context) {
    final lock = context.watch<AppLockController>();
    // Only someone's data needs guarding; the sign-in pages are open to all.
    final inside = context.select<AuthProvider, bool>(
      (auth) => auth.isAuthenticated,
    );
    final covered = inside && (lock.locked || !lock.isReady);

    return Stack(
      children: <Widget>[
        // Still there underneath, so nothing is lost by locking; out of
        // reach of touch and of a screen reader while it is covered.
        ExcludeSemantics(
          excluding: covered,
          child: IgnorePointer(
            key: const ValueKey<String>('app-lock-cover'),
            ignoring: covered,
            child: widget.child,
          ),
        ),
        if (covered)
          Positioned.fill(
            child: lock.isReady
                ? const _LockScreen()
                : const GlassBackground(child: SizedBox.expand()),
          ),
      ],
    );
  }
}

class _LockScreen extends StatefulWidget {
  const _LockScreen();

  @override
  State<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<_LockScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Asked for straight away, so opening the app is one touch.
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    if (_busy || !mounted) return;
    setState(() => _busy = true);
    await context.read<AppLockController>().unlock(
      reason: _unlockReason(context),
    );
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    return GlassBackground(
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const FlameMascot(
                    face: MoodFace.sleepy,
                    energy: 0.7,
                    size: 84,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    context.t('Kharcha is locked', 'खर्चा लक छ'),
                    key: const ValueKey<String>('app-lock-title'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    context.t(
                      'Use your fingerprint, face or the phone’s PIN to '
                          'open it.',
                      'खोल्न फिंगरप्रिन्ट, अनुहार वा फोनको PIN प्रयोग गर्नुहोस्।',
                    ),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: glass.textSecondary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 24),
                  PrimaryButton(
                    key: const ValueKey<String>('app-lock-unlock'),
                    label: context.t('Unlock', 'खोल्नुहोस्'),
                    icon: Icons.lock_open_rounded,
                    expanded: false,
                    isLoading: _busy,
                    onPressed: _unlock,
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

/// The App lock switch in Settings: a row for the Security card.
class AppLockRow extends StatefulWidget {
  const AppLockRow({super.key});

  @override
  State<AppLockRow> createState() => _AppLockRowState();
}

class _AppLockRowState extends State<AppLockRow> {
  /// Whether the phone has a screen lock; null until it has answered.
  bool? _available;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    context.read<AppLockController>().isAvailable().then((available) {
      if (mounted) setState(() => _available = available);
    });
  }

  Future<void> _toggle(bool value) async {
    if (_busy) return;
    setState(() => _busy = true);
    final lock = context.read<AppLockController>();
    final reason = value
        ? context.t('Turn on app lock', 'एप लक खोल्नुहोस्')
        : context.t('Turn off app lock', 'एप लक बन्द गर्नुहोस्');
    final done = await lock.setEnabled(value, reason: reason);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!done) return;
    showMessage(
      context,
      value
          ? context.t(
              'App lock is on. Kharcha will ask each time it is opened.',
              'एप लक खुला छ। खर्चा खोल्दा हरेक पटक सोधिनेछ।',
            )
          : context.t('App lock is off.', 'एप लक बन्द छ।'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lock = context.watch<AppLockController>();
    final available = _available;
    final usable = available ?? false;

    return SettingSwitchRow(
      key: const ValueKey<String>('app-lock-row'),
      switchKey: const ValueKey<String>('app-lock-switch'),
      icon: Icons.lock_rounded,
      color: const Color(0xFFFF453A),
      title: context.t('App lock', 'एप लक'),
      subtitle: available == false
          ? context.t(
              'Set a screen lock on this phone first.',
              'पहिले यो फोनमा स्क्रिन लक राख्नुहोस्।',
            )
          : context.t(
              'Ask for fingerprint, face or the phone’s PIN each time '
                  'Kharcha is opened',
              'खर्चा खोल्दा हरेक पटक फिंगरप्रिन्ट, अनुहार वा फोनको PIN '
                  'माग्नुहोस्',
            ),
      value: lock.enabled,
      // With no screen lock on the phone there is nothing to ask for.
      onChanged: _busy || (!usable && !lock.enabled) ? null : _toggle,
    );
  }
}
