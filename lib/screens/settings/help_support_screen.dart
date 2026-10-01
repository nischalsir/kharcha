import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n/app_l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/common/form_helpers.dart';
import '../../widgets/common/glass_background.dart';
import '../../widgets/common/glass_card.dart';

/// Help & support: ways to reach the developer, plus a short FAQ.
class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  static const String contactEmail = 'nischalpandey.dev@gmail.com';
  static const String contactPhone = '9865060952';
  static const String bugReportUrl =
      'https://github.com/nischalsir/kharcha/issues/new/choose';

  /// Opens [uri] in the matching app; if nothing can handle it (no mail app,
  /// a tablet with no dialer), copies [fallback] instead so the tap is never
  /// a dead end.
  Future<void> _launch(
    BuildContext context,
    Uri uri, {
    required String fallback,
    required String label,
  }) async {
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (opened || !context.mounted) return;
    await _copy(context, label, fallback);
  }

  Future<void> _copy(BuildContext context, String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (context.mounted) {
      showMessage(context, context.t('$label copied', '$label कपी भयो'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;

    final faqs = <(String, String)>[
      (
        context.t('Does Kharcha work offline?', 'खर्चा अफलाइन चल्छ?'),
        context.t(
          'Yes. Everything is saved on your phone first, so you can record '
              'expenses with no internet. It syncs by itself once you are '
              'back online.',
          'चल्छ। सबै कुरा पहिले फोनमै सुरक्षित हुन्छ, त्यसैले इन्टरनेट बिना '
              'पनि खर्च लेख्न सकिन्छ। अनलाइन भएपछि आफैँ सिङ्क हुन्छ।',
        ),
      ),
      (
        context.t('How do I keep my data safe?', 'डाटा कसरी सुरक्षित राख्ने?'),
        context.t(
          'Sign in with an account and your records sync to it '
              'automatically. For an extra copy, go to Settings → Backup & '
              'Restore to save a backup to the cloud or to a file.',
          'खातामा साइन इन गरेपछि रेकर्ड आफैँ सिङ्क हुन्छन्। थप प्रतिलिपिका '
              'लागि सेटिङ → ब्याकअप र रिस्टोरबाट क्लाउड वा फाइलमा ब्याकअप '
              'राख्नुहोस्।',
        ),
      ),
      (
        context.t(
          'I used guest mode. Will I lose my data?',
          'पाहुना मोड प्रयोग गरेँ। डाटा हराउँछ?',
        ),
        context.t(
          'Guest data lives only on this phone. Tap "Save your data" in '
              'Settings to create an account and keep everything.',
          'पाहुनाको डाटा यो फोनमा मात्र हुन्छ। सबै राख्न सेटिङमा "डाटा '
              'सुरक्षित गर्नुहोस्" थिचेर खाता बनाउनुहोस्।',
        ),
      ),
      (
        context.t('Why am I not getting notifications?', 'सूचना किन आउँदैन?'),
        context.t(
          'Turn on "Allow notifications" in Settings → Notifications. If '
              'Android says it is blocked, allow it in your phone’s '
              'Settings → Apps → Kharcha → Notifications.',
          'सेटिङ → सूचनाहरूमा "सूचना अनुमति दिनुहोस्" खोल्नुहोस्। अवरुद्ध '
              'देखाएमा फोनको सेटिङ → एप → खर्चा → सूचनामा अनुमति दिनुहोस्।',
        ),
      ),
      (
        context.t('How does the AI work?', 'AI ले कसरी काम गर्छ?'),
        context.t(
          'A secure server makes a small summary of your own spending and '
              'asks the AI for a suggestion. The flame’s mood comes from '
              'how much of this month’s income you have kept.',
          'सुरक्षित सर्भरले तपाईंको खर्चको सानो सारांश बनाएर AI सँग सुझाव '
              'माग्छ। ज्वालाको मुड यस महिनाको आम्दानीबाट कति बचत भयो भन्नेमा '
              'भर पर्छ।',
        ),
      ),
      (
        context.t(
          'How do I switch language or calendar?',
          'भाषा वा पात्रो कसरी बदल्ने?',
        ),
        context.t(
          'Settings → Preferences lets you choose English or Nepali, and '
              'Bikram Sambat or the English calendar.',
          'सेटिङ → प्राथमिकताबाट अंग्रेजी वा नेपाली, र विक्रम संवत् वा '
              'अंग्रेजी पात्रो छान्न सकिन्छ।',
        ),
      ),
    ];

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
          title: Text(
            context.t('Help & Support', 'मद्दत र सहयोग'),
            style: theme.textTheme.titleLarge,
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 48),
            children: <Widget>[
              Text(
                context.t('We are here to help', 'हामी मद्दतका लागि छौँ'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                context.t(
                  'Have a question, found a bug, or want a feature? Reach out.',
                  'प्रश्न छ, बग भेटियो, वा नयाँ सुविधा चाहियो? सम्पर्क गर्नुहोस्।',
                ),
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
                      label: context.t('Email', 'इमेल'),
                      value: contactEmail,
                      onTap: () => _launch(
                        context,
                        Uri(
                          scheme: 'mailto',
                          path: contactEmail,
                          queryParameters: const <String, String>{
                            'subject': 'Kharcha support',
                          },
                        ),
                        fallback: contactEmail,
                        label: 'Email',
                      ),
                      onCopy: () => _copy(context, 'Email', contactEmail),
                    ),
                    const Divider(height: 1),
                    _ContactTile(
                      icon: Icons.phone_outlined,
                      color: const Color(0xFF30D158),
                      label: context.t('Phone', 'फोन'),
                      value: contactPhone,
                      onTap: () => _launch(
                        context,
                        Uri(scheme: 'tel', path: contactPhone),
                        fallback: contactPhone,
                        label: 'Phone',
                      ),
                      onCopy: () => _copy(context, 'Phone', contactPhone),
                    ),
                    const Divider(height: 1),
                    _ContactTile(
                      icon: Icons.bug_report_outlined,
                      color: const Color(0xFFFF9F0A),
                      label: context.t(
                        'Report a problem',
                        'समस्या रिपोर्ट गर्नुहोस्',
                      ),
                      value: context.t(
                        'Open a bug report or feature idea',
                        'बग रिपोर्ट वा सुविधाको सुझाव खोल्नुहोस्',
                      ),
                      onTap: () => _launch(
                        context,
                        Uri.parse(bugReportUrl),
                        fallback: bugReportUrl,
                        label: 'Link',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                context.t('Frequently asked', 'धेरै सोधिने प्रश्न'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              GlassCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: <Widget>[
                    for (var i = 0; i < faqs.length; i++) ...<Widget>[
                      if (i > 0) const Divider(height: 1),
                      _Faq(question: faqs[i].$1, answer: faqs[i].$2),
                    ],
                  ],
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
    this.onCopy,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final VoidCallback onTap;

  /// When set, a copy button is shown beside the row's main action.
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
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
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (onCopy != null)
              IconButton(
                tooltip: context.t('Copy', 'कपी गर्नुहोस्'),
                onPressed: onCopy,
                icon: Icon(
                  Icons.copy_rounded,
                  size: 18,
                  color: glass.textTertiary,
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.all(12),
                child: Icon(
                  Icons.open_in_new_rounded,
                  size: 18,
                  color: glass.textTertiary,
                ),
              ),
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
