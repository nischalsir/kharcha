import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/errors/app_failure.dart';
import '../../core/l10n/app_l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../services/payment_qr_store.dart';
import 'form_helpers.dart';
import 'glass_back_button.dart';
import 'glass_button.dart';
import 'glass_card.dart';
import 'receipt_field.dart';

/// The payment QR of a shop or a friend, as a row on their page.
///
/// With none saved, tapping it asks for a picture of the code (a photo of
/// the one on the counter, or a screenshot someone sent) and uploads it.
/// With one saved, tapping it opens the code full screen, ready to be
/// scanned from another phone, where it can also be replaced or removed.
class PaymentQrTile extends StatefulWidget {
  const PaymentQrTile({
    super.key,
    required this.owner,
    required this.id,
    required this.name,
    required this.path,
    required this.onChanged,
    this.store = const PaymentQrStore(),
    this.pick,
  });

  final PaymentQrOwner owner;

  /// The pasal's or the friend's id.
  final String id;

  /// Their name, for the heading over the code.
  final String name;

  /// Where the saved QR is, or null when there is none.
  final String? path;

  /// Saves the new path (null to take it off) on the pasal or the friend.
  /// False when it could not be saved.
  final Future<bool> Function(String? path) onChanged;

  final PaymentQrStore store;

  /// Replaces the camera and the gallery in tests.
  final Future<Uint8List?> Function(BuildContext context)? pick;

  @override
  State<PaymentQrTile> createState() => _PaymentQrTileState();
}

class _PaymentQrTileState extends State<PaymentQrTile> {
  bool _busy = false;

  Future<Uint8List?> _pick() {
    final pick = widget.pick;
    if (pick != null) return pick(context);
    return pickReceiptImage(
      context,
      title: context.t('Payment QR', 'भुक्तानी QR'),
    );
  }

