import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../models/sync_models.dart';
import '../../services/sync_service.dart';

/// How a pull-to-refresh ended.
enum RefreshOutcome { refreshed, offline, failed }

/// Pull-to-refresh for a whole page, with the same feedback everywhere.
///
/// Pulling shows the spinner at the top of the page. When the refresh has
/// actually finished, a small notice appears in that same spot naming the page:
/// "Home page refreshed". A refresh that did not work says so instead; it is
/// never reported as a success.
///
/// [child] must be the page's vertical scrollable, built with
/// [AlwaysScrollableScrollPhysics] so a page too short to scroll can still be
/// pulled.
class PageRefresh extends StatelessWidget {
  const PageRefresh({
    super.key,
    required this.pageName,
    required this.pageNameNe,
    required this.child,
    this.onRefresh,
  });

  /// The page's name as shown in the notice, e.g. `Home`.
  final String pageName;
  final String pageNameNe;
  final Widget child;

  /// What refreshing this page means. Defaults to fetching the account's
  /// changes from the server, which is what every data page shows.
  final Future<RefreshOutcome> Function()? onRefresh;

  /// Fetches what changed on the server since the last sync. Only the rows
  /// that changed are transferred; nothing is reloaded from scratch.
  static Future<RefreshOutcome> fromServer(SyncService sync) async {
    await sync.refresh();
    return switch (sync.status) {
      SyncStatus.synced => RefreshOutcome.refreshed,
      SyncStatus.offline => RefreshOutcome.offline,
      _ => RefreshOutcome.failed,
    };
  }

  Future<void> _refresh(BuildContext context) async {
    final refresh = onRefresh;
    final sync = refresh == null ? context.read<SyncService>() : null;
    // Resolved before the wait, while the context is certainly still valid.
    final messages = <RefreshOutcome, String>{
      RefreshOutcome.refreshed: context.t(
        '$pageName page refreshed',
        '$pageNameNe पृष्ठ रिफ्रेस भयो',
      ),
      RefreshOutcome.offline: context.t(
        'You’re offline. $pageName page not refreshed',
        'तपाईं अफलाइन हुनुहुन्छ। $pageNameNe पृष्ठ रिफ्रेस भएन',
      ),
      RefreshOutcome.failed: context.t(
        'Could not refresh $pageName page',
        '$pageNameNe पृष्ठ रिफ्रेस गर्न सकिएन',
      ),
    };

    RefreshOutcome outcome;
    try {
      outcome = await (refresh != null ? refresh() : fromServer(sync!));
    } catch (_) {
      outcome = RefreshOutcome.failed;
    }
    if (!context.mounted) return;
    RefreshNotice.show(
      context,
      messages[outcome]!,
      isError: outcome != RefreshOutcome.refreshed,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: () => _refresh(context),
      color: theme.colorScheme.primary,
      backgroundColor: context.glass.surfaceStrong,
      child: child,
    );
  }
}

/// The short notice shown where the refresh spinner was.
///
/// Only one is ever on screen: showing another replaces it, so refreshing
/// twice quickly cannot stack notices.
class RefreshNotice {
  const RefreshNotice._();

  static OverlayEntry? _entry;

  /// Shows [message] at the top of the area [context] occupies.
  static void show(
    BuildContext context,
    String message, {
    bool isError = false,
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    dismiss();

    // Same place the spinner came down from: the top edge of the page area.
    final box = context.findRenderObject();
    final top = box is RenderBox && box.hasSize
        ? box.localToGlobal(Offset.zero).dy
        : MediaQuery.paddingOf(context).top;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned(
        top: top + 12,
        left: 24,
        right: 24,
        child: _NoticePill(
          message: message,
          isError: isError,
          onDone: () {
            if (_entry == entry) _entry = null;
            if (entry.mounted) entry.remove();
          },
        ),
      ),
    );
    _entry = entry;
    overlay.insert(entry);
  }

  static void dismiss() {
    final entry = _entry;
    _entry = null;
    if (entry != null && entry.mounted) entry.remove();
  }
}

class _NoticePill extends StatefulWidget {
  const _NoticePill({
    required this.message,
    required this.isError,
    required this.onDone,
  });

  final String message;
  final bool isError;
  final VoidCallback onDone;

  @override
  State<_NoticePill> createState() => _NoticePillState();
}

class _NoticePillState extends State<_NoticePill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    // Errors stay a little longer: they are the ones that need reading.
    _timer = Timer(Duration(milliseconds: widget.isError ? 3200 : 2000), () {
      if (!mounted) return;
      _controller.reverse().whenComplete(widget.onDone);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    final accent = widget.isError ? glass.danger : glass.success;
    final curved = CurvedAnimation(parent: _controller, curve: Curves.easeOut);

    return IgnorePointer(
      child: FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -0.4),
            end: Offset.zero,
          ).animate(curved),
          child: Align(
            alignment: Alignment.topCenter,
            child: Semantics(
              liveRegion: true,
              child: Material(
                color: glass.surfaceStrong,
                elevation: 3,
                shadowColor: Colors.black26,
                shape: StadiumBorder(
                  side: BorderSide(color: glass.border.withValues(alpha: 0.6)),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        widget.isError
                            ? Icons.error_outline_rounded
                            : Icons.check_circle_rounded,
                        size: 16,
                        color: accent,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          widget.message,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
