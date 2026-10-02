import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_l10n.dart';
import '../../core/router/route_paths.dart';
import '../../providers/app_settings_provider.dart';
import '../../services/app_images.dart';

/// One slide of the introduction: a picture for the disc, and the feature
/// it stands for in a headline and a line.
@immutable
class IntroPicture {
  const IntroPicture({
    required this.imageId,
    required this.title,
    required this.titleNe,
    required this.body,
    required this.bodyNe,
    required this.label,
    required this.labelNe,
    required this.fallback,
  });

  /// Cloudinary public id.
  final String imageId;

  /// The feature, in two short lines.
  final String title;
  final String titleNe;

  /// What it does for the user, in a sentence.
  final String body;
  final String bodyNe;

  /// What the picture shows, for a screen reader.
  final String label;
  final String labelNe;

  /// Stands in when the picture cannot be fetched (a first launch offline).
  final IconData fallback;

  /// The picture cut out of its background and trimmed to its own edges, so
  /// that it stands on the disc, served as WebP/AVIF at a phone-sized width.
  String get url =>
      'https://res.cloudinary.com/dh3rzo7bt/image/upload/'
      'e_background_removal/e_trim/f_auto,q_auto,w_720/$imageId.png';
}

/// The first thing a new user sees: one page, not a walk-through.
///
/// A carousel of the app's features: each slide is a picture on a glass disc
/// in a warm glow, with the feature it shows named under it. The slides
/// change by themselves and can be swiped. Under them, always in the same
/// place, are the two ways on: create an account, or sign in. It is dark
/// whatever the theme, like a title card.
class IntroductionScreen extends StatefulWidget {
  const IntroductionScreen({super.key});

  /// The slides, in the order they are shown: what the app is for, then
  /// one feature each.
  static const List<IntroPicture> pictures = <IntroPicture>[
    IntroPicture(
      imageId: 'kharcha/intro/wallet',
      title: 'Know Where\nYour Money Goes',
      titleNe: 'तपाईंको पैसा\nकहाँ जान्छ, थाहा पाउनुहोस्',
      body:
          'Track spending, budgets and festivals, in your own calendar and '
          'language',
      bodyNe: 'खर्च, बजेट र चाडपर्व, तपाईंकै पात्रो र भाषामा',
      label: 'A wallet with coins and a receipt',
      labelNe: 'सिक्का र रसिदसहितको वालेट',
      fallback: Icons.account_balance_wallet_rounded,
    ),
    IntroPicture(
      imageId: 'qiwpmjgzfclytnrv5tgh',
      title: 'Record Every\nExpense in Seconds',
      titleNe: 'हरेक खर्च\nसेकेन्डमै लेख्नुहोस्',
      body:
          'Type it, or import it from your bank statement and payment '
          'messages',
      bodyNe: 'आफैँ लेख्नुहोस्, वा बैंक स्टेटमेन्ट र सन्देशबाट आयात गर्नुहोस्',
      label: 'Flamey holding a phone with a list of expenses',
      labelNe: 'खर्चको सूची भएको फोन समातेको Flamey',
      fallback: Icons.receipt_long_rounded,
    ),
    IntroPicture(
      imageId: 'stwv5wtm46f3pfjftb13',
      title: 'Budgets and\nSavings Goals',
      titleNe: 'बजेट र\nबचत लक्ष्य',
      body:
          'Set limits by month, category or festival, and put money aside '
          'for what matters',
      bodyNe: 'महिना, श्रेणी वा चाडपर्व अनुसार सीमा, र चाहिने कुराका लागि बचत',
      label: 'Flamey between a spending chart and a piggy bank',
      labelNe: 'खर्चको चार्ट र खुत्रुकेबीच Flamey',
      fallback: Icons.pie_chart_rounded,
    ),
    IntroPicture(
      imageId: 'b3qorzldimac95asnxng',
      title: 'Share Costs with\nFriends and Family',
      titleNe: 'साथी र परिवारसँग\nखर्च बाँड्नुहोस्',
      body:
          'Split a bill, keep a tab at the pasal, and run one ledger for the '
          'household',
      bodyNe: 'बिल बाँड्नुहोस्, पसलको उधारो राख्नुहोस्, र घरको एउटै खाता चलाउनुहोस्',
      label: 'Friends sharing momo and splitting the bill',
      labelNe: 'मम खाँदै बिल बाँड्दै गरेका साथीहरू',
      fallback: Icons.people_alt_rounded,
    ),
    IntroPicture(
      imageId: 'yhq42j7ar5npx5ncybxx',
      title: 'Works Offline,\nSyncs Safely',
      titleNe: 'अफलाइन चल्छ,\nसुरक्षित सिङ्क हुन्छ',
      body:
          'Everything is saved on your phone first and backed up to your '
          'account',
      bodyNe: 'सबै कुरा पहिले फोनमै सुरक्षित हुन्छ र खातामा ब्याकअप हुन्छ',
      label: 'Flamey holding a phone with a lock, under a syncing cloud',
      labelNe: 'सिङ्क हुँदै गरेको क्लाउडमुनि ताल्चा भएको फोन समातेको Flamey',
      fallback: Icons.cloud_sync_rounded,
    ),
  ];

