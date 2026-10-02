import 'package:flutter/material.dart';

import '../../core/l10n/app_l10n.dart';
import 'mornye_chrome.dart';

/// The way back from a page: an arrow on a small round piece of the same
/// glass the cards are made of. Used as an app bar's `leading`, or at the
/// start of a page's own heading through [PageBack].
class GlassBackButton extends StatelessWidget {
  const GlassBackButton({super.key, this.onPressed});

  /// Defaults to closing the page.
  final VoidCallback? onPressed;

  static const double size = 40;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Fills an app bar's leading slot and sits in its middle; anywhere else
    // it takes only its own size.
    return Center(
      widthFactor: 1,
      heightFactor: 1,
      child: Tooltip(
        message: context.t('Back', 'पछाडि'),
        child: SizedBox(
          width: size,
          height: size,
          child: MornyeGlass.navigation(
            blurEnabled: false,
            radius: size / 2,
            strongTint: true,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onPressed ?? () => Navigator.maybePop(context),
                child: Icon(
                  Icons.arrow_back_rounded,
                  size: 20,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A [GlassBackButton] for a page that draws its own heading instead of an
/// app bar. Takes no room when there is nowhere to go back to, which is how
/// the same page looks as a tab.
class PageBack extends StatelessWidget {
  const PageBack({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Navigator.of(context).canPop()) return const SizedBox.shrink();
    return const Padding(
      padding: EdgeInsets.only(right: 12),
      child: GlassBackButton(),
    );
  }
}
