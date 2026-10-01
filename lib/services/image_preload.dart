import '../models/statement_entry.dart';
import '../screens/auth/introduction_screen.dart';
import '../screens/payments/statement_guide_screen.dart';
import '../widgets/common/auth_widgets.dart';
import '../widgets/common/festival_image.dart';
import 'app_images.dart';
import 'festival_service.dart';

/// Which pictures to fetch ahead of time, at exactly the sizes the screens
/// ask for on this phone, so that opening a page finds them already stored.
class ImagePreload {
  const ImagePreload._();

  /// Sizes festival photographs are shown at: the Calendar's month list, the
  /// home card, and (null) the full-width day card.
  static const List<double?> _festivalWidths = <double?>[46, 64, null];

  /// Pictures seen before signing in: the logo and the introduction's.
  static List<String> startup({required double devicePixelRatio}) => <String>[
    AuthBrand.logoUrl((AuthBrand.logoSize * devicePixelRatio).round()),
    IntroductionScreen.heroImageUrl,
  ];

  /// Pictures used inside the app: the statement guides and every festival.
  /// Small ones first, so the lists fill in before the large day-card photos.
  static List<String> account({
    required double screenWidth,
    required double devicePixelRatio,
  }) {
    final guideWidth = GuideStep.pixelWidthFor(screenWidth, devicePixelRatio);
    final paths = FestivalService.imagePaths;
    return <String>{
      for (final source in StatementSource.values)
        for (final step in StatementGuides.forSource(source))
          ?step.urlFor(guideWidth),
      for (final width in _festivalWidths)
        for (final path in paths)
          FestivalImage.urlFor(
            path,
            FestivalImage.pixelWidthFor(width ?? screenWidth, devicePixelRatio),
          ),
    }.toList();
  }

  /// Starts fetching [startup], and [account] too when someone is signed in.
  static void run({
    required double screenWidth,
    required double devicePixelRatio,
    required bool signedIn,
  }) {
    if (screenWidth <= 0 || devicePixelRatio <= 0) return;
    AppImages.preload(<String>[
      ...startup(devicePixelRatio: devicePixelRatio),
      if (signedIn)
        ...account(
          screenWidth: screenWidth,
          devicePixelRatio: devicePixelRatio,
        ),
    ]);
  }
}
