import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_info.dart';
import '../../core/l10n/app_l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/update_provider.dart';
import '../../widgets/common/form_helpers.dart';
import '../../widgets/common/glass_background.dart';
import '../../widgets/common/glass_card.dart';
import '../../widgets/common/update_dialog.dart';

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
  @override
  void initState() {
    super.initState();
    // Normally already done at launch, in which case this is a no-op. It
    // covers the page being opened before the launch check has run.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<UpdateProvider>().checkOnLaunch();
    });
  }

  /// What changed in the installed version. Update with each release.
  static const List<(String, String)> _whatsNew = <(String, String)>[
    (
      'Reports export as PDF or CSV: save to your phone or share',
      'प्रतिवेदन PDF वा CSV मा निर्यात: फोनमा सुरक्षित वा साझा गर्नुहोस्',
    ),
    (
      'A new welcome page: one screen, with Get started and Login',
      'नयाँ स्वागत पृष्ठ: एउटै स्क्रिन, सुरु गर्ने र लगइन',
    ),
    (
      'Updates download and install from inside the app',
      'अपडेट एपभित्रै डाउनलोड र इन्स्टल हुन्छ',
    ),
    (
      'Khalti transaction history files are read',
      'Khalti को कारोबार विवरण फाइल पढिन्छ',
    ),
    (
      'Fixed: statement files could be seen but not picked',
      'सुधार: स्टेटमेन्ट फाइल देखिन्थ्यो तर छान्न मिल्दैनथ्यो',
    ),
    (
      'Settings is shorter: Backup, Help and About are on the More page',
      'सेटिङ छोटो: ब्याकअप, मद्दत र बारे "थप" पृष्ठमा',
    ),
    (
      'Statement PDFs from wallets read correctly',
      'वालेटका स्टेटमेन्ट PDF ठीकसँग पढिन्छन्',
    ),
    (
      'Import a statement without choosing where it is from',
      'कहाँबाट हो नछानी स्टेटमेन्ट आयात गर्नुहोस्',
    ),
    (
      'Select all on the import review; tap a row to tick it',
      'आयात समीक्षामा "सबै छान्नुहोस्"; पङ्क्ति थिचेर छान्नुहोस्',
    ),
    (
      'Profile has its own page, opened from More; Settings is settings only',
      'प्रोफाइलको आफ्नै पृष्ठ, "थप" बाट खुल्छ; सेटिङमा सेटिङ मात्र',
    ),
    (
      'Your profile picture on the More page, under Profile',
      '"थप" पृष्ठमा प्रोफाइल अन्तर्गत तपाईंको प्रोफाइल तस्बिर',
    ),
    (
      'Share a statement PDF straight into Kharcha',
      'स्टेटमेन्ट PDF सिधै Kharcha मा Share गर्नुहोस्',
    ),
    (
      'Statement PDFs from more banks, checked against their balance',
      'धेरै बैंकका स्टेटमेन्ट PDF, ब्यालेन्ससँग जाँचेर',
    ),
    ('Khalti and other wallets as sources', 'Khalti र अन्य वालेट स्रोत'),
    (
      'Suggestions arrive on their own, morning to night',
      'सुझाव आफैं आउँछन्, बिहानदेखि रातिसम्म',
    ),
    (
      'Flamey knows your habits, and may roast them a little',
      'Flamey ले बानी चिन्छ, अलिकति जिस्काउँछ पनि',
    ),
    (
      'Flamey reacts when you tap, hold or swipe it',
      'छुँदा, थिच्दा वा स्वाइप गर्दा Flamey प्रतिक्रिया दिन्छ',
    ),
    ('A tidier More page', 'सफा "थप" पृष्ठ'),
    (
      'Google Drive backup is kept to your own account',
      'Google Drive ब्याकअप तपाईंकै खातामा मात्र',
    ),
    (
      'Pictures are saved on your phone, so pages open faster',
      'तस्बिरहरू फोनमै सुरक्षित हुन्छन्, पृष्ठ छिटो खुल्छन्',
    ),
    (
      'Statement guide ends with Done and returns you to the page',
      'स्टेटमेन्ट मार्गदर्शन “सम्पन्न” मा सकिन्छ र पृष्ठमा फर्काउँछ',
    ),
    (
      'Import bank and eSewa statements: PDF, Excel or CSV',
      'बैंक र eSewa स्टेटमेन्ट आयात: PDF, Excel वा CSV',
    ),
    (
      'Step-by-step guide for downloading your statement',
      'स्टेटमेन्ट डाउनलोड गर्ने चरणबद्ध मार्गदर्शन',
    ),
    (
      'Importing the same statement twice adds nothing twice',
      'एउटै स्टेटमेन्ट दोहोर्‍याएर आयात गर्दा कारोबार दोहोरिँदैन',
    ),
    ('Meet Flamey, your money buddy', 'Flamey, तपाईंको पैसाको साथी'),
    (
      'Clear “Signing in” and “Signing out” screens',
      'स्पष्ट “साइन इन” र “साइन आउट” स्क्रिन',
    ),
    (
      'A backup can only be restored into the account that made it',
      'ब्याकअप बनाउने खातामा मात्र पुनर्स्थापना हुन्छ',
    ),
    ('Theme choices side by side', 'थिम विकल्प एउटै पङ्क्तिमा'),
    (
      'Update prompt with Download, Later and Don’t remind',
      'डाउनलोड, पछि र नसम्झाउने विकल्पसहित अपडेट सूचना',
    ),
    (
      'Sign-in problems show as a notice from the bottom',
      'साइन इन समस्या तलबाट सूचनाका रूपमा देखिन्छ',
    ),
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
                        '${context.t('Version', 'संस्करण')} ${AppInfo.displayVersion}',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const _UpdateStatus(),
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

/// Whether the app is up to date, straight from [UpdateProvider]: the same
/// state the startup prompt and the update notification use, so this page can
/// never say something different from them.
class _UpdateStatus extends StatelessWidget {
  const _UpdateStatus();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    final updates = context.watch<UpdateProvider>();
    final checking = updates.status == UpdateStatus.checking;

    Widget checkButton(String label) => SizedBox(
      width: double.infinity,
      child: FilledButton.tonalIcon(
        onPressed: checking ? null : updates.refresh,
        icon: checking
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.refresh_rounded, size: 18),
        label: Text(label),
      ),
    );

    Widget line(IconData icon, Color color, String text) => Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );

    if (updates.isUpdateAvailable) {
      final notes = updates.releaseNotes ?? '';
      final latest = AppInfo.short(updates.latestVersion ?? '');
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: glass.warning.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: glass.warning.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.system_update_rounded,
                  size: 20,
                  color: glass.warning,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.t(
                      'Version $latest is available',
                      'संस्करण $latest उपलब्ध छ',
                    ),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            if (notes.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                notes,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: glass.textSecondary,
                  height: 1.45,
                ),
              ),
            ],
            const SizedBox(height: 12),
            UpdateAction(
              updateLabel: context.t(
                'Update to $latest',
                '$latest मा अपडेट गर्नुहोस्',
              ),
              browserLabel: context.t('Download $latest', '$latest डाउनलोड'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: <Widget>[
        switch (updates.status) {
          UpdateStatus.upToDate => line(
            Icons.check_circle_rounded,
            glass.success,
            context.t('You’re up to date', 'तपाईंसँग नवीनतम संस्करण छ'),
          ),
          UpdateStatus.failed => line(
            Icons.cloud_off_rounded,
            glass.textSecondary,
            context.t('Could not check for updates', 'अपडेट जाँच गर्न सकिएन'),
          ),
          _ => line(
            Icons.sync_rounded,
            glass.textSecondary,
            context.t('Checking for updates…', 'अपडेट जाँच हुँदैछ…'),
          ),
        },
        const SizedBox(height: 12),
        checkButton(
          updates.status == UpdateStatus.failed
              ? context.t('Try again', 'फेरि प्रयास गर्नुहोस्')
              : context.t('Check for updates', 'अपडेट जाँच गर्नुहोस्'),
        ),
      ],
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
