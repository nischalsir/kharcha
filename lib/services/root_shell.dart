import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/l10n/app_l10n.dart';
import '../providers/friend_provider.dart';
import '../widgets/common/app_bottom_nav.dart';
import '../widgets/common/glass_background.dart';
import '../widgets/common/root_drawer.dart';
import '../screens/friends/friends_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/more/more_screen.dart';
import '../screens/pasal/pasal_screen.dart';
import '../screens/payments/payments_screen.dart';

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell>
    with SingleTickerProviderStateMixin {
  int _index = 0;
  final AppNavController _nav = AppNavController();
  bool _keyboardVisible = false;

  final PageController _pageController = PageController();

  @override
  void initState() {
    super.initState();
    AppNavRouteObserver.bind(_nav);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncKeyboard(MediaQuery.viewInsetsOf(context).bottom);
  }

  void _syncKeyboard(double inset) {
    final visible = inset > 0;
    if (visible && !_keyboardVisible) {
      _nav.expand();
    }
    _keyboardVisible = visible;
  }

@override
  void dispose() {
    AppNavRouteObserver.unbind(_nav);
    _pageController.dispose();
    _nav.dispose();
    super.dispose();
  }

  Widget _buildPage(int index) {
    switch (index) {
      case 0:
        return const HomeScreen();
      case 1:
        return const PaymentsScreen();
      case 2:
        return const FriendsScreen();
      case 3:
        return const PasalScreen();
      case 4:
        return const MoreScreen();
      default:
        return const HomeScreen();
    }
  }

  void _select(int index) {
    if (index == _index) return;
    _nav.expand();
    setState(() => _index = index);
    if (!_pageController.hasClients) return;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  void _handlePageChanged(int index) {
    if (index != _index) {
      setState(() => _index = index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final friendOverdue = context
        .watch<FriendProvider>()
        .summary()
        .overdueCount;

    final items = <AppBottomNavItem>[
      AppBottomNavItem(
        icon: Icons.home_outlined,
        selectedIcon: Icons.home_rounded,
        label: context.t('Home', 'गृह'),
      ),
      AppBottomNavItem(
        icon: Icons.receipt_long_outlined,
        selectedIcon: Icons.receipt_long_rounded,
        label: context.t('Payments', 'भुक्तानी'),
      ),
      AppBottomNavItem(
        icon: Icons.people_outline,
        selectedIcon: Icons.people_alt_rounded,
        label: context.t('Friends', 'साथीहरू'),
        badgeCount: friendOverdue,
      ),
      AppBottomNavItem(
        icon: Icons.storefront_outlined,
        selectedIcon: Icons.storefront_rounded,
        label: context.t('Pasal', 'पसल'),
      ),
      AppBottomNavItem(
        icon: Icons.more_horiz,
        selectedIcon: Icons.more_horiz,
        label: context.t('More', 'थप'),
      ),
    ];

    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        drawer: RootDrawer(
          currentIndex: _index,
          onTabSelected: _select,
          friendOverdue: friendOverdue,
        ),
        body: NotificationListener<ScrollNotification>(
          onNotification: _nav.handleScroll,
          child: PageView(
            controller: _pageController,
            onPageChanged: _handlePageChanged,
            physics: const NeverScrollableScrollPhysics(),
            children: <Widget>[
              for (int i = 0; i < 5; i++)
                _KeepAlivePage(
                  key: ValueKey(i),
                  child: _buildPage(i),
                ),
            ],
          ),
        ),
        bottomNavigationBar: AppBottomNav(
          items: items,
          selectedIndex: _index,
          onSelected: _select,
          controller: _nav,
        ),
      ),
    );
  }
}

/// Keeps off-screen shell pages alive inside the `PageView` so their scroll
/// positions (and heavy dashboard state) survive swiping away and back.
class _KeepAlivePage extends StatefulWidget {
  const _KeepAlivePage({required this.child, super.key});

  final Widget child;

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}