import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../models/sync_models.dart';
import '../../providers/auth_provider.dart';
import '../../screens/auth/guest_upgrade_screen.dart';
import '../../services/sync_service.dart';
import 'glass_card.dart';
import 'primary_button.dart';

/// What is said to the person about where their data is, in their words
/// rather than the sync service's.
enum SyncDisplay {
  /// Guest mode: nothing leaves this phone.
  localOnly,
  syncing,

  /// Saved here, not yet on the server.
  pending,
  offline,
  failed,
  synced;

  /// Works out what to say from the sync service's state.
  static SyncDisplay of(SyncService sync, {required bool guest}) {
    if (guest || sync.isLocalOnly) return SyncDisplay.localOnly;
    switch (sync.status) {
      case SyncStatus.syncing:
        return SyncDisplay.syncing;
      case SyncStatus.offline:
        return SyncDisplay.offline;
      case SyncStatus.failed:
        return SyncDisplay.failed;
      case SyncStatus.synced || SyncStatus.loadingFromCache:
        return sync.waitingCount > 0 ? SyncDisplay.pending : SyncDisplay.synced;
    }
  }

  IconData get icon => switch (this) {
    SyncDisplay.localOnly => Icons.smartphone_rounded,
    SyncDisplay.syncing => Icons.sync_rounded,
    SyncDisplay.pending => Icons.cloud_upload_outlined,
    SyncDisplay.offline => Icons.cloud_off_rounded,
    SyncDisplay.failed => Icons.sync_problem_rounded,
    SyncDisplay.synced => Icons.cloud_done_rounded,
  };

  Color color(BuildContext context) {
    final glass = context.glass;
    return switch (this) {
      SyncDisplay.failed => glass.danger,
      SyncDisplay.offline || SyncDisplay.pending => glass.warning,
      SyncDisplay.synced => glass.success,
      SyncDisplay.syncing => Theme.of(context).colorScheme.primary,
      SyncDisplay.localOnly => glass.textSecondary,
    };
  }

  /// A few words, for a row.
  String short(BuildContext context) => switch (this) {
    SyncDisplay.localOnly => context.t('On this phone', 'यही फोनमा'),
    SyncDisplay.syncing => context.t('Syncing', 'सिङ्क हुँदैछ'),
    SyncDisplay.pending => context.t('Changes pending', 'परिवर्तन बाँकी'),
    SyncDisplay.offline => context.t('Offline', 'अफलाइन'),
    SyncDisplay.failed => context.t('Sync failed', 'सिङ्क असफल'),
    SyncDisplay.synced => context.t('Synced', 'सिङ्क भयो'),
  };

  /// The whole sentence.
  String long(BuildContext context, {int waiting = 0}) => switch (this) {
    SyncDisplay.localOnly => context.t(
      'Saved on this phone only',
      'यही फोनमा मात्र सुरक्षित',
    ),
    SyncDisplay.syncing => context.t(
      'Syncing your data',
      'तपाईंको डाटा सिङ्क हुँदैछ',
    ),
    SyncDisplay.pending => context.t(
      waiting == 1
          ? '1 change waiting to sync'
          : '$waiting changes waiting to sync',
      '${L10n.neNumber(waiting)} परिवर्तन सिङ्क हुन बाँकी',
    ),
    SyncDisplay.offline => context.t(
      'Offline — changes will sync later',
      'अफलाइन — परिवर्तन पछि सिङ्क हुनेछ',
    ),
    SyncDisplay.failed => context.t(
      'Sync failed. Your changes are safe on this phone.',
      'सिङ्क असफल। तपाईंका परिवर्तन यही फोनमा सुरक्षित छन्।',
    ),
    SyncDisplay.synced => context.t('Synced', 'सिङ्क भयो'),
  };
}

/// A small mark in a page's heading that only appears when there is
/// something to know: syncing, changes waiting, offline, a failed sync, or
/// guest mode. When everything is synced it takes no room at all.
class SyncStatusButton extends StatelessWidget {
  const SyncStatusButton({super.key});

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncService>();
    final guest = context.select<AuthProvider, bool>((auth) => auth.isGuest);
    final display = SyncDisplay.of(sync, guest: guest);
    if (display == SyncDisplay.synced) return const SizedBox.shrink();
    return IconButton(
      key: const ValueKey<String>('sync-status'),
      tooltip: display.long(context, waiting: sync.waitingCount),
      visualDensity: VisualDensity.compact,
      onPressed: () => showSyncStatusSheet(context),
      icon: Icon(display.icon, size: 22, color: display.color(context)),
    );
  }
}

