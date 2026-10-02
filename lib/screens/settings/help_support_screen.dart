import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n/app_l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../models/statement_entry.dart';
import '../payments/statement_guide_screen.dart';
import '../payments/statement_import_screen.dart';
import '../../widgets/common/form_helpers.dart';
import '../../widgets/common/glass_background.dart';
import '../../widgets/common/glass_card.dart';
import '../../widgets/common/glass_back_button.dart';

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
        context.t(
          'Why is a wallet balance wrong or below zero?',
          'वालेटको ब्यालेन्स किन गलत वा शून्यभन्दा कम छ?',
        ),
        context.t(
          'A wallet starts at zero and follows the income, expenses and '
              'transfers recorded against it, so it only knows what you have '
              'entered. Open More → Wallets, tap the wallet and type what is '
              'really in it now. Your transactions are not changed.',
          'वालेट शून्यबाट सुरु हुन्छ र यसमा लेखिएको आम्दानी, खर्च र सारेको '
              'रकम अनुसार चल्छ, त्यसैले यसले तपाईंले लेखेको मात्र जान्दछ। '
              'थप → वालेटहरूमा गएर वालेट थिच्नुहोस् र अहिले साँच्चै भएको रकम '
              'लेख्नुहोस्। तपाईंका कारोबार बदलिँदैनन्।',
        ),
      ),
      (
        context.t(
          'How do I put Kharcha on my home screen?',
          'खर्चालाई होम स्क्रिनमा कसरी राख्ने?',
        ),
        context.t(
          'Press and hold an empty spot on your home screen, choose '
              'Widgets and pick Kharcha. It shows what you spent today and '
              'this month, and its Add button opens a new expense.',
          'होम स्क्रिनको खाली ठाउँमा थिचिराख्नुहोस्, Widgets छानेर खर्चा '
              'रोज्नुहोस्। यसले आज र यस महिनाको खर्च देखाउँछ, र Add बटनले नयाँ '
              'खर्च खोल्छ।',
        ),
      ),
      (
        context.t(
          'Where are my receipt photos kept?',
          'रसिदका फोटो कहाँ राखिन्छन्?',
        ),
        context.t(
          'In your own private folder in the cloud, so only your account '
              'can open them. Attaching one needs internet; if it cannot be '
              'uploaded the transaction is still saved, and you can add the '
              'photo later by tapping the transaction.',
          'क्लाउडमा तपाईंको आफ्नै निजी फोल्डरमा, त्यसैले तपाईंको खाताले मात्र '
              'खोल्न सक्छ। फोटो जोड्न इन्टरनेट चाहिन्छ; अपलोड हुन नसके पनि '
              'कारोबार सुरक्षित हुन्छ, र पछि कारोबार थिचेर फोटो थप्न सकिन्छ।',
        ),
      ),
      (
        context.t('How does Flamey work?', 'Flamey ले कसरी काम गर्छ?'),
        context.t(
          'Suggestions arrive on their own: in the morning (yesterday), at '
              'midday (today against a typical day), in the evening and at '
              'the end of the day, with a weekly look on Saturday evening and '
              'a monthly one three times a month. They also update when you '
              'add, edit or delete a transaction or change a budget. Every '
              'figure comes from your own records. Flamey writes one on the '
              'phone straight away; when online, the AI writes a version '
              'from a private summary, and anything quoting a figure that is '
              'not in your records is thrown away. Pull the Home page down '
              'to ask again. Flamey’s face follows what is being said.',
          'सुझाव आफैं आउँछन्: बिहान (हिजोको), दिउँसो (सामान्य दिनसँग '
              'तुलना), साँझ र दिनको अन्त्यमा, शनिबार साँझ हप्ताको र महिनामा तीन '
              'पटक महिनाको। कारोबार थप्दा, बदल्दा वा मेटाउँदा र बजेट बदल्दा पनि '
              'सुझाव फेरिन्छ। हरेक अङ्क तपाईंकै रेकर्डबाट आउँछ। ताजा गर्न '
              'गृह पृष्ठ तल तान्नुहोस्।',
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
          leading: const GlassBackButton(),
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
                context.t(
                  'Import bank / eSewa statement',
                  'बैंक / eSewa स्टेटमेन्ट आयात',
                ),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const _StatementImportHelp(),
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

/// How statement import works, and the ways into it.
class _StatementImportHelp extends StatelessWidget {
  const _StatementImportHelp();

  void _guide(BuildContext context, StatementSource source) {
    Navigator.of(context)
        .push<bool>(
          MaterialPageRoute<bool>(
            builder: (_) => StatementGuideScreen(source: source),
          ),
        )
        .then((chooseFile) {
          if (chooseFile == true && context.mounted) _import(context);
        });
  }

  void _import(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const StatementImportScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;

    Widget point(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: glass.textSecondary,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          point(
            Icons.auto_awesome_rounded,
            context.t(
              'Download a statement from your bank or eSewa, choose the file, '
                  'and Kharcha turns its rows into expenses and income. You '
                  'check the list first; nothing is added until you confirm.',
              'आफ्नो बैंक वा eSewa बाट स्टेटमेन्ट डाउनलोड गरी फाइल छान्नुहोस्, '
                  'खर्चाले त्यसका पङ्क्तिलाई खर्च र आम्दानीमा बदल्छ। पहिले '
                  'सूची जाँच्नुहुन्छ; पुष्टि नगरी केही थपिँदैन।',
            ),
          ),
          point(
            Icons.insert_drive_file_outlined,
            context.t(
              'File types: Excel (.xls, .xlsx), CSV and PDF, up to 5 MB. '
                  'Excel or CSV reads most reliably. A PDF that is not laid '
                  'out as a table is refused rather than guessed at.',
              'फाइल प्रकार: Excel (.xls, .xlsx), CSV र PDF, ५ MB सम्म। Excel '
                  'वा CSV सबैभन्दा भरपर्दो हुन्छ। तालिकाजस्तो नभएको PDF '
                  'अनुमान नगरी अस्वीकार गरिन्छ।',
            ),
          ),
          point(
            Icons.list_alt_rounded,
            context.t(
              'What is imported: the date, the description, the amount and '
                  'whether it was money in or out. Balances and totals are '
                  'ignored.',
              'के आयात हुन्छ: मिति, विवरण, रकम र पैसा आएको वा गएको। ब्यालेन्स '
                  'र जम्मा रकम बेवास्ता गरिन्छ।',
            ),
          ),
          point(
            Icons.verified_outlined,
            context.t(
              'No duplicates: each row is recognised if you import the same '
                  'statement again, shown as already imported and left out.',
              'दोहोरो हुँदैन: एउटै स्टेटमेन्ट फेरि आयात गर्दा हरेक पङ्क्ति '
                  'चिनिन्छ, पहिल्यै आयात भएको देखाइन्छ र छोडिन्छ।',
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _guide(context, StatementSource.bank),
                  icon: const Icon(Icons.account_balance_rounded, size: 18),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(context.t('Bank steps', 'बैंक चरण')),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _guide(context, StatementSource.esewa),
                  icon: const Icon(
                    Icons.account_balance_wallet_rounded,
                    size: 18,
                  ),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(context.t('eSewa steps', 'eSewa चरण')),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _guide(context, StatementSource.khalti),
                  icon: const Icon(Icons.wallet_rounded, size: 18),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(context.t('Khalti steps', 'Khalti चरण')),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _guide(context, StatementSource.other),
                  icon: const Icon(Icons.description_rounded, size: 18),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(context.t('Other apps', 'अन्य एप')),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _import(context),
              icon: const Icon(Icons.upload_file_rounded, size: 18),
              label: Text(
                context.t('Import a statement', 'स्टेटमेन्ट आयात गर्नुहोस्'),
              ),
            ),
          ),
        ],
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
