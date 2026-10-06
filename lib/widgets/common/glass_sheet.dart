import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';

Future<T?> showGlassSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  String? title,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    barrierColor: const Color(0x66000000),
    builder: (sheetContext) =>
        GlassSheet(title: title, child: builder(sheetContext)),
  );
}

/// The app's bottom sheet: a solid surface with a grabber, a centred title
/// and the content, which scrolls when it is taller than the screen.
///
/// The page behind is dimmed, which is what sets a sheet apart. It used to be
/// wrapped in a blur as well, behind a body that was opaque anyway.
class GlassSheet extends StatelessWidget {
  const GlassSheet({super.key, required this.child, this.title});

  final Widget child;
  final String? title;

  /// The theme as it applies on a sheet, one per theme.
  static final Expando<ThemeData> _onSheet = Expando<ThemeData>();

  /// A sheet is the grouped grey that cards and text fields are made of on a
  /// page. On a sheet both step to the next surface up, so a field typed
  /// into and a row tapped on can be seen for what they are.
  static ThemeData onSheet(ThemeData theme) => _onSheet[theme] ??= () {
    final dark = theme.brightness == Brightness.dark;
    final raised = dark ? const Color(0xff2c2c2e) : Colors.white;
    return theme.copyWith(
      colorScheme: theme.colorScheme.copyWith(surfaceContainerHigh: raised),
      inputDecorationTheme: theme.inputDecorationTheme.copyWith(
        fillColor: raised,
      ),
    );
  }();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = scheme.brightness == Brightness.dark;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Material(
        color: scheme.surfaceContainerLow,
        shape: context.tokens.sheetShape,
        clipBehavior: Clip.antiAlias,
        child: Theme(
          data: onSheet(theme),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Center(
                    child: Container(
                      width: 36,
                      height: 5,
                      decoration: BoxDecoration(
                        color: dark
                            ? Colors.white.withValues(alpha: 0.2)
                            : Colors.black.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  if (title != null) ...<Widget>[
                    const SizedBox(height: 14),
                    Semantics(
                      header: true,
                      child: Text(
                        title!,
                        style: theme.textTheme.labelLarge,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Flexible(child: SingleChildScrollView(child: child)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
