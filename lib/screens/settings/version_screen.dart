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
import '../../widgets/common/whats_new_dialog.dart';

/// About the app: what it is, what changed, how to update, who made it.
class VersionScreen extends StatefulWidget {
  const VersionScreen({super.key});

  static const String developerName = 'Nischal Pandey';
  static const String instagramUrl = WhatsNew.instagramUrl;
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

  /// What changed in the installed version; shared with the pop-up that
  /// shows it once after an update.
  static const List<(String, String)> _whatsNew = WhatsNew.items;

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
