import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/push_provider.dart';
import '../../services/push_notification_service.dart';
import '../common/glass_card.dart';

/// Shows the push notification status and lets the user enable/disable it.
class PushNotificationCard extends StatelessWidget {
  const PushNotificationCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    final push = context.watch<PushProvider>();

    if (!push.isReady) {
      return GlassCard(
        child: Row(
          children: <Widget>[
            Icon(Icons.notifications_off_rounded, color: glass.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                context.t(
                  'Notifications unavailable on this build',
                  'यस बिल्डमा सूचना उपलब्ध छैन',
                ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: glass.textSecondary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final canReceive = push.canReceive;
    final permission = push.permission;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                canReceive ? Icons.notifications_active_rounded : Icons.notifications_off_rounded,
                color: canReceive ? glass.success : glass.textSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  context.t('Push Notifications', 'पुश सूचना'),
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Switch(
                value: canReceive,
                onChanged: (_) async {
                  if (!canReceive) {
                    await push.enable();
                  } else {
                    await push.openSystemSettings();
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            canReceive
                ? context.t(
                    'You will receive transaction alerts, budget warnings, and daily AI greetings.',
                    'तपाईंले लेनदेन सतर्कता, बजेट चेतावनी, र दैनिक AI अभिवादन प्राप्त गर्नुहुनेछ।',
                  )
                : _permissionMessage(context, permission),
            style: theme.textTheme.bodySmall?.copyWith(
              color: glass.textSecondary,
              height: 1.4,
            ),
          ),
          if (push.error != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              'Error: ${push.error}',
              style: theme.textTheme.bodySmall?.copyWith(color: glass.danger),
            ),
          ],
        ],
      ),
    );
  }

  String _permissionMessage(BuildContext context, PushPermission permission) {
    switch (permission) {
      case PushPermission.denied:
        return context.t(
          'Permission denied. Enable in system settings to receive notifications.',
          'अनुमति अस्वीकार भयो। सूचना प्राप्त गर्न सिस्टम सेटिङ्समा सक्षम गर्नुहोस्।',
        );
      case PushPermission.provisional:
        return context.t(
          'Provisional permission. Notifications may be limited.',
          'अस्थायी अनुमति। सूचना सिमित हुन सक्छ।',
        );
      case PushPermission.notDetermined:
        return context.t(
          'Permission not requested yet. Tap to enable notifications.',
          'अनुमति मागिएको छैन। सूचना सक्षम गर्न ट्याप गर्नुहोस्।',
        );
      case PushPermission.unknown:
        return context.t(
          'Checking notification permission…',
          'सूचना अनुमति जाँचदै…',
        );
      case PushPermission.authorized:
        return context.t(
          'Enabled. You will receive notifications.',
          'सक्षम। तपाईंले सूचना प्राप्त गर्नुहुनेछ।',
        );
    }
  }
}