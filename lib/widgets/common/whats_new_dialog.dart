import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_info.dart';
import '../../core/l10n/app_l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../models/sync_models.dart';
import '../../services/cache_service.dart';
import 'form_helpers.dart';

/// What changed in the installed version, and whether its owner has been
/// told. Update [items] with each release.
class WhatsNew {
  const WhatsNew._();

  /// Where to follow the developer.
  static const String instagramUrl = 'https://instagram.com/nischalsir';

  static const String _seenKey = 'whats_new.seen_version';

  /// English and Nepali, newest first.
  static const List<(String, String)> items = <(String, String)>[
    (
      'Continue with Google: sign in or sign up without a password',
      'Google बाट जारी राख्नुहोस्: पासवर्ड बिना साइन इन वा साइन अप',
    ),
    (
      'New accounts confirm their email with a 6-digit code',
      'नयाँ खाताले ६ अंकको कोडबाट इमेल पुष्टि गर्छ',
    ),
    (
      'Flamey now roasts your spending habits, using your own numbers',
      'Flamey ले अब तपाईंकै अङ्क लिएर खर्च गर्ने बानीको खिल्ली उडाउँछ',
    ),
    (
      'Flamey has over twenty moods, from Fuming to Smitten',
      'Flamey का बीसभन्दा बढी मुड छन्, रिसाएकोदेखि मायामा परेकोसम्म',
    ),
    (
      'Every Flamey reaction has its own colour and its own way of moving',
      'Flamey को हरेक भावको आफ्नै रङ र आफ्नै चाल छ',
    ),
    (
      'Pull to refresh: Flamey pulls faces, then says the page refreshed',
      'तानेर रिफ्रेस: Flamey ले अनुहार बदल्छ, अनि पृष्ठ रिफ्रेस भएको भन्छ',
    ),
    (
      'Google Drive backup: connect your Google account in Settings',
      'Google Drive ब्याकअप: सेटिङमा आफ्नो Google खाता जोड्नुहोस्',
    ),
    (
      'SMS import: paste messages when Android blocks the permission',
      'SMS आयात: Android ले अनुमति रोक्दा सन्देश टाँस्नुहोस्',
    ),
    (
      'A bell on Home opens your notifications, the new ones on top',
      'होमको घण्टीले सूचनाहरू खोल्छ, नयाँ सूचना माथि',
    ),
    (
      'Import from SMS: bank, eSewa and Khalti alerts become transactions',
      'SMS बाट आयात: बैंक, eSewa र Khalti का सन्देश कारोबार बन्छन्',
    ),
    (
      'Household: one ledger shared with family, joined by an invite code',
      'घरपरिवार: परिवारसँग साझा खाता, निम्तो कोडबाट जोडिने',
    ),
    (
      'Loans & EMI: instalment, interest and what is left to pay',
      'ऋण र किस्ता: किस्ता, ब्याज र तिर्न बाँकी',
    ),
    (
      'Press and hold the app icon for Add expense, Add income and Import',
      'खर्च, आम्दानी थप्न र आयात गर्न एपको आइकन थिचिराख्नुहोस्',
    ),
    (
      'Three home-screen widgets: today, this month and quick actions',
      'तीन होम स्क्रिन विजेट: आज, यो महिना र द्रुत कार्य',
    ),
    (
      'Savings goals, and wallets with balances and transfers',
      'बचत लक्ष्य, र ब्यालेन्स तथा रकम सार्ने सुविधासहित वालेट',
    ),
    (
      'Receipt photos on transactions, and filters on the Payments page',
      'कारोबारमा रसिदको फोटो, र भुक्तानी पृष्ठमा फिल्टर',
    ),
    (
      'Split a bill with friends, and set a budget for a festival',
      'साथीहरूसँग बिल बाँड्नुहोस्, र चाडपर्वका लागि बजेट राख्नुहोस्',
    ),
    (
      'Amounts show paisa everywhere: NPR 1,000.00',
      'रकममा सबैतिर पैसा देखिन्छ: NPR 1,000.00',
    ),
    (
      'Fixed: built-in categories now sync for every account',
      'सुधार: पूर्वनिर्धारित श्रेणी अब हरेक खातामा सिङ्क हुन्छन्',
    ),
  ];

  /// Whether this version's changes have not been shown on this phone yet.
  ///
  /// A phone with nothing recorded has nothing to compare the changes with:
  /// someone who has just installed the app is not told what is "new", and
  /// the version is simply noted.
  static bool shouldShow(CacheService cache) {
    if (cache.readSetting(_seenKey) == AppInfo.version) return false;
    return cache.rows(SyncEntity.transactions).isNotEmpty;
  }

  static Future<void> markSeen(CacheService cache) =>
      cache.writeSetting(_seenKey, AppInfo.version);
}

/// Shows what is new once after each update, the first time Home opens on
/// the new version.
Future<void> maybeShowWhatsNew(BuildContext context) async {
  final CacheService cache;
  try {
    cache = context.read<CacheService>();
  } on ProviderNotFoundException {
    // A test or a preview built without the app's providers.
    return;
  }
  final show = WhatsNew.shouldShow(cache);
  // Noted before it is shown, so closing the app on the pop-up does not
  // bring it back on every launch.
  await WhatsNew.markSeen(cache);
  if (!show || !context.mounted) return;
  await showWhatsNewDialog(context);
}

/// The "What's new" pop-up: the changes in this version, and a way to
/// follow the developer.
Future<void> showWhatsNewDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _WhatsNewDialog(),
  );
}

class _WhatsNewDialog extends StatelessWidget {
  const _WhatsNewDialog();

  Future<void> _follow(BuildContext context) async {
    final failed = context.t('Could not open the link.', 'लिङ्क खोल्न सकिएन।');
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(WhatsNew.instagramUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }
    if (!opened && context.mounted) showMessage(context, failed);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;

    return AlertDialog(
      contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  size: 30,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Center(
              child: Text(
                context.t(
                  'What’s new in ${AppInfo.displayVersion}',
                  '${AppInfo.displayVersion} मा के नयाँ छ',
                ),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 14),
            for (final item in WhatsNew.items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.check_circle_rounded,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        context.t(item.$1, item.$2),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      // Under the list, not in it: the two buttons stay in sight however
      // long the list of changes grows.
      actions: <Widget>[
        SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const ValueKey<String>('whats-new-follow'),
                  onPressed: () => _follow(context),
                  icon: const Icon(Icons.camera_alt_outlined, size: 18),
                  label: Text(
                    context.t(
                      'Follow me on Instagram',
                      'Instagram मा फलो गर्नुहोस्',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '@nischalsir',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: glass.textTertiary,
                ),
              ),
              TextButton(
                key: const ValueKey<String>('whats-new-close'),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.t('Got it', 'बुझेँ')),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
