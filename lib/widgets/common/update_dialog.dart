import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_info.dart';
import '../../core/l10n/app_l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/update_provider.dart';
import '../../services/app_updater.dart';

/// Opens the latest release's download and records that the user was told.
/// Launched directly: gating on `canLaunchUrl` returns false on Android 11+
/// unless the manifest declares the intent. If no browser opens, the link is
/// copied instead so the update is never a dead end.
Future<void> downloadUpdate(BuildContext context) async {
  final updates = context.read<UpdateProvider>();
  final url = updates.updateUrl;
  if (url == null) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final copied = context.t(
    'Could not open the browser. Download link copied.',
    'ब्राउजर खोल्न सकिएन। डाउनलोड लिङ्क कपी भयो।',
  );
  await updates.markInformed();
  var opened = false;
  try {
    opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    opened = false;
  }
  if (opened) return;
  await Clipboard.setData(ClipboardData(text: url));
  messenger?.showSnackBar(SnackBar(content: Text(copied)));
}

/// The way to get the update, wherever one is offered.
///
/// Where the app can update itself (Android, a release with an APK), it
/// downloads the update here with its progress shown, then opens Android's
/// installer, which asks the user to confirm. Anywhere else, and whenever
/// that does not work, the download is opened in the browser.
class UpdateAction extends StatelessWidget {
  const UpdateAction({
    super.key,
    required this.updateLabel,
    required this.browserLabel,
    this.afterBrowser,
  });

  /// The button that starts the in-app update, e.g. `Update now`.
  final String updateLabel;

  /// The button that opens the download in the browser, e.g. `Download`.
  final String browserLabel;

  /// Called after the browser download is started, e.g. to close a dialog.
  final VoidCallback? afterBrowser;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    final updates = context.watch<UpdateProvider>();

    void openBrowser() {
      downloadUpdate(context);
      afterBrowser?.call();
    }

    Widget wide(Widget button) =>
        SizedBox(width: double.infinity, child: button);

    if (!updates.canInstallInApp) {
      return wide(
        FilledButton.icon(
          icon: const Icon(Icons.download_rounded, size: 18),
          label: Text(browserLabel),
          onPressed: openBrowser,
        ),
      );
    }

    switch (updates.installState) {
      case UpdateInstallState.idle:
        return wide(
          FilledButton.icon(
            key: const ValueKey<String>('update-now'),
            icon: const Icon(Icons.system_update_rounded, size: 18),
            label: Text(updateLabel),
            onPressed: updates.downloadAndInstall,
          ),
        );

      case UpdateInstallState.downloading:
        final progress = updates.downloadProgress;
        final percent = progress == null ? null : (progress * 100).floor();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(value: progress, minHeight: 8),
            ),
            const SizedBox(height: 4),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    percent == null
                        ? context.t('Downloading…', 'डाउनलोड हुँदैछ…')
                        : context.t(
                            'Downloading… $percent%',
                            'डाउनलोड हुँदैछ… $percent%',
                          ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: glass.textSecondary,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: updates.cancelDownload,
                  child: Text(context.t('Cancel', 'रद्द गर्नुहोस्')),
                ),
              ],
            ),
          ],
        );

      case UpdateInstallState.ready:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              context.t(
                'Downloaded. Android will ask you to confirm the install; '
                    'the first time it also asks you to allow Kharcha to '
                    'install updates. If Play Protect offers to scan the '
                    'app, choose Scan app: Google checks every new version '
                    'it has not seen yet, and it takes a few seconds.',
                'डाउनलोड भयो। Android ले इन्स्टल पुष्टि गर्न सोध्छ; पहिलो '
                    'पटक Kharcha लाई अपडेट इन्स्टल गर्न अनुमति दिन पनि '
                    'सोध्छ। Play Protect ले एप स्क्यान गर्न भन्यो भने Scan '
                    'app छान्नुहोस्: Google ले नदेखेको हरेक नयाँ संस्करण '
                    'जाँच्छ, केही सेकेन्ड लाग्छ।',
              ),
              style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
            ),
            const SizedBox(height: 8),
            wide(
              FilledButton.icon(
                key: const ValueKey<String>('update-install'),
                icon: const Icon(Icons.install_mobile_rounded, size: 18),
                label: Text(context.t('Install', 'इन्स्टल गर्नुहोस्')),
                onPressed: updates.installDownloaded,
              ),
            ),
          ],
        );

      case UpdateInstallState.failed:
        final download = updates.installProblem != UpdateProblem.install;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              download
                  ? context.t(
                      'The update could not be downloaded. Check your '
                          'connection and try again.',
                      'अपडेट डाउनलोड हुन सकेन। इन्टरनेट जाँचेर फेरि प्रयास '
                          'गर्नुहोस्।',
                    )
                  : context.t(
                      'Android could not open the installer. Download the '
                          'update in the browser instead.',
                      'Android ले इन्स्टलर खोल्न सकेन। अपडेट ब्राउजरबाट '
                          'डाउनलोड गर्नुहोस्।',
                    ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: glass.danger,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: <Widget>[
                FilledButton.tonal(
                  onPressed: updates.downloadAndInstall,
                  child: Text(context.t('Try again', 'फेरि प्रयास गर्नुहोस्')),
                ),
                TextButton(
                  onPressed: openBrowser,
                  child: Text(
                    context.t('Download in browser', 'ब्राउजरबाट डाउनलोड'),
                  ),
                ),
              ],
            ),
          ],
        );
    }
  }
}

/// The "Update app" prompt: what the new version is, what changed, and three
/// ways out. Update now downloads and installs it from here, Later asks again
/// next time the app opens, and Don't remind silences this release only.
Future<void> showUpdateDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _UpdateDialog(),
  );
}

class _UpdateDialog extends StatelessWidget {
  const _UpdateDialog();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    final updates = context.watch<UpdateProvider>();
    final notes = updates.releaseNotes ?? '';
    final latest = AppInfo.short(updates.latestVersion ?? '');
    final installed = AppInfo.short(updates.installedVersion);

    return AlertDialog(
      contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.system_update_rounded,
                size: 32,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              context.t('Update available', 'अपडेट उपलब्ध छ'),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              context.t(
                'Version $latest is ready. '
                    'You have $installed.',
                'संस्करण $latest तयार छ। '
                    'तपाईंसँग $installed छ।',
              ),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: glass.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            if (notes.isNotEmpty) ...<Widget>[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: glass.fill,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  notes,
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.45),
                ),
              ),
            ],
            const SizedBox(height: 16),
            UpdateAction(
              updateLabel: context.t('Update now', 'अहिले अपडेट गर्नुहोस्'),
              browserLabel: context.t('Download', 'डाउनलोड'),
              afterBrowser: Navigator.of(context).pop,
            ),
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: <Widget>[
        TextButton(
          onPressed: () {
            updates.dontRemind();
            Navigator.of(context).pop();
          },
          child: Text(
            context.t('Don’t remind', 'फेरि नसम्झाउनुहोस्'),
            style: TextStyle(color: glass.textSecondary),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.t('Later', 'पछि')),
        ),
      ],
    );
  }
}
