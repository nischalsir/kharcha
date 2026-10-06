import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/ai_insight_provider.dart';
import '../../providers/auth_provider.dart';
import '../common/glass_card.dart';

/// Celebratory AI birthday wish, shown only on the user's birthday.
class AiBirthdayBanner extends StatelessWidget {
  const AiBirthdayBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final birthDate = auth.profileBirthDate;
    if (birthDate == null) return const SizedBox.shrink();

    final now = DateTime.now();
    if (birthDate.month != now.month || birthDate.day != now.day) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final name = context.watch<AiInsightProvider>().userName ?? auth.profileName;

    return GlassCard(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[Color(0xFFF59E0B), Color(0xFFEC4899)],
      ),
      child: Row(
        children: <Widget>[
          const Text('🎂', style: TextStyle(fontSize: 36)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  name == null ? 'Happy Birthday!' : 'Happy Birthday, $name!',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Kharcha wishes you a wonderful day. Treat yourself — '
                  'you have earned it.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.92),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
