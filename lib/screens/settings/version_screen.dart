import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_info.dart';
import '../../core/l10n/app_l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../services/update_service.dart';
import '../../widgets/common/form_helpers.dart';
import '../../widgets/common/glass_background.dart';
import '../../widgets/common/glass_card.dart';

/// About the app: what it is, what changed, how to update, who made it.
class VersionScreen extends StatefulWidget {
  const VersionScreen({super.key});

  static const String developerName = 'Nischal Pandey';
  static const String instagramUrl = 'https://instagram.com/nischalsir';
  static const String repoUrl = 'https://github.com/nischalsir/kharcha';
  static const String releasesUrl = '$repoUrl/releases';

  @override
  State<VersionScreen> createState() => _VersionScreenState();
}

class _VersionScreenState extends State<VersionScreen> {
  bool _checking = false;

  /// What changed in the installed version. Update with each release.
  static const List<(String, String)> _whatsNew = <(String, String)>[
    (
      'A new flame with many more moods and reactions',
      'नयाँ ज्वाला, धेरै नयाँ भाव र प्रतिक्रियाहरू',
    ),
    (
      'Shop credit items: just a name, a price and a picture',
      'पसल उधारो: नाम, मूल्य र तस्बिर मात्र',
    ),
    ('Calculator inside the price field', 'मूल्य फिल्डभित्रै क्याल्कुलेटर'),
    (
      'Weather for your own town on the Calendar',
      'पात्रोमा तपाईंकै शहरको मौसम',
    ),
    (
      'Profile pictures in the fingerprint account chooser',
      'फिंगरप्रिन्ट खाता छनोटमा प्रोफाइल तस्बिर',
    ),
    (
      'Pull down on any page to refresh it',
      'जुनसुकै पृष्ठ तल तानेर रिफ्रेस गर्नुहोस्',
    ),
    ('Cleaner date on the home card', 'गृह कार्डमा सफा मिति'),
    (
      'Several accounts can use fingerprint sign-in on one phone',
      'एउटै फोनमा धेरै खाताले फिंगरप्रिन्ट साइन इन प्रयोग गर्न सक्छन्',
    ),
    (
      'Fingerprint sign-in no longer asks for the authenticator code',
      'फिंगरप्रिन्ट साइन इनमा अब प्रमाणक कोड सोधिँदैन',
    ),
    (
      'Switching accounts never shows another account’s data',
      'खाता बदल्दा अर्को खाताको डाटा कहिल्यै देखिँदैन',
    ),
    (
      'A picture for every festival in the calendar',
      'पात्रोमा हरेक चाडपर्वको तस्बिर',
    ),
    (
      'Import your bank PDF or eSewa Excel statement',
      'बैंक PDF वा eSewa Excel स्टेटमेन्ट आयात',
    ),
    ('Weather on today’s calendar card', 'आजको पात्रो कार्डमा मौसम'),
    (
      'Smaller profile card, cleaner edit profile',
      'सानो प्रोफाइल कार्ड, सफा प्रोफाइल सम्पादन',
    ),
    (
      'Clearer warning when a new password repeats the old one',
      'नयाँ पासवर्ड पुरानै भए स्पष्ट चेतावनी',
    ),
  ];

  Future<void> _checkForUpdate() async {
    setState(() => _checking = true);
    final update = await UpdateService().checkForUpdate();
    if (!mounted) return;
    setState(() => _checking = false);
    if (update == null) {
      showMessage(
        context,
        context.t('You have the latest version.', 'तपाईंसँग नवीनतम संस्करण छ।'),
      );
      return;
    }
    await UpdateService.showUpdateDialog(context, update);
  }

  Future<void> _open(String url) async {
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      showMessage(
        context,
        context.t('Could not open the link.', 'लिङ्क खोल्न सकिएन।'),
      );
    }
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
          title: Text(
            context.t('About Kharcha', 'खर्चा बारे'),
            style: theme.textTheme.titleLarge,
          ),
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
                    ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: Image.asset(
                        'assets/images/logo.png',
                        width: 76,
                        height: 76,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Icon(
                          Icons.local_fire_department_rounded,
                          size: 56,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Kharcha',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.t(
                        'Your money, in your calendar, in your language.',
                        'तपाईंको पैसा, तपाईंकै पात्रो र भाषामा।',
                      ),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: glass.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(
                          alpha: 0.14,
                        ),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${context.t('Version', 'संस्करण')} ${AppInfo.version}',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        onPressed: _checking ? null : _checkForUpdate,
                        icon: _checking
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.system_update_rounded, size: 18),
                        label: Text(
                          context.t(
                            'Check for updates',
                            'अपडेट जाँच गर्नुहोस्',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _Heading(context.t('What’s new', 'के नयाँ छ')),
              const SizedBox(height: 8),
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (final item in _whatsNew)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Icon(
                              Icons.auto_awesome_rounded,
                              size: 16,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                context.t(item.$1, item.$2),
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => _open(VersionScreen.releasesUrl),
                        child: Text(
                          context.t('See all releases', 'सबै रिलिज हेर्नुहोस्'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _Heading(context.t('About', 'बारे')),
              const SizedBox(height: 8),
              Text(
                context.t(
                  'Kharcha is an expense tracker made for Nepal. It follows '
                      'the Bikram Sambat calendar, knows the festivals and '
                      'the daily tithi, and works without internet. A little '
                      'flame keeps you company: it glows when you save and '
                      'worries when you overspend. Your records are private '
                      'to your account.',
                  'खर्चा नेपालका लागि बनाइएको खर्च ट्र्याकर हो। यसले विक्रम '
                      'संवत् पात्रो, चाडपर्व र दैनिक तिथि बुझ्छ, र इन्टरनेट '
                      'बिना पनि चल्छ। एउटा सानो ज्वालाले साथ दिन्छ: बचत गर्दा '
                      'चम्किन्छ, बढी खर्च गर्दा चिन्तित हुन्छ। तपाईंका रेकर्ड '
                      'तपाईंको खातामा मात्र सीमित छन्।',
                ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: glass.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              _Heading(context.t('Made by', 'निर्माता')),
              const SizedBox(height: 8),
              GlassCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: <Widget>[
                    _LinkRow(
                      icon: Icons.person_rounded,
                      label: VersionScreen.developerName,
                      trailing: '@nischalsir',
                      onTap: () => _open(VersionScreen.instagramUrl),
                    ),
                    const Divider(height: 1),
                    _LinkRow(
                      icon: Icons.code_rounded,
                      label: context.t(
                        'Source code on GitHub',
                        'GitHub मा स्रोत कोड',
                      ),
                      onTap: () => _open(VersionScreen.repoUrl),
                    ),
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

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleMedium
          ?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String? trailing;
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
            Icon(icon, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (trailing != null) ...<Widget>[
              Text(
                trailing!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: glass.textSecondary,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Icon(
              Icons.open_in_new_rounded,
              size: 16,
              color: glass.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}
