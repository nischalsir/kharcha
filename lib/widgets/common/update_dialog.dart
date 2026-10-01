import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

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

/// The "Update app" prompt: what the new version is, what changed, and three
/// ways out. Download opens the release, Later asks again next time the app
/// opens, and Don't remind silences this release only.
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
                'Version ${updates.latestVersion} is ready. '
                    'You have ${updates.installedVersion}.',
                'संस्करण ${updates.latestVersion} तयार छ। '
                    'तपाईंसँग ${updates.installedVersion} छ।',
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
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.download_rounded),
                label: Text(context.t('Download', 'डाउनलोड')),
                onPressed: () {
                  // Read before the pop: the dialog's context is gone after.
                  final navigator = Navigator.of(context);
                  downloadUpdate(context);
                  navigator.pop();
                },
              ),
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