  /// Where the pictures are fetched from. Also read by the image preloader.
  static List<String> get pictureUrls => <String>[
    for (final picture in pictures) picture.url,
  ];

  /// How long each picture stays before the next one slides in.
  static const Duration pictureInterval = Duration(seconds: 4);

  static const Color _accent = Color(0xFFF07F13);
  static const Color _accentDeep = Color(0xFFD9650A);

  @override
  State<IntroductionScreen> createState() => _IntroductionScreenState();
}

class _IntroductionScreenState extends State<IntroductionScreen> {
  final PageController _pictures = PageController();

  /// Which picture is on the disc, for the dots under the words.
  final ValueNotifier<int> _shown = ValueNotifier<int>(0);
  Timer? _turn;

  static const Color _accent = IntroductionScreen._accent;

  @override
  void initState() {
    super.initState();
    _turn = Timer.periodic(IntroductionScreen.pictureInterval, (_) {
      if (!_pictures.hasClients) return;
      final next = (_shown.value + 1) % IntroductionScreen.pictures.length;
      _pictures.animateToPage(
        next,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _turn?.cancel();
    _pictures.dispose();
    _shown.dispose();
    super.dispose();
  }

  /// Someone who swipes is choosing what to look at: the pictures stop
  /// changing under their finger.
  bool _onScroll(ScrollNotification notification) {
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _turn?.cancel();
      _turn = null;
    }
    return false;
  }

  /// Marks the introduction as seen and goes to [route].
  Future<void> _leave(BuildContext context, String route) async {
    // Read before the wait: once the introduction is marked as seen the page
    // under this one becomes the sign-in page and this context may be gone.
    final navigator = Navigator.of(context);
    await context.read<AppSettingsProvider>().markIntroductionSeen();
    // Push (not replace) so the root route stays in the stack and can still
    // hand the user back to the sign-in page after a sign-out.
    navigator.pushNamed(route);
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF2E2A2B),
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                Color(0xFF3B3431),
                Color(0xFF2C2A33),
                Color(0xFF3A3836),
              ],
              stops: <double>[0, 0.6, 1],
            ),
          ),
          child: SafeArea(
            // Very large text would push the buttons off a small phone.
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.2,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final words = _words(context);
                  final hero = NotificationListener<ScrollNotification>(
                    onNotification: _onScroll,
                    child: _Hero(
                      controller: _pictures,
                      onChanged: (index) => _shown.value = index,
                    ),
                  );
                  const padding = EdgeInsets.fromLTRB(24, 8, 24, 20);
                  // On a phone of ordinary height the picture takes whatever
                  // the words leave. On a very short one it keeps a small
                  // fixed size and the page scrolls, rather than the buttons
                  // running off the bottom.
                  if (constraints.maxHeight >= _roomyHeight) {
                    return Padding(
                      padding: padding,
                      child: Column(
                        children: <Widget>[
                          Expanded(child: hero),
                          ...words,
                        ],
                      ),
                    );
                  }
                  return SingleChildScrollView(
                    padding: padding,
                    child: Column(
                      children: <Widget>[
                        SizedBox(height: 180, child: hero),
                        ...words,
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The least height at which the picture and the words fit without
  /// scrolling.
  static const double _roomyHeight = 560;

  /// Everything under the picture.
  List<Widget> _words(BuildContext context) {
    final theme = Theme.of(context);
    return <Widget>[
      const SizedBox(height: 20),
      // Every slide's words are laid out, and only the shown one is drawn:
      // the block is as tall as the tallest, so the buttons under it never
      // move as the slides turn.
      ValueListenableBuilder<int>(
        valueListenable: _shown,
        builder: (context, shown, _) => IndexedStack(
          index: shown,
          alignment: Alignment.topCenter,
          children: <Widget>[
            for (final slide in IntroductionScreen.pictures)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    context.t(slide.title, slide.titleNe),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    context.t(slide.body, slide.bodyNe),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: Colors.white.withValues(alpha: 0.78),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
      const SizedBox(height: 22),
      ValueListenableBuilder<int>(
        valueListenable: _shown,
        builder: (context, shown, _) => _Ornament(color: _accent, shown: shown),
      ),
      const SizedBox(height: 22),
      _GetStartedButton(
        label: context.t('Get started', 'सुरु गर्नुहोस्'),
        onPressed: () => _leave(context, RoutePaths.signup),
      ),
      const SizedBox(height: 12),
      // The second way on, in glass: the same width and shape as the first,
      // without competing with it.
      SizedBox(
        width: double.infinity,
        height: 52,
        child: OutlinedButton(
          key: const ValueKey<String>('intro-login'),
          onPressed: () => _leave(context, RoutePaths.login),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: Colors.white.withValues(alpha: 0.08),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.28)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
          ),
          child: Text(
            context.t('Login', 'लगइन'),
            style: theme.textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    ];
  }
}

/// The pictures on their glass disc, lit from behind. The glow and the disc
/// stay still; only the picture standing on the disc slides.
class _Hero extends StatelessWidget {
  const _Hero({required this.controller, required this.onChanged});

  final PageController controller;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // As large as the space allows, and never wider than it is tall, so
        // a short phone gets a smaller picture rather than a cropped one.
        final size = constraints.biggest.shortestSide;
        final discWidth = size * 0.94;
        final discHeight = discWidth * 0.26;
        // A little below the middle of the space, close to the words.
        return Align(
          alignment: const Alignment(0, 0.5),
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.bottomCenter,
              clipBehavior: Clip.none,
              children: <Widget>[
                // The warm light behind the picture.
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        // Gone before it reaches the edge of its box, so
                        // the light never shows a straight edge.
                        radius: 0.5,
                        colors: <Color>[
                          const Color(0xFFE9A77C).withValues(alpha: 0.62),
                          const Color(0xFFE9A77C).withValues(alpha: 0.2),
                          Colors.transparent,
                        ],
                        stops: const <double>[0, 0.5, 0.95],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: size * 0.04,
                  child: CustomPaint(
                    size: Size(discWidth, discHeight),
                    painter: const _GlassDiscPainter(),
                  ),
                ),
                // Standing on the disc: its foot is a little above the
                // disc's middle. As wide as the space, so a swipe anywhere
                // across the picture turns it.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: size * 0.04 + discHeight * 0.42,
                  height: size * 0.66,
                  child: PageView.builder(
                    key: const ValueKey<String>('intro-pictures'),
                    controller: controller,
                    onPageChanged: onChanged,
                    itemCount: IntroductionScreen.pictures.length,
                    itemBuilder: (context, index) {
                      final picture = IntroductionScreen.pictures[index];
                      return Image(
                        image: AppImages.provider(picture.url),
                        fit: BoxFit.contain,
                        alignment: Alignment.bottomCenter,
                        semanticLabel: context.t(
                          picture.label,
                          picture.labelNe,
                        ),
                        frameBuilder: (context, child, frame, sync) =>
                            AnimatedOpacity(
                              opacity: sync || frame != null ? 1 : 0,
                              duration: const Duration(milliseconds: 300),
                              child: child,
                            ),
                        // The first launch can be offline: an icon stands in.
                        errorBuilder: (_, _, _) => Align(
                          alignment: Alignment.bottomCenter,
                          child: Icon(
                            picture.fallback,
                            size: size * 0.42,
                            color: const Color(0xFFE9A77C),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A round sheet of glass seen from a little above: a faint fill, a bright
/// near edge, and a second line under it for the glass's thickness.
class _GlassDiscPainter extends CustomPainter {
  const _GlassDiscPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const thickness = 5.0;
    final top = Rect.fromLTWH(0, 0, size.width, size.height - thickness);
    final under = top.shift(const Offset(0, thickness));

    canvas.drawOval(
      under,
      Paint()..color = Colors.white.withValues(alpha: 0.10),
    );
    canvas.drawOval(
      under,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.28),
    );
    canvas.drawOval(
      top,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0x52857C86), Color(0x66665F6B)],
        ).createShader(top),
    );
    canvas.drawOval(
      top,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0x40FFFFFF), Color(0xD9FFFFFF)],
        ).createShader(top),
    );
    // Where the picture stands: a soft shadow, so it sits on the glass
    // rather than floating over it.
    canvas.drawOval(
      Rect.fromCenter(
        center: top.center.translate(0, -top.height * 0.04),
        width: top.width * 0.5,
        height: top.height * 0.42,
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Dots on a line, under the words: one for each slide, the one for the
/// slide being shown lit and a little larger.
class _Ornament extends StatelessWidget {
  const _Ornament({required this.color, required this.shown});

  final Color color;
  final int shown;

  @override
  Widget build(BuildContext context) {
    final faint = color.withValues(alpha: 0.4);
    Widget dot(int index) => SizedBox(
      width: 10,
      height: 10,
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: index == shown ? 10 : 7,
          height: index == shown ? 10 : 7,
          decoration: BoxDecoration(
            color: index == shown ? color : faint,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
    Widget line() => Container(width: 12, height: 2, color: faint);
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (var i = 0; i < IntroductionScreen.pictures.length; i++) ...[
            if (i > 0) line(),
            dot(i),
          ],
        ],
      ),
    );
  }
}

/// The wide orange button.
class _GetStartedButton extends StatelessWidget {
  const _GetStartedButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(28);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            IntroductionScreen._accent,
            IntroductionScreen._accentDeep,
          ],
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: IntroductionScreen._accentDeep.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: const ValueKey<String>('intro-get-started'),
          borderRadius: radius,
          onTap: onPressed,
          child: SizedBox(
            width: double.infinity,
            height: 56,
            child: Center(
              child: Text(
                label,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
