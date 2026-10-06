import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../models/financial_summary.dart';
import '../../providers/app_settings_provider.dart';
import '../../widgets/common/flame_mascot.dart';
import '../../widgets/common/glass_background.dart';
import '../../widgets/common/glass_card.dart';
import '../../widgets/common/pressable_scale.dart';
import '../../widgets/common/primary_button.dart';

/// One page of the tour: a picture, a few words, nothing to do but read.
class TutorialPage {
  const TutorialPage({
    required this.icon,
    required this.color,
    required this.face,
    required this.title,
    required this.titleNe,
    required this.body,
    required this.bodyNe,
    this.chips = const <(IconData, String, String)>[],
  });

  /// What the page is about, drawn large on a glass disc.
  final IconData icon;
  final Color color;

  /// How Flamey looks beside it.
  final MoodFace face;
  final String title;
  final String titleNe;
  final String body;
  final String bodyNe;

  /// Small labelled marks floating around the picture: icon, English, Nepali.
  final List<(IconData, String, String)> chips;
}

/// The tour a new person is given the first time they open Kharcha: what the
/// main parts of the app are, one page each.
///
/// It is shown once per installation (see `AppSettingsProvider`), before
/// signing in on a fresh install, or on first entering as a guest. Every
/// page can be skipped, and where someone had got to is remembered if the
/// app is closed halfway.
class TutorialScreen extends StatefulWidget {
  const TutorialScreen({super.key, this.onFinished});

  /// Called after the tour has been completed or skipped and that has been
  /// saved. The page that shows the tour decides what comes next.
  final VoidCallback? onFinished;

  static const List<TutorialPage> pages = <TutorialPage>[
    TutorialPage(
      icon: Icons.account_balance_wallet_rounded,
      color: Color(0xFFFF9F0A),
      face: MoodFace.excited,
      title: 'Welcome to Kharcha',
      titleNe: 'खर्चामा स्वागत छ',
      body:
          'Home shows this month at a glance: what came in, what went '
          'out, and what is left.',
      bodyNe:
          'होममा यो महिनाको सबै कुरा एकै नजरमा: कति आयो, कति गयो र '
          'कति बाँकी छ।',
      chips: <(IconData, String, String)>[
        (Icons.south_west_rounded, 'Income', 'आम्दानी'),
        (Icons.north_east_rounded, 'Spent', 'खर्च'),
      ],
    ),
    TutorialPage(
      icon: Icons.add_circle_rounded,
      color: Color(0xFF30D158),
      face: MoodFace.wink,
      title: 'Add it in seconds',
      titleNe: 'केही सेकेन्डमै थप्नुहोस्',
      body:
          'Tap + to add an expense or income. Pick a category, type the '
          'amount, done.',
      bodyNe:
          'खर्च वा आम्दानी थप्न + थिच्नुहोस्। श्रेणी छान्नुहोस्, रकम '
          'लेख्नुहोस्, सकियो।',
      chips: <(IconData, String, String)>[
        (Icons.remove_rounded, 'Expense', 'खर्च'),
        (Icons.add_rounded, 'Income', 'आम्दानी'),
      ],
    ),
    TutorialPage(
      icon: Icons.donut_small_rounded,
      color: Color(0xFF0A84FF),
      face: MoodFace.proud,
      title: 'Budgets that warn you',
      titleNe: 'सचेत गराउने बजेट',
      body:
          'Give your month, or a category like Food, a budget. Kharcha '
          'tells you before you go past it.',
      bodyNe:
          'महिना वा खाना जस्तो श्रेणीलाई बजेट दिनुहोस्। नाघ्नुअघि नै '
          'खर्चाले बताउँछ।',
      chips: <(IconData, String, String)>[
        (Icons.category_rounded, 'Categories', 'श्रेणी'),
        (Icons.flag_rounded, 'Goals', 'लक्ष्य'),
      ],
    ),
    TutorialPage(
      icon: Icons.groups_rounded,
      color: Color(0xFFBF5AF2),
      face: MoodFace.love,
      title: 'Friends and credit',
      titleNe: 'साथी र उधारो',
      body:
          'Keep track of who owes whom, split a bill, and settle up when '
          'it is paid.',
      bodyNe:
          'कसले कसलाई कति तिर्नुपर्छ हेर्नुहोस्, बिल बाँड्नुहोस् र तिरेपछि '
          'हिसाब मिलाउनुहोस्।',
      chips: <(IconData, String, String)>[
        (Icons.call_split_rounded, 'Split a bill', 'बिल बाँड्नुहोस्'),
      ],
    ),
    TutorialPage(
      icon: Icons.storefront_rounded,
      color: Color(0xFF64D2FF),
      face: MoodFace.curious,
      title: 'Pasal',
      titleNe: 'पसल',
      body:
          'A tab for each shop: what you took on credit, what you have '
          'paid, and what is still due.',
      bodyNe:
          'हरेक पसलको खाता: उधारोमा के लिनुभयो, कति तिर्नुभयो र कति '
          'बाँकी छ।',
      chips: <(IconData, String, String)>[
        (Icons.receipt_long_rounded, 'Credit', 'उधारो'),
        (Icons.payments_rounded, 'Paid', 'तिरेको'),
      ],
    ),
    TutorialPage(
      icon: Icons.upload_file_rounded,
      color: Color(0xFF5E5CE6),
      face: MoodFace.thinking,
      title: 'Import instead of typing',
      titleNe: 'टाइप नगरी आयात गर्नुहोस्',
      body:
          'Bring in a bank, eSewa or Khalti statement, or your payment '
          'SMS, and choose what to keep.',
      bodyNe:
          'बैंक, eSewa वा Khalti को स्टेटमेन्ट, वा भुक्तानीका SMS ल्याउनुहोस् '
          'र राख्ने कुरा छान्नुहोस्।',
      chips: <(IconData, String, String)>[
        (Icons.account_balance_rounded, 'Statement', 'स्टेटमेन्ट'),
        (Icons.sms_rounded, 'SMS', 'SMS'),
      ],
    ),
    TutorialPage(
      icon: Icons.auto_awesome_rounded,
      color: Color(0xFFFF453A),
      face: MoodFace.roasting,
      title: 'Meet Flamey',
      titleNe: 'Flamey लाई भेट्नुहोस्',
      body:
          'Flamey reads your spending, suggests what to do about it, and '
          'roasts you a little when you earn it.',
      bodyNe:
          'Flamey ले तपाईंको खर्च हेर्छ, के गर्ने सुझाउँछ र चाहिएको बेला '
          'अलिकति जिस्क्याउँछ पनि।',
      chips: <(IconData, String, String)>[
        (Icons.lightbulb_rounded, 'Suggestions', 'सुझाव'),
      ],
    ),
    TutorialPage(
      icon: Icons.cloud_done_rounded,
      color: Color(0xFF30D158),
      face: MoodFace.cool,
      title: 'Yours, and safe',
      titleNe: 'तपाईंको, र सुरक्षित',
      body:
          'Sign in to back up and sync across phones, or explore as a '
          'guest and keep everything on this phone. What Kharcha may '
          'use is yours to choose in Settings.',
      bodyNe:
          'ब्याकअप र अरू फोनमा सिङ्क गर्न साइन इन गर्नुहोस्, वा पाहुनाको '
          'रूपमा हेर्नुहोस् र सबै कुरा यही फोनमा राख्नुहोस्। खर्चाले के '
          'प्रयोग गर्न पाउँछ भन्ने सेटिङमा तपाईंले नै रोज्नुहुन्छ।',
      chips: <(IconData, String, String)>[
        (Icons.lock_rounded, 'Private', 'निजी'),
        (Icons.sync_rounded, 'Sync', 'सिङ्क'),
      ],
    ),
  ];

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  late final PageController _controller;
  late int _page;
  bool _leaving = false;

