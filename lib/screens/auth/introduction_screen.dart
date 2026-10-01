import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_l10n.dart';
import '../../core/router/route_paths.dart';
import '../../providers/app_settings_provider.dart';
import '../../services/app_images.dart';

/// The first thing a new user sees: one page, not a walk-through.
///
/// A picture standing on a glass disc in a warm glow, what the app is for in
/// two lines, and the two ways on: create an account, or sign in. It is dark
/// whatever the theme, like a title card.
class IntroductionScreen extends StatelessWidget {
  const IntroductionScreen({super.key});

  /// Cloudinary public id of the picture on the disc.
  static const String heroImageId = 'kharcha/intro/wallet';

  /// The picture, cut out of its background and trimmed to its own edges so
  /// that it stands on the disc, served as WebP/AVIF at a phone-sized width.
  /// Also read by the image preloader.
  static const String heroImageUrl =
      'https://res.cloudinary.com/dh3rzo7bt/image/upload/'
      'e_background_removal/e_trim/f_auto,q_auto,w_720/$heroImageId.png';

  static const Color _accent = Color(0xFFF07F13);
  static const Color _accentDeep = Color(0xFFD9650A);

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
                          const Expanded(child: _Hero()),
                          ...words,
                        ],
                      ),
                    );
                  }
                  return SingleChildScrollView(
                    padding: padding,
                    child: Column(
                      children: <Widget>[
                        const SizedBox(height: 180, child: _Hero()),
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
      Text(
        context.t(
          'Know Where\nYour Money Goes',
          'तपाईंको पैसा\nकहाँ जान्छ, थाहा पाउनुहोस्',
        ),
        textAlign: TextAlign.center,
        style: theme.textTheme.headlineMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          height: 1.2,
        ),
      ),
      const SizedBox(height: 12),
      Text(
        context.t(
          'Track spending, budgets and festivals, in your own calendar and '
              'language',
          'खर्च, बजेट र चाडपर्व, तपाईंकै पात्रो र भाषामा',
        ),
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: Colors.white.withValues(alpha: 0.78),
          height: 1.4,
        ),
      ),
      const SizedBox(height: 22),
      const _Ornament(color: _accent),
      const SizedBox(height: 22),
      _GetStartedButton(
        label: context.t('Get started', 'सुरु गर्नुहोस्'),
        onPressed: () => _leave(context, RoutePaths.signup),
      ),
      const SizedBox(height: 6),
      TextButton(
        key: const ValueKey<String>('intro-login'),
        onPressed: () => _leave(context, RoutePaths.login),
        child: Text(
          context.t('Login', 'लगइन'),
          style: theme.textTheme.titleMedium?.copyWith(
            color: Colors.white,
            decoration: TextDecoration.underline,
            decorationColor: Colors.white70,
          ),
        ),
      ),
    ];
  }
}

/// The picture on its glass disc, lit from behind.
class _Hero extends StatelessWidget {
  const _Hero();

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
                // disc's middle.
                Positioned(
                  bottom: size * 0.04 + discHeight * 0.42,
                  child: Image(
                    image: AppImages.provider(IntroductionScreen.heroImageUrl),
                    width: size * 0.66,
                    height: size * 0.66,
                    fit: BoxFit.contain,
                    alignment: Alignment.bottomCenter,
                    semanticLabel: context.t(
                      'A wallet with coins and a receipt',
                      'सिक्का र रसिदसहितको वालेट',
                    ),
                    frameBuilder: (context, child, frame, sync) =>
                        AnimatedOpacity(
                          opacity: sync || frame != null ? 1 : 0,
                          duration: const Duration(milliseconds: 300),
                          child: child,
                        ),
                    // The first launch can be offline: an icon stands in.
                    errorBuilder: (_, _, _) => SizedBox(
                      width: size * 0.66,
                      height: size * 0.66,
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Icon(
                          Icons.account_balance_wallet_rounded,
                          size: size * 0.42,
                          color: const Color(0xFF5E8A5A),
                        ),
                      ),
                    ),
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

/// Three dots on a line, under the words.
class _Ornament extends StatelessWidget {
  const _Ornament({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    Widget dot() => Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
    Widget line() => Container(width: 12, height: 2, color: color);
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[dot(), line(), dot(), line(), dot()],
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
