import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/common/form_helpers.dart';
import '../../widgets/common/glass_background.dart';
import '../../widgets/common/glass_card.dart';
import 'version_screen.dart';

/// Help & support: direct contact details plus a short FAQ.
class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  static const String contactEmail = 'nischalpandey.dev@gmail.com';
  static const String contactPhone = '9865060952';

  Future<void> _copy(BuildContext context, String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (context.mounted) showMessage(context, '$label copied');
  }

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
          title: Text('Help & Support', style: theme.textTheme.titleLarge),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 48),
            children: <Widget>[
              Text(
                'We are here to help',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Reach out with a question, a bug report or feedback — '
                'tap a card to copy the details.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: glass.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              GlassCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: <Widget>[
                    _ContactTile(
                      icon: Icons.mail_outline_rounded,
                      color: const Color(0xFF0A84FF),
                      label: 'Email',
                      value: contactEmail,
                      onTap: () => _copy(context, 'Email', contactEmail),
                    ),
                    const Divider(height: 1),
                    _ContactTile(
                      icon: Icons.phone_outlined,
                      color: const Color(0xFF30D158),
                      label: 'Phone',
                      value: contactPhone,
                      onTap: () => _copy(context, 'Phone', contactPhone),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Frequently asked',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              GlassCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: const <Widget>[
                    _Faq(
                      question: 'Does Kharcha work offline?',
                      answer:
                          'Yes. Everything is saved on your device first, so '
                          'you can record expenses with no internet. It syncs '
                          'automatically once you are back online.',
                    ),
                    Divider(height: 1),
                    _Faq(
                      question: 'How do I back up my data?',
                      answer:
                          'Turn on Supabase Sync in Settings. Your records are '
                          'backed up to your own private account and restored '
                          'when you sign in on another device.',
                    ),
                    Divider(height: 1),
                    _Faq(
                      question: 'How does the AI insight work?',
                      answer:
                          'A secure server builds a small summary of your own '
                          'spending and asks the AI for a suggestion. Your raw '
                          'transactions never leave your account.',
                    ),
                    Divider(height: 1),
                    _Faq(
                      question: 'How do I change my name or photo?',
                      answer:
                          'Go to Settings → Edit Profile to set your name, '
                          'gender and birth date, or tap the picture to upload '
                          'a new one.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Kharcha v${VersionScreen.appVersion}',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: glass.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
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
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: glass.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.copy_rounded, size: 18, color: glass.textTertiary),
          ],
        ),
      ),
    );
  }
}

class _Faq extends StatelessWidget {
  const _Faq({required this.question, required this.answer});

  final String question;
  final String answer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        title: Text(
          question,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        children: <Widget>[
          Text(
            answer,
            style: theme.textTheme.bodySmall?.copyWith(
              color: glass.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
