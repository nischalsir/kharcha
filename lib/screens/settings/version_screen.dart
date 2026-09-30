import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/common/form_helpers.dart';
import '../../widgets/common/glass_background.dart';
import '../../widgets/common/glass_card.dart';

/// Version / build information for the app.
class VersionScreen extends StatelessWidget {
  const VersionScreen({super.key});

  /// Keep in sync with pubspec.yaml (`version: 1.0.0+2`).
  static const String appVersion = '1.0.0';
  static const String buildNumber = '2';
  static const String applicationId = 'com.nischalpandey.kharcha';

  static const String developerName = 'Nischal Pandey';
  static const String instagramHandle = '@nischalsir';
  static const String instagramUrl = 'https://instagram.com/nischalsir';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;

    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(
              Icons.arrow_back_rounded,
              color: theme.colorScheme.onSurface,
            ),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text('Version', style: theme.textTheme.titleLarge),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 48),
            children: <Widget>[
              GlassCard(
                strong: true,
                glow: true,
                child: Column(
                  children: <Widget>[
                    Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: <Color>[
                            theme.colorScheme.primary,
                            theme.colorScheme.secondary,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: const Icon(
                        Icons.account_balance_wallet_rounded,
                        color: Colors.white,
                        size: 38,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Kharcha',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'v$appVersion (build $buildNumber)',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: glass.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              GlassCard(
                child: Column(
                  children: <Widget>[
                    _InfoRow(label: 'Version', value: appVersion),
                    const Divider(height: 1),
                    _InfoRow(label: 'Build', value: buildNumber),
                    const Divider(height: 1),
                    _InfoRow(label: 'Application ID', value: applicationId),
                    const Divider(height: 1),
                    _InfoRow(label: 'Built with', value: 'Flutter'),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Developer',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              GlassCard(
                child: Column(
                  children: <Widget>[
                    _InfoRow(label: 'Name', value: developerName),
                    const Divider(height: 1),
                    _InfoRow(
                      label: 'Instagram',
                      value: instagramHandle,
                      icon: Icons.alternate_email_rounded,
                      onTap: () => _copyInstagram(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'About',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Kharcha is a Nepali-first expense tracker built around the Bikram Sambat '
                'calendar. It works offline, syncs securely via Supabase, and includes '
                'an AI flame mascot that reacts to your spending. Push notifications '
                'cover budget alerts, daily AI greetings (morning/night), and transaction '
                'reminders. All data is encrypted at rest; secrets live only in server-side '
                'Edge Functions.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: glass.textSecondary,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _copyInstagram(BuildContext context) async {
    await Clipboard.setData(const ClipboardData(text: instagramHandle));
    if (context.mounted) {
      showMessage(context, 'Copied $instagramHandle to clipboard.');
    }
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.icon,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(label, style: theme.textTheme.bodyMedium),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (onTap != null) ...<Widget>[
            const SizedBox(width: 6),
            Icon(
              Icons.copy_rounded,
              size: 14,
              color: theme.colorScheme.primary.withValues(alpha: 0.7),
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }
}
