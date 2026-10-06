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

  /// What changed in this version, in English and Nepali. Only this
  /// version: the pop-up says what is new since the last update, in a few
  /// lines. Replace the list with each release; do not add to it.
  static const List<(String, String)> items = <(String, String)>[
    (
      'Bill maker: rent, water and electricity bills as a PDF',
      'बिल बनाउने: भाडा, पानी र बिजुलीको बिल PDF मा',
    ),
    (
      'Payment QR: save a shop’s or a friend’s QR and open it to pay',
      'भुक्तानी QR: पसल वा साथीको QR राख्नुहोस्, तिर्दा खोल्नुहोस्',
    ),
    (
      'Dark mode fixed on the pages that turned white',
      'सेतो देखिने पृष्ठहरूमा डार्क मोड ठीक गरियो',
    ),
    (
      'No SMS permission any more: paste messages to import them',
      'अब SMS अनुमति चाहिँदैन: आयात गर्न सन्देश टाँस्नुहोस्',
    ),
    ('Sync now, straight from Settings', 'सेटिङबाटै अहिले सिङ्क गर्नुहोस्'),
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
