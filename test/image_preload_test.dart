import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/models/statement_entry.dart';
import 'package:kharcha_app/screens/auth/introduction_screen.dart';
import 'package:kharcha_app/screens/payments/statement_guide_screen.dart';
import 'package:kharcha_app/services/festival_service.dart';
import 'package:kharcha_app/services/image_preload.dart';
import 'package:kharcha_app/widgets/common/auth_widgets.dart';
import 'package:kharcha_app/widgets/common/festival_image.dart';

void main() {
  // A common phone: 1080 physical pixels across at 2.75x.
  const double dpr = 2.75;
  const double width = 1080 / dpr;

  test('before sign-in: the logo and the introduction pictures', () {
    final urls = ImagePreload.startup(devicePixelRatio: dpr);
    expect(urls, contains(AuthBrand.logoUrl((76 * dpr).round())));
    expect(urls, containsAll(IntroductionScreen.pictureUrls));
    expect(IntroductionScreen.pictureUrls, hasLength(5));
    expect(urls, hasLength(6));
  });

  test('the guide slides are fetched at the width the slide asks for', () {
    final urls = ImagePreload.account(
      screenWidth: width,
      devicePixelRatio: dpr,
    );
    final pixels = GuideStep.pixelWidthFor(width, dpr);
    expect(pixels, 1200);
    for (final source in StatementSource.values) {
      for (final step in StatementGuides.forSource(source)) {
        // Steps with no picture are not fetched at all.
        final url = step.urlFor(pixels);
        if (url == null) continue;
        expect(urls, contains(url));
      }
    }
    expect(urls.where((url) => url.contains('/kharcha/help/')), hasLength(10));
  });

  test('every festival is fetched at each size it is shown', () {
    final urls = ImagePreload.account(
      screenWidth: width,
      devicePixelRatio: dpr,
    );
    final paths = FestivalService.imagePaths;
    expect(paths, isNotEmpty);
    for (final path in paths) {
      // The Calendar list (46) and the home card (64) share one rendition.
      expect(urls, contains(FestivalImage.urlFor(path, 200)));
      // The full-width day card.
      expect(urls, contains(FestivalImage.urlFor(path, 1100)));
    }
    expect(urls.toSet(), hasLength(urls.length));
    expect(
      urls.every((url) => url.startsWith('https://res.cloudinary.com/')),
      isTrue,
    );
  });

  test('guide widths stay within what Cloudinary is asked for', () {
    expect(GuideStep.pixelWidthFor(100, 1), 400);
    expect(GuideStep.pixelWidthFor(360, 3), 1200);
    expect(GuideStep.pixelWidthFor(1200, 3), 1600);
  });
}
