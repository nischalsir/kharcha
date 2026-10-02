import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../models/financial_summary.dart';
import '../../models/sync_models.dart';
import '../../services/sync_service.dart';
import 'flame_mascot.dart';

/// How a pull-to-refresh ended.
enum RefreshOutcome { refreshed, offline, failed }

/// Pull-to-refresh for a whole page, with the same feedback everywhere.
///
/// Pulling brings Flamey down on a small glass disc at the top of the page,
/// where it pulls a new face every beat until the refresh is over. When the
/// refresh has actually finished, that same disc widens into a pill naming
/// the page, "Home page refreshed", and Flamey comes to rest on one reaction.
/// A refresh that did not work says so instead; it is never reported as a
/// success.
///
/// [child] must be the page's vertical scrollable, built with
/// [AlwaysScrollableScrollPhysics] so a page too short to scroll can still be
/// pulled.
class PageRefresh extends StatefulWidget {
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

  /// The reactions Flamey may come to rest on when the refresh worked.
  static const List<MoodFace> pleased = <MoodFace>[
    MoodFace.happy,
    MoodFace.proud,
    MoodFace.cool,
    MoodFace.wink,
    MoodFace.party,
    MoodFace.love,
    MoodFace.excited,
    MoodFace.yum,
    MoodFace.starstruck,
  ];

  /// And when it did not.
  static const List<MoodFace> sorry = <MoodFace>[
    MoodFace.worried,
    MoodFace.sad,
    MoodFace.confused,
    MoodFace.dizzy,
    MoodFace.crying,
  ];

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

  @override
  State<PageRefresh> createState() => _PageRefreshState();
}

class _PageRefreshState extends State<PageRefresh> {
  static final math.Random _random = math.Random();

  RefreshIndicatorStatus? _status;

  /// What the pill says once a refresh is over. It keeps its words while it
  /// slides away, so [_noticeUp] says whether it is on show.
  String? _notice;
  bool _noticeUp = false;
  bool _noticeIsError = false;

  /// The reaction Flamey came to rest on.
  MoodFace _rest = MoodFace.happy;
  Timer? _noticeTimer;

  @override
  void dispose() {
    _noticeTimer?.cancel();
    super.dispose();
  }

  void _onStatus(RefreshIndicatorStatus? status) {
    void apply() {
      if (mounted && _status != status) setState(() => _status = status);
    }

    // The indicator can report while the page is being laid out.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => apply());
    } else {
      apply();
    }
  }

  Future<void> _refresh() async {
    final refresh = widget.onRefresh;
    final sync = refresh == null ? context.read<SyncService>() : null;
    final pageName = widget.pageName;
    final pageNameNe = widget.pageNameNe;
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

    // The last refresh's notice makes way: the pill is a disc again while
    // this one runs, so two refreshes can never stack two notices.
    _noticeTimer?.cancel();
    if (_notice != null) {
      setState(() {
        _notice = null;
        _noticeUp = false;
      });
    }

    RefreshOutcome outcome;
    try {
      outcome = await (refresh != null
          ? refresh()
          : PageRefresh.fromServer(sync!));
    } catch (_) {
      outcome = RefreshOutcome.failed;
    }
    if (!mounted) return;

    final worked = outcome == RefreshOutcome.refreshed;
    final faces = worked ? PageRefresh.pleased : PageRefresh.sorry;
    setState(() {
      _notice = messages[outcome];
      _noticeUp = true;
      _noticeIsError = !worked;
      _rest = faces[_random.nextInt(faces.length)];
    });
    // Errors stay a little longer: they are the ones that need reading.
    _noticeTimer = Timer(Duration(milliseconds: worked ? 2200 : 3400), () {
      if (mounted) setState(() => _noticeUp = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final working =
        _status == RefreshIndicatorStatus.snap ||
        _status == RefreshIndicatorStatus.refresh;
    final pulling =
        _status == RefreshIndicatorStatus.drag ||
        _status == RefreshIndicatorStatus.armed;

    return Stack(
      children: <Widget>[
        RefreshIndicator.noSpinner(
          onRefresh: _refresh,
          onStatusChange: _onStatus,
          child: widget.child,
        ),
        Positioned(
          top: 12,
          left: 24,
          right: 24,
          child: IgnorePointer(
            child: Center(
              child: _RefreshPill(
                shown: working || pulling || _noticeUp,
                notice: _notice,
                isError: _noticeIsError,
                small: _status == RefreshIndicatorStatus.drag && !_noticeUp,
                // Resting on one reaction once it is over, going through
                // them while it runs, watching while the page is pulled.
                hold: _notice != null
                    ? _rest
                    : working
                    ? null
                    : _status == RefreshIndicatorStatus.armed
                    ? MoodFace.excited
                    : MoodFace.calm,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Flamey on a glass disc where the refresh spinner used to be, which widens
/// into a pill to say how the refresh went.
class _RefreshPill extends StatefulWidget {
  const _RefreshPill({
    required this.shown,
    required this.hold,
    required this.notice,
    required this.isError,
    required this.small,
  });

  final bool shown;

  /// The face Flamey stays on; null while it goes through them.
  final MoodFace? hold;
  final String? notice;
  final bool isError;

  /// Slightly smaller while the page has not been pulled far enough yet.
  final bool small;

  @override
  State<_RefreshPill> createState() => _RefreshPillState();
}

class _RefreshPillState extends State<_RefreshPill> {
  static const double _disc = 46;

  /// Flamey is only built while the pill can be seen. It animates for as
  /// long as it exists, and a page must not keep repainting for a pill that
  /// is out of sight.
  late bool _present = widget.shown;

  @override
  void didUpdateWidget(_RefreshPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.shown) _present = true;
  }

  void _gone() {
    if (!widget.shown && _present && mounted) {
      setState(() => _present = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    final still = MediaQuery.disableAnimationsOf(context);
    final duration = still ? Duration.zero : const Duration(milliseconds: 200);
    final notice = widget.notice;
    // With no animation there is no end of one to wait for.
    final present = still ? widget.shown : _present;

    return AnimatedSlide(
      offset: widget.shown ? Offset.zero : const Offset(0, -1.6),
      duration: duration,
      curve: Curves.easeOut,
      onEnd: _gone,
      child: AnimatedOpacity(
        opacity: widget.shown ? 1 : 0,
        duration: duration,
        child: AnimatedScale(
          scale: widget.small ? 0.82 : 1,
          duration: duration,
          child: Material(
            key: const ValueKey<String>('refresh-flamey'),
            color: glass.surfaceStrong,
            elevation: 3,
            shadowColor: Colors.black26,
            clipBehavior: Clip.antiAlias,
            shape: StadiumBorder(
              side: BorderSide(
                color:
                    (notice != null && widget.isError
                            ? glass.danger
                            : glass.border)
                        .withValues(alpha: 0.6),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SizedBox(
                  width: _disc,
                  height: _disc,
                  child: Center(
                    child: present
                        ? BusyFlamey(size: 30, hold: widget.hold)
                        : null,
                  ),
                ),
                Flexible(
                  child: AnimatedSize(
                    duration: still
                        ? Duration.zero
                        : const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.centerLeft,
                    // The words go with Flamey once the pill is out of sight.
                    child: notice == null || !present
                        ? const SizedBox(height: _disc)
                        : Padding(
                            padding: const EdgeInsets.only(right: 16),
                            child: Semantics(
                              liveRegion: true,
                              child: Text(
                                notice,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: theme.colorScheme.onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