  static const Duration _turn = Duration(milliseconds: 320);

  int get _last => TutorialScreen.pages.length - 1;

  @override
  void initState() {
    super.initState();
    // Someone who closed the app halfway carries on from where they were.
    final saved = context.read<AppSettingsProvider>().tutorialPage;
    _page = saved.clamp(0, _last);
    _controller = PageController(initialPage: _page);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onPage(int index) {
    setState(() => _page = index);
    context.read<AppSettingsProvider>().saveTutorialProgress(index);
  }

  void _go(int index) {
    final target = index.clamp(0, _last);
    // With reduced motion the page changes at once instead of sliding.
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.jumpToPage(target);
      return;
    }
    _controller.animateToPage(
      target,
      duration: _turn,
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _finish({required bool skipped}) async {
    if (_leaving) return;
    setState(() => _leaving = true);
    await context.read<AppSettingsProvider>().finishTutorial(skipped: skipped);
    if (mounted) widget.onFinished?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    final onLast = _page == _last;

    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          // Very large text would push the buttons off a small phone.
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.2,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                children: <Widget>[
                  // Skip: always there, never the loudest thing on the page.
                  SizedBox(
                    height: 44,
                    child: Row(
                      children: <Widget>[
                        Text(
                          '${_page + 1} / ${TutorialScreen.pages.length}',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: glass.textSecondary,
                          ),
                        ),
                        const Spacer(),
                        if (!onLast)
                          TextButton(
                            key: const ValueKey<String>('tutorial-skip'),
                            onPressed: _leaving
                                ? null
                                : () => _finish(skipped: true),
                            style: TextButton.styleFrom(
                              foregroundColor: glass.textSecondary,
                              minimumSize: const Size(64, 44),
                            ),
                            child: Text(context.t('Skip', 'छोड्नुहोस्')),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: PageView.builder(
                      key: const ValueKey<String>('tutorial-pages'),
                      controller: _controller,
                      onPageChanged: _onPage,
                      itemCount: TutorialScreen.pages.length,
                      itemBuilder: (context, index) => _PageView(
                        page: TutorialScreen.pages[index],
                        shown: index == _page,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _Dots(count: TutorialScreen.pages.length, shown: _page),
                  const SizedBox(height: 18),
                  Row(
                    children: <Widget>[
                      // Back takes its room even on the first page, so Next
                      // never jumps sideways.
                      SizedBox(
                        width: 96,
                        child: AnimatedOpacity(
                          opacity: _page == 0 ? 0 : 1,
                          duration: const Duration(milliseconds: 150),
                          child: IgnorePointer(
                            ignoring: _page == 0,
                            child: _BackButton(onPressed: () => _go(_page - 1)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: PrimaryButton(
                          key: const ValueKey<String>('tutorial-next'),
                          label: onLast
                              ? context.t(
                                  'Start using Kharcha',
                                  'खर्चा प्रयोग गर्न सुरु गर्नुहोस्',
                                )
                              : context.t('Next', 'अर्को'),
                          icon: onLast
                              ? Icons.check_rounded
                              : Icons.arrow_forward_rounded,
                          isLoading: _leaving,
                          onPressed: onLast
                              ? () => _finish(skipped: false)
                              : () => _go(_page + 1),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The quiet button beside Next.
class _BackButton extends StatelessWidget {
  const _BackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    return Semantics(
      button: true,
      child: PressableScale(
        key: const ValueKey<String>('tutorial-back'),
        onTap: onPressed,
        child: Container(
          height: 50,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: glass.fill,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: glass.border.withValues(alpha: 0.6)),
          ),
          child: Text(
            context.t('Back', 'पछाडि'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

/// A line of dots, one per page; the one for the page being read is a bar in
/// the app's accent.
class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.shown});

  final int count;
  final int shown;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final faint = context.glass.textTertiary.withValues(alpha: 0.5);
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == shown ? 22 : 7,
              height: 7,
              decoration: BoxDecoration(
                color: i == shown ? primary : faint,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
        ],
      ),
    );
  }
}

class _PageView extends StatelessWidget {
  const _PageView({required this.page, required this.shown});

  final TutorialPage page;

  /// Whether this is the page on screen; Flamey only moves on that one.
  final bool shown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    return LayoutBuilder(
      builder: (context, constraints) {
        final words = <Widget>[
          Text(
            context.t(page.title, page.titleNe),
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            context.t(page.body, page.bodyNe),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: glass.textSecondary,
              height: 1.4,
            ),
          ),
        ];
        // On a phone of ordinary height the picture takes what the words
        // leave; on a very short one the page scrolls instead of squeezing.
        if (constraints.maxHeight >= 360) {
          return Column(
            children: <Widget>[
              Expanded(
                child: _Visual(page: page, shown: shown),
              ),
              const SizedBox(height: 16),
              ...words,
            ],
          );
        }
        return SingleChildScrollView(
          child: Column(
            children: <Widget>[
              SizedBox(
                height: 200,
                child: _Visual(page: page, shown: shown),
              ),
              const SizedBox(height: 16),
              ...words,
            ],
          ),
        );
      },
    );
  }
}

/// The picture on a page: what it is about on a glass disc lit in its own
/// colour, Flamey beside it, and a couple of labels.
class _Visual extends StatelessWidget {
  const _Visual({required this.page, required this.shown});

  final TutorialPage page;
  final bool shown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.biggest.shortestSide.clamp(140.0, 320.0);
        final disc = side * 0.62;
        final flame = side * 0.34;

        Widget chip(int index) {
          final (icon, en, ne) = page.chips[index];
          return GlassCard(
            radius: 16,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, size: 15, color: page.color),
                const SizedBox(width: 6),
                Text(
                  context.t(en, ne),
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          );
        }

        return Center(
          child: SizedBox(
            width: side,
            height: side,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: <Widget>[
                // The colour behind the disc.
                Container(
                  width: side * 0.9,
                  height: side * 0.9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: <Color>[
                        page.color.withValues(alpha: 0.34),
                        page.color.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
                GlassCard(
                  radius: disc / 2,
                  padding: EdgeInsets.zero,
                  child: SizedBox(
                    width: disc,
                    height: disc,
                    child: Icon(page.icon, size: disc * 0.5, color: page.color),
                  ),
                ),
                Positioned(
                  right: side * 0.02,
                  bottom: side * 0.04,
                  // Only the page being read keeps its animation running.
                  child: MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      disableAnimations:
                          !shown || MediaQuery.disableAnimationsOf(context),
                    ),
                    child: FlameMascot(
                      face: page.face,
                      energy: 0.9,
                      size: flame,
                    ),
                  ),
                ),
                if (page.chips.isNotEmpty)
                  Positioned(left: 0, top: side * 0.1, child: chip(0)),
                if (page.chips.length > 1)
                  Positioned(
                    left: side * 0.02,
                    bottom: side * 0.1,
                    child: chip(1),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