/// How long ago the last sync was, in a few words.
String _ago(BuildContext context, DateTime at) {
  final minutes = DateTime.now().difference(at).inMinutes;
  if (minutes < 1) return context.t('just now', 'भर्खरै');
  if (minutes < 60) {
    return context.t('$minutes min ago', '${L10n.neNumber(minutes)} मिनेट अघि');
  }
  final hours = minutes ~/ 60;
  if (hours < 24) {
    return context.t(
      hours == 1 ? '1 hour ago' : '$hours hours ago',
      '${L10n.neNumber(hours)} घण्टा अघि',
    );
  }
  final days = hours ~/ 24;
  return context.t(
    days == 1 ? 'yesterday' : '$days days ago',
    days == 1 ? 'हिजो' : '${L10n.neNumber(days)} दिन अघि',
  );
}

/// Says where the data is, from the bottom of the screen, with the one
/// thing that can be done about it: sync now, or (for a guest) create an
/// account.
Future<void> showSyncStatusSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    elevation: 0,
    builder: (_) => const _SyncStatusSheet(),
  );
}

class _SyncStatusSheet extends StatelessWidget {
  const _SyncStatusSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    final sync = context.watch<SyncService>();
    final guest = context.select<AuthProvider, bool>((auth) => auth.isGuest);
    final display = SyncDisplay.of(sync, guest: guest);
    final last = sync.lastSyncAt;

    final detail = switch (display) {
      SyncDisplay.localOnly => context.t(
        'You are exploring as a guest. Create an account to back up what '
            'you add and use it on your other devices.',
        'तपाईं पाहुनाको रूपमा हेर्दै हुनुहुन्छ। थपेका कुरा जोगाउन र अरू '
            'उपकरणमा प्रयोग गर्न खाता बनाउनुहोस्।',
      ),
      SyncDisplay.offline => context.t(
        'Everything you add is saved on this phone and sent as soon as you '
            'are back online.',
        'तपाईंले थपेका सबै कुरा यही फोनमा सुरक्षित छन् र अनलाइन हुनासाथ '
            'पठाइन्छन्।',
      ),
      SyncDisplay.failed => context.t(
        'It will be tried again on its own. You can also try now.',
        'यो आफैं फेरि प्रयास गरिनेछ। अहिले पनि प्रयास गर्न सक्नुहुन्छ।',
      ),
      _ =>
        last == null
            ? context.t(
                'Your data is kept in step across your devices.',
                'तपाईंको डाटा सबै उपकरणमा एकनास राखिन्छ।',
              )
            : context.t(
                'Last synced ${_ago(context, last)}.',
                'पछिल्लो सिङ्क: ${_ago(context, last)}।',
              ),
    };

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: GlassCard(
          radius: 28,
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(display.icon, color: display.color(context)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      display.long(context, waiting: sync.waitingCount),
                      key: const ValueKey<String>('sync-status-text'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                detail,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: glass.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              if (display == SyncDisplay.localOnly)
                PrimaryButton(
                  label: context.t(
                    'Create account or sign in',
                    'खाता बनाउनुहोस् वा साइन इन गर्नुहोस्',
                  ),
                  icon: Icons.arrow_forward_rounded,
                  onPressed: () {
                    final navigator = Navigator.of(context);
                    navigator.pop();
                    navigator.push(
                      MaterialPageRoute<void>(
                        builder: (_) => const GuestUpgradeScreen(),
                      ),
                    );
                  },
                )
              else
                PrimaryButton(
                  key: const ValueKey<String>('sync-now'),
                  label: context.t('Sync now', 'अहिले सिङ्क गर्नुहोस्'),
                  icon: Icons.sync_rounded,
                  isLoading: display == SyncDisplay.syncing,
                  onPressed: () => display == SyncDisplay.failed
                      ? sync.retryFailed()
                      : sync.refresh(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