  /// Picks a picture, uploads it and saves its path. Returns the new path,
  /// or null when the user backed out or it failed (they are told why).
  Future<String?> _upload() async {
    if (_busy) return null;
    final bytes = await _pick();
    if (bytes == null || !mounted) return null;
    final failed = context.t(
      'The QR could not be saved. Check your connection and try again.',
      'QR सुरक्षित गर्न सकिएन। इन्टरनेट जाँचेर फेरि प्रयास गर्नुहोस्।',
    );
    final saved = context.t('Payment QR saved.', 'भुक्तानी QR सुरक्षित भयो।');
    setState(() => _busy = true);
    final old = widget.path;
    try {
      final path = await widget.store.upload(
        bytes,
        owner: widget.owner,
        id: widget.id,
      );
      if (!await widget.onChanged(path)) {
        // The row still names the old picture: do not leave the new one.
        await widget.store.remove(path);
        if (mounted) showMessage(context, failed);
        return null;
      }
      if (old != null && old != path) await widget.store.remove(old);
      if (mounted) showMessage(context, saved);
      return path;
    } on AppFailure catch (failure) {
      if (mounted) showMessage(context, failure.message);
      return null;
    } catch (_) {
      if (mounted) showMessage(context, failed);
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Takes the QR off. True when it is gone.
  Future<bool> _remove() async {
    final old = widget.path;
    if (old == null || _busy) return false;
    setState(() => _busy = true);
    try {
      if (!await widget.onChanged(null)) return false;
      await widget.store.remove(old);
      return true;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open() async {
    final path = widget.path;
    if (path == null) {
      await _upload();
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PaymentQrScreen(
          name: widget.name,
          path: path,
          store: widget.store,
          onReplace: _upload,
          onRemove: _remove,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    final has = widget.path != null;
    const color = Color(0xFF5E5CE6);
    return GlassCard(
      key: const ValueKey<String>('payment-qr'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      onTap: _busy ? null : _open,
      child: Row(
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.qr_code_2_rounded, color: color, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  context.t('Payment QR', 'भुक्तानी QR'),
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  has
                      ? context.t(
                          'Open it to scan and pay',
                          'स्क्यान गरेर तिर्न खोल्नुहोस्',
                        )
                      : context.t(
                          'Add their QR code, from a photo or a screenshot',
                          'फोटो वा स्क्रिनसटबाट उनको QR थप्नुहोस्',
                        ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: glass.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (_busy)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(
              has
                  ? Icons.chevron_right_rounded
                  : Icons.add_photo_alternate_outlined,
              color: has ? glass.textTertiary : theme.colorScheme.primary,
            ),
        ],
      ),
    );
  }
}

/// A saved payment QR, full screen: large and on white whatever the theme,
/// which is what a scanner needs.
class PaymentQrScreen extends StatefulWidget {
  const PaymentQrScreen({
    super.key,
    required this.name,
    required this.path,
    required this.onReplace,
    required this.onRemove,
    this.store = const PaymentQrStore(),
  });

  final String name;
  final String path;

  /// Picks and saves another picture; the new path, or null when nothing
  /// changed.
  final Future<String?> Function() onReplace;

  /// Takes the QR off; true when it is gone.
  final Future<bool> Function() onRemove;

  final PaymentQrStore store;

  @override
  State<PaymentQrScreen> createState() => _PaymentQrScreenState();
}

class _PaymentQrScreenState extends State<PaymentQrScreen> {
  late String _path = widget.path;
  late Future<String?> _url = widget.store.signedUrl(_path);
  bool _busy = false;

  Future<void> _replace() async {
    setState(() => _busy = true);
    final path = await widget.onReplace();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (path != null) {
        _path = path;
        _url = widget.store.signedUrl(path);
      }
    });
  }

  Future<void> _remove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.t('Remove this QR?', 'यो QR हटाउने?')),
        content: Text(
          dialogContext.t(
            'The picture is deleted. You can add one again at any time.',
            'तस्बिर मेटिन्छ। जुनसुकै बेला फेरि थप्न सकिन्छ।',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(dialogContext.t('Cancel', 'रद्द गर्नुहोस्')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: Text(dialogContext.t('Remove', 'हटाउनुहोस्')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final failed = context.t(
      'The QR could not be removed. Try again.',
      'QR हटाउन सकिएन। फेरि प्रयास गर्नुहोस्।',
    );
    setState(() => _busy = true);
    final gone = await widget.onRemove();
    if (!mounted) return;
    if (gone) {
      Navigator.of(context).pop();
    } else {
      setState(() => _busy = false);
      showMessage(context, failed);
    }
  }

  Widget _unavailable(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        context.t(
          'This QR cannot be shown right now. Check your connection and try '
              'again.',
          'यो QR अहिले देखाउन सकिएन। इन्टरनेट जाँचेर फेरि प्रयास गर्नुहोस्।',
        ),
        key: const ValueKey<String>('payment-qr-unavailable'),
        textAlign: TextAlign.center,
        // On the white panel, whatever the theme.
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: const Color(0xFF3A3A3C)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    return Scaffold(
      appBar: AppBar(
        leading: const GlassBackButton(),
        title: Text(context.t('Payment QR', 'भुक्तानी QR')),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            children: <Widget>[
              Text(
                widget.name,
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                context.t(
                  'Scan this from the wallet app on another phone, or pinch '
                      'to make it larger.',
                  'अर्को फोनको वालेट एपबाट यो स्क्यान गर्नुहोस्, वा ठूलो '
                      'पार्न पिन्च गर्नुहोस्।',
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: glass.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: ColoredBox(
                        key: const ValueKey<String>('payment-qr-panel'),
                        // A scanner reads dark on white; never the theme's
                        // own surface.
                        color: Colors.white,
                        child: FutureBuilder<String?>(
                          future: _url,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState !=
                                ConnectionState.done) {
                              return const Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                ),
                              );
                            }
                            final url = snapshot.data;
                            if (url == null) {
                              return Center(child: _unavailable(context));
                            }
                            return InteractiveViewer(
                              maxScale: 5,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Image.network(
                                  url,
                                  fit: BoxFit.contain,
                                  loadingBuilder: (context, child, progress) =>
                                      progress == null
                                      ? child
                                      : const Center(
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.4,
                                          ),
                                        ),
                                  errorBuilder: (context, _, _) =>
                                      Center(child: _unavailable(context)),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  Expanded(
                    child: GlassButton(
                      key: const ValueKey<String>('payment-qr-replace'),
                      label: context.t('Replace', 'फेर्नुहोस्'),
                      icon: Icons.swap_horiz_rounded,
                      onPressed: _busy ? null : _replace,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GlassButton(
                      key: const ValueKey<String>('payment-qr-remove'),
                      label: context.t('Remove', 'हटाउनुहोस्'),
                      icon: Icons.delete_outline_rounded,
                      color: glass.danger,
                      onPressed: _busy ? null : _remove,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
