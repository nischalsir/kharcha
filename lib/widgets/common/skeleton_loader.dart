import 'package:flutter/material.dart';

import '../../core/theme/motion.dart';
import 'glass_card.dart';
import 'grouped_list.dart';

/// A region that is still loading, drawn as the shape of what is coming.
///
/// Wrap a layout of [SkeletonLoader] blocks in one of these. Every block
/// under it breathes together, slowly and only slightly, so the page reads
/// as one thing waiting rather than a dozen things flashing. With reduced
/// motion the blocks hold still. A screen reader is told the region is
/// loading once, instead of being read a row of empty boxes.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, required this.child, this.label = 'Loading'});

  final Widget child;

  /// What a screen reader says for the whole region.
  final String label;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late final Animation<double> _opacity = Tween<double>(
    begin: 1,
    end: 0.45,
  ).animate(CurvedAnimation(parent: _breath, curve: Curves.easeInOut));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context)) {
      _breath
        ..stop()
        ..value = 0;
    } else if (!_breath.isAnimating) {
      _breath.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.label,
      container: true,
      child: ExcludeSemantics(
        child: _SkeletonScope(opacity: _opacity, child: widget.child),
      ),
    );
  }
}

class _SkeletonScope extends InheritedWidget {
  const _SkeletonScope({required this.opacity, required super.child});

  final Animation<double> opacity;

  @override
  bool updateShouldNotify(_SkeletonScope oldWidget) =>
      opacity != oldWidget.opacity;
}

/// One placeholder block: a line of text, a picture, an amount.
///
/// Give it the size of the thing it stands for, so nothing moves when that
/// thing arrives. It animates only under a [Skeleton]; on its own it is a
/// still block.
class SkeletonLoader extends StatelessWidget {
  const SkeletonLoader({
    super.key,
    this.width,
    this.height = 16,
    this.radius = 8,
    this.color,
  });

  final double? width;
  final double height;
  final double radius;

  /// For a block on a surface that does not follow the theme. Otherwise the
  /// block takes a tint of the theme's text colour.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final block = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color:
            color ??
            scheme.onSurface.withValues(
              alpha: scheme.brightness == Brightness.dark ? 0.14 : 0.09,
            ),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
    final scope = context.dependOnInheritedWidgetOfExactType<_SkeletonScope>();
    if (scope == null) return block;
    return FadeTransition(opacity: scope.opacity, child: block);
  }
}

/// The placeholder for one row of a list: a tile, a name with a line under
/// it, and an amount, laid out exactly as [GroupedRow] lays out the real
/// thing.
class SkeletonRow extends StatelessWidget {
  const SkeletonRow({super.key, this.leading = true, this.trailing = true});

  final bool leading;
  final bool trailing;

  @override
  Widget build(BuildContext context) {
    return GroupedRow(
      leading: leading
          ? const SkeletonLoader(
              width: LeadingTile.size,
              height: LeadingTile.size,
              radius: 12,
            )
          : null,
      // Each block sits in a box the height of the line of text it stands
      // for, so the two are as far apart as the name and its caption.
      title: const SizedBox(
        height: 18,
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: 0.62,
          heightFactor: 0.66,
          child: SkeletonLoader(),
        ),
      ),
      subtitle: const SizedBox(
        height: 16,
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: 0.4,
          heightFactor: 0.62,
          child: SkeletonLoader(),
        ),
      ),
      trailing: trailing ? const SkeletonLoader(width: 68, height: 14) : null,
    );
  }
}

/// A list that is still loading: [count] rows in one card.
class SkeletonList extends StatelessWidget {
  const SkeletonList({
    super.key,
    this.count = 3,
    this.leading = true,
    this.trailing = true,
    this.label = 'Loading',
  });

  final int count;
  final bool leading;
  final bool trailing;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      label: label,
      child: GroupedCard(
        dividerIndent: leading ? 66 : 14,
        children: <Widget>[
          for (var i = 0; i < count; i++)
            SkeletonRow(leading: leading, trailing: trailing),
        ],
      ),
    );
  }
}

/// A card of text that is still loading: a heading and [lines] lines.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key, this.lines = 3});

  final int lines;

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SkeletonLoader(width: 120, height: 14),
            const SizedBox(height: 14),
            for (var i = 0; i < lines; i++) ...<Widget>[
              SkeletonLoader(
                width: i == lines - 1 ? 180 : double.infinity,
                height: 12,
              ),
              if (i != lines - 1) const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

/// Home, before the account's data is ready: the greeting, the balance, the
/// shortcuts and the first rows, each where the real one will be.
///
/// Shown only once it is certain Home is what comes next, in place of a
/// spinner in the middle of an empty screen.
class HomeSkeleton extends StatelessWidget {
  const HomeSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Skeleton(
        label: 'Loading your account',
        // Never scrolls and never overflows: on a short screen the lower
        // rows are simply cut off, as they would be on the real page.
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: const <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        SkeletonLoader(width: 96, height: 11),
                        SizedBox(height: 10),
                        SkeletonLoader(width: 190, height: 26),
                      ],
                    ),
                  ),
                  SkeletonLoader(width: 40, height: 40, radius: 20),
                ],
              ),
              const SizedBox(height: 22),
              const GlassCard(
                padding: EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SkeletonLoader(width: 100, height: 12),
                    SizedBox(height: 12),
                    SkeletonLoader(width: 210, height: 34),
                    SizedBox(height: 24),
                    Row(
                      children: <Widget>[
                        Expanded(child: _StatPlaceholder()),
                        SizedBox(width: 12),
                        Expanded(child: _StatPlaceholder()),
                        SizedBox(width: 12),
                        Expanded(child: _StatPlaceholder()),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (var i = 0; i < 5; i++)
                    const Expanded(
                      child: Column(
                        children: <Widget>[
                          SkeletonLoader(width: 56, height: 56, radius: 20),
                          SizedBox(height: 8),
                          SkeletonLoader(width: 40, height: 9),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              const GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SkeletonLoader(width: 140, height: 14),
                    SizedBox(height: 14),
                    SkeletonLoader(height: 12),
                    SizedBox(height: 10),
                    SkeletonLoader(width: 200, height: 12),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              const Align(
                alignment: AlignmentDirectional.centerStart,
                child: SkeletonLoader(width: 150, height: 18),
              ),
              const SizedBox(height: 12),
              GroupedCard(
                children: const <Widget>[
                  SkeletonRow(),
                  SkeletonRow(),
                  SkeletonRow(),
                  SkeletonRow(),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatPlaceholder extends StatelessWidget {
  const _StatPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SkeletonLoader(width: 52, height: 10),
        SizedBox(height: 8),
        SkeletonLoader(width: 70, height: 15),
      ],
    );
  }
}

/// Swaps a placeholder for the content it stood for with a short cross-fade,
/// so the content arrives instead of popping in. Both are pinned to the top,
/// which keeps a height difference from showing as a jump from the middle.
class SkeletonSwitcher extends StatelessWidget {
  const SkeletonSwitcher({
    super.key,
    required this.loading,
    required this.skeleton,
    required this.child,
  });

  final bool loading;
  final Widget skeleton;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppMotion.of(context, AppMotion.medium),
      switchInCurve: AppMotion.standard,
      switchOutCurve: AppMotion.standard,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: <Widget>[...previous, ?current],
      ),
      child: KeyedSubtree(
        key: ValueKey<bool>(loading),
        child: loading ? skeleton : child,
      ),
    );
  }
}
