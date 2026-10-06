import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_info.dart';
import '../../core/l10n/app_l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/update_provider.dart';

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

/// The way to get the update, wherever one is offered: one button that
/// opens the release's APK in the browser, which downloads it, and a line
/// saying what to do with it.
///
/// The app does not install updates itself. That needs Android's
/// install-packages permission, which Google Play Protect counts against an
/// app installed from a file; see docs/play-protect.md.
class UpdateAction extends StatelessWidget {
  const UpdateAction({super.key, required this.label, this.afterOpen});

  /// The button, e.g. `Download update`.
  final String label;

  /// Called after the download is opened, e.g. to close a dialog.
  final VoidCallback? afterOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        FilledButton.icon(
          key: const ValueKey<String>('update-download'),
          icon: const Icon(Icons.download_rounded, size: 18),
          label: Text(label),
          onPressed: () {
            downloadUpdate(context);
            afterOpen?.call();
          },
        ),
        const SizedBox(height: 8),
        Text(
          context.t(
            'Your browser downloads the new version. Open the file when it '
                'is done and choose Update. If Play Protect offers to scan '
                'it, choose Scan app.',
            'ब्राउजरले नयाँ संस्करण डाउनलोड गर्छ। सकिएपछि फाइल खोलेर Update '
                'छान्नुहोस्। Play Protect ले स्क्यान गर्न भन्यो भने Scan app '
                'छान्नुहोस्।',
          ),
          key: const ValueKey<String>('update-how'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: glass.textSecondary,
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// The "Update app" prompt: what the new version is, what changed, and three
/// ways out. Download opens it in the browser, Later asks again next time
/// the app opens, and Don't remind silences this release only.
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
                fontWeight: FontWeight.w700,
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
              label: context.t('Download update', 'अपडेट डाउनलोड गर्नुहोस्'),
              afterOpen: Navigator.of(context).pop,
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
