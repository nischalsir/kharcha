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
      description: 'Log your daily spending in seconds. Categorize expenses, add notes, and never wonder where your money went.',
      illustration: Icons.receipt_long_rounded,
      color: const Color(0xFF10B981),
    ),
    OnboardingPage(
      title: 'Smart Budgets',
      description: 'Set monthly budgets per category. Get alerts before you overspend and visualize your spending patterns.',
      illustration: Icons.pie_chart_rounded,
      color: const Color(0xFF3B82F6),
    ),
    OnboardingPage(
      title: 'Split with Friends',
      description: 'Track shared expenses with friends and Pasal (group expenses). Settle up instantly with clear balances.',
      illustration: Icons.people_alt_rounded,
      color: const Color(0xFFF59E0B),
    ),
    OnboardingPage(
      title: 'Works Offline',
      description: 'Your data stays on your device. Sync securely with Supabase when online. Privacy first, always.',
      illustration: Icons.cloud_sync_rounded,
      color: const Color(0xFF8B5CF6),
    ),
  ];

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
                  onPageChanged: (index) =>
                      setState(() => _currentPage = index),
                  itemBuilder: (context, index) {
                    final page = _pages[index];
                    return _OnboardingPageContent(page: page);
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

  const OnboardingPage({
    required this.title,
    required this.description,
    required this.illustration,
    required this.color,
  });
}

class _OnboardingPageContent extends StatelessWidget {
  const _OnboardingPageContent({required this.page});

  final OnboardingPage page;

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
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              color: page.color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(page.illustration, size: 64, color: page.color),
          ),
          const SizedBox(height: 40),
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
