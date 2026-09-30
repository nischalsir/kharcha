import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/router/route_paths.dart';
import '../../providers/app_settings_provider.dart';
import '../../widgets/common/glass_background.dart';
import '../../widgets/common/primary_button.dart';

class IntroductionScreen extends StatefulWidget {
  const IntroductionScreen({super.key});

  @override
  State<IntroductionScreen> createState() => _IntroductionScreenState();
}

class _IntroductionScreenState extends State<IntroductionScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<OnboardingPage> _pages = [
    OnboardingPage(
      title: 'Track Every Expense',
      imageId: 'qiwpmjgzfclytnrv5tgh',
      description: 'Log your daily spending in seconds. Categorize expenses, add notes, and never wonder where your money went.',
      illustration: Icons.receipt_long_rounded,
      color: const Color(0xFF10B981),
    ),
    OnboardingPage(
      title: 'Smart Budgets',
      imageId: 'stwv5wtm46f3pfjftb13',
      description: 'Set monthly budgets per category. Get alerts before you overspend and visualize your spending patterns.',
      illustration: Icons.pie_chart_rounded,
      color: const Color(0xFF3B82F6),
    ),
    OnboardingPage(
      title: 'Split with Friends',
      imageId: 'b3qorzldimac95asnxng',
      description: 'Track shared expenses with friends and Pasal (group expenses). Settle up instantly with clear balances.',
      illustration: Icons.people_alt_rounded,
      color: const Color(0xFFF59E0B),
    ),
    OnboardingPage(
      title: 'Works Offline',
      imageId: 'yhq42j7ar5npx5ncybxx',
      description: 'Your data stays on your device. Sync securely with Supabase when online. Privacy first, always.',
      illustration: Icons.cloud_sync_rounded,
      color: const Color(0xFF8B5CF6),
    ),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Warm the first two slides so swiping never waits on the network.
    for (final page in _pages.take(2)) {
      precacheImage(NetworkImage(page.imageUrl), context, onError: (_, _) {});
    }
  }

  void _onPageChanged(int index) {
    setState(() => _currentPage = index);
    if (index + 1 < _pages.length) {
      precacheImage(
        NetworkImage(_pages[index + 1].imageUrl),
        context,
        onError: (_, _) {},
      );
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    } else {
      _completeOnboarding();
    }
  }

  void _completeOnboarding() async {
    await context.read<AppSettingsProvider>().markIntroductionSeen();
    if (mounted) {
      // Push (not replace) so the root `_AuthWrapper` route stays in the stack
      // and can still hand the user back to the login page after a sign-out.
      Navigator.of(context).pushNamed(RoutePaths.login);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              // Skip button
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextButton(
                    onPressed: _completeOnboarding,
                    child: Text(
                      'Skip',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
              // PageView
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _pages.length,
                  onPageChanged: _onPageChanged,
                  itemBuilder: (context, index) {
                    final page = _pages[index];
                    // Parallax: the illustration drifts and shrinks slightly as
                    // its page slides away. Driven by the controller, so it
                    // costs one transform per frame and no rebuild of the text.
                    return AnimatedBuilder(
                      animation: _pageController,
                      builder: (context, child) {
                        var offset = 0.0;
                        if (_pageController.hasClients &&
                            _pageController.position.haveDimensions) {
                          offset = (_pageController.page ?? 0) - index;
                        }
                        return _OnboardingPageContent(
                          page: page,
                          offset: offset.clamp(-1.0, 1.0),
                        );
                      },
                    );
                  },
                ),
              ),
              // Indicators and buttons
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                child: Column(
                  children: [
                    // Page indicators
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(_pages.length, (index) {
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: _currentPage == index ? 24 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _currentPage == index
                                ? _pages[_currentPage].color
                                : colorScheme.outline.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 32),
                    // Next/Get Started button
                    SizedBox(
                      width: double.infinity,
                      child: PrimaryButton(
                        label: _currentPage == _pages.length - 1
                            ? 'Get Started'
                            : 'Next',
                        onPressed: _nextPage,
                        color: _pages[_currentPage].color,
                      ),
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

class OnboardingPage {
  final String title;
  final String description;
  final IconData illustration;
  final Color color;

  /// Cloudinary public id of the slide's illustration.
  final String imageId;

  const OnboardingPage({
    required this.title,
    required this.description,
    required this.illustration,
    required this.color,
    required this.imageId,
  });

  /// Generated on a white canvas; background removal lets it sit on the glass
  /// background, and f_auto/q_auto serve WebP/AVIF at a phone-sized width.
  String get imageUrl =>
      'https://res.cloudinary.com/dh3rzo7bt/image/upload/'
      'e_background_removal/f_auto,q_auto,w_720/$imageId.png';
}

class _OnboardingPageContent extends StatelessWidget {
  const _OnboardingPageContent({required this.page, this.offset = 0});

  final OnboardingPage page;

  /// -1..1: how far this page is from being centred.
  final double offset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Illustration
          Transform.translate(
            offset: Offset(offset * -60, 0),
            child: Transform.scale(
              scale: 1 - offset.abs() * 0.12,
              child: SizedBox(
                width: 260,
                height: 260,
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    Container(
                      width: 220,
                      height: 220,
                      decoration: BoxDecoration(
                        color: page.color.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                    ),
                    Image.network(
                      page.imageUrl,
                      width: 260,
                      height: 260,
                      fit: BoxFit.contain,
                      semanticLabel: page.title,
                      frameBuilder: (context, child, frame, sync) =>
                          AnimatedOpacity(
                            opacity: sync || frame != null ? 1 : 0,
                            duration: const Duration(milliseconds: 250),
                            child: child,
                          ),
                      // First launch can be offline: show the icon instead.
                      errorBuilder: (_, _, _) => Icon(
                        page.illustration,
                        size: 72,
                        color: page.color,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
          // Title
          Text(
            page.title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          // Description
          Text(
            page.description,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
