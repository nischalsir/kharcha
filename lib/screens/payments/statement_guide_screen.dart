import 'package:flutter/material.dart';

import '../../core/l10n/app_l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../models/statement_entry.dart';
import '../../services/app_images.dart';
import '../../widgets/common/glass_background.dart';
import '../../widgets/common/primary_button.dart';

/// One step of a "how to download your statement" guide.
class GuideStep {
  const GuideStep({
    required this.image,
    required this.icon,
    required this.title,
    required this.titleNe,
    required this.body,
    required this.bodyNe,
  });

  /// Cloudinary public id of the step's picture, under `kharcha/help/`.
  /// Replacing the image on Cloudinary under the same id changes the slide
  /// without an app update.
  final String image;

  /// Shown in place of the picture while it loads or when offline.
  final IconData icon;
  final String title;
  final String titleNe;
  final String body;
  final String bodyNe;

  static const String _base =
      'https://res.cloudinary.com/dh3rzo7bt/image/upload';

  /// The picture width asked for on a screen [logicalWidth] wide. Stepped,
  /// so that the preloader and the slide agree on one address.
  static int pixelWidthFor(double logicalWidth, double devicePixelRatio) =>
      (((logicalWidth * devicePixelRatio) / 200).ceil() * 200).clamp(400, 1600);

  /// The slide picture, sized for the screen it is shown on.
  String urlFor(int pixelWidth) =>
      '$_base/f_auto,q_auto,c_limit,w_$pixelWidth/kharcha/help/$image';
}

/// The steps for each kind of statement.
///
/// Banks differ and their apps change, so the bank guide describes what to
/// look for rather than naming any one bank's menus. The eSewa guide follows
/// what its own statement export contains.
class StatementGuides {
  const StatementGuides._();

  static const List<GuideStep> bank = <GuideStep>[
    GuideStep(
      image: 'bank-1',
      icon: Icons.account_balance_rounded,
      title: 'Open your bank',
      titleNe: 'आफ्नो बैंक खोल्नुहोस्',
      body:
          'Sign in to your bank’s mobile app or its internet banking site. '
          'The exact screens differ from bank to bank; the steps are the same.',
      bodyNe:
          'आफ्नो बैंकको मोबाइल एप वा इन्टरनेट बैंकिङमा साइन इन गर्नुहोस्। '
          'स्क्रिन बैंकअनुसार फरक हुन्छ, चरण उही हुन्।',
    ),
    GuideStep(
      image: 'bank-2',
      icon: Icons.receipt_long_rounded,
      title: 'Find your statement',
      titleNe: 'स्टेटमेन्ट खोज्नुहोस्',
      body:
          'Look for Statement, Account statement or Transactions. It is '
          'usually on the account’s own page.',
      bodyNe:
          'Statement, Account statement वा Transactions खोज्नुहोस्। यो '
          'प्रायः खाताकै पृष्ठमा हुन्छ।',
    ),
    GuideStep(
      image: 'bank-3',
      icon: Icons.date_range_rounded,
      title: 'Choose the account and dates',
      titleNe: 'खाता र मिति छान्नुहोस्',
      body:
          'Pick the account and the period you want. A month or two at a time '
          'is easiest to review.',
      bodyNe:
          'खाता र चाहिएको अवधि छान्नुहोस्। एक-दुई महिनाको स्टेटमेन्ट जाँच्न '
          'सजिलो हुन्छ।',
    ),
    GuideStep(
      image: 'bank-4',
      icon: Icons.file_download_rounded,
      title: 'Download or export it',
      titleNe: 'डाउनलोड वा एक्सपोर्ट गर्नुहोस्',
      body:
          'Choose Download or Export. If you are offered a choice, Excel or '
          'CSV reads most reliably; PDF works for statements laid out as a '
          'table.',
      bodyNe:
          'Download वा Export छान्नुहोस्। विकल्प भए Excel वा CSV सबैभन्दा '
          'भरपर्दो हुन्छ; तालिकाजस्तो PDF पनि चल्छ।',
    ),
    GuideStep(
      image: 'bank-5',
      icon: Icons.upload_file_rounded,
      title: 'Import it into Kharcha',
      titleNe: 'खर्चामा आयात गर्नुहोस्',
      body:
          'Go back to the import page, tap Choose file and pick the file you '
          'saved, then check the list of '
          'transactions and confirm. Importing the same statement twice does '
          'not create duplicates.',
      bodyNe:
          'आयात पृष्ठमा फर्केर सुरक्षित गरेको फाइल छान्नुहोस्, कारोबारको सूची जाँचेर '
          'पुष्टि गर्नुहोस्। एउटै स्टेटमेन्ट दुई पटक आयात गर्दा दोहोरिँदैन।',
    ),
  ];

  static const List<GuideStep> esewa = <GuideStep>[
    GuideStep(
      image: 'esewa-1',
      icon: Icons.account_balance_wallet_rounded,
      title: 'Sign in to eSewa',
      titleNe: 'eSewa मा साइन इन गर्नुहोस्',
      body:
          'Open eSewa and sign in to your account. The website in a browser '
          'is the easiest place to export a file from.',
      bodyNe:
          'eSewa खोलेर आफ्नो खातामा साइन इन गर्नुहोस्। फाइल एक्सपोर्ट गर्न '
          'ब्राउजरमा वेबसाइट सबैभन्दा सजिलो हुन्छ।',
    ),
    GuideStep(
      image: 'esewa-2',
      icon: Icons.history_rounded,
      title: 'Open your statement',
      titleNe: 'आफ्नो स्टेटमेन्ट खोल्नुहोस्',
      body:
          'Go to your Statement, the list of everything paid and received '
          'from your wallet.',
      bodyNe:
          'आफ्नो Statement मा जानुहोस्, जहाँ वालेटबाट तिरेको र पाएको सबै '
          'सूची हुन्छ।',
    ),
    GuideStep(
      image: 'esewa-3',
      icon: Icons.date_range_rounded,
      title: 'Set the dates',
      titleNe: 'मिति राख्नुहोस्',
      body:
          'Choose the From and To dates for the period you want to bring '
          'into Kharcha.',
      bodyNe: 'खर्चामा ल्याउन चाहेको अवधिका लागि From र To मिति छान्नुहोस्।',
    ),
    GuideStep(
      image: 'esewa-4',
      icon: Icons.table_view_rounded,
      title: 'Export as Excel',
      titleNe: 'Excel मा एक्सपोर्ट गर्नुहोस्',
      body:
          'Export the statement as an Excel file (.xls). Kharcha reads the '
          'Date Time, Description, Dr. and Cr. columns from it.',
      bodyNe:
          'स्टेटमेन्ट Excel फाइल (.xls) मा एक्सपोर्ट गर्नुहोस्। खर्चाले त्यसका '
          'Date Time, Description, Dr. र Cr. स्तम्भ पढ्छ।',
    ),
    GuideStep(
      image: 'esewa-5',
      icon: Icons.upload_file_rounded,
      title: 'Import it into Kharcha',
      titleNe: 'खर्चामा आयात गर्नुहोस्',
      body:
          'Go back to the import page and tap Choose file. Money you paid '
          'becomes '
          'expenses, money you received becomes income, and you choose which '
          'rows to keep.',
      bodyNe:
          'आयात पृष्ठमा फर्केर फाइल छान्नुहोस्। तिरेको रकम खर्च र पाएको रकम आम्दानी '
          'बन्छ, र कुन पङ्क्ति राख्ने तपाईंले छान्नुहुन्छ।',
    ),
  ];

  static List<GuideStep> forSource(StatementSource source) =>
      source == StatementSource.esewa ? esewa : bank;
}

/// Step-by-step slides showing how to get a statement file to import.
///
/// A guide only: "Done" on the last step, like closing it, goes back to the
/// page it was opened from.
class StatementGuideScreen extends StatefulWidget {
  const StatementGuideScreen({super.key, required this.source});

  final StatementSource source;

  @override
  State<StatementGuideScreen> createState() => _StatementGuideScreenState();
}

class _StatementGuideScreenState extends State<StatementGuideScreen> {
  final PageController _controller = PageController();
  int _index = 0;

  List<GuideStep> get _steps => StatementGuides.forSource(widget.source);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _go(int index) {
    final animate = !MediaQuery.disableAnimationsOf(context);
    if (animate) {
      _controller.animateToPage(
        index,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    } else {
      _controller.jumpToPage(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    final steps = _steps;
    final last = _index == steps.length - 1;
    final isEsewa = widget.source == StatementSource.esewa;

    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            tooltip: context.t('Close', 'बन्द गर्नुहोस्'),
            icon: Icon(Icons.close_rounded, color: theme.colorScheme.onSurface),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            isEsewa
                ? context.t('eSewa statement', 'eSewa स्टेटमेन्ट')
                : context.t('Bank statement', 'बैंक स्टेटमेन्ट'),
            style: theme.textTheme.titleLarge,
          ),
        ),
        body: SafeArea(
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Text(
                  context.t(
                    'Step ${_index + 1} of ${steps.length}',
                    'चरण ${L10n.neNumber(_index + 1)} / '
                        '${L10n.neNumber(steps.length)}',
                  ),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: glass.textSecondary,
                  ),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: steps.length,
                  onPageChanged: (index) => setState(() => _index = index),
                  itemBuilder: (context, index) => _Slide(step: steps[index]),
                ),
              ),
              _Dots(count: steps.length, index: _index),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _index == 0 ? null : () => _go(_index - 1),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                        ),
                        child: Text(context.t('Back', 'पछाडि')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: PrimaryButton(
                        label: last
                            ? context.t('Done', 'सम्पन्न')
                            : context.t('Next', 'अर्को'),
                        icon: last
                            ? Icons.check_rounded
                            : Icons.arrow_forward_rounded,
                        onPressed: last
                            ? () => Navigator.pop(context)
                            : () => _go(_index + 1),
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

class _Slide extends StatelessWidget {
  const _Slide({required this.step});

  final GuideStep step;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;

    return LayoutBuilder(
      builder: (context, constraints) {
        final pixels = GuideStep.pixelWidthFor(
          constraints.maxWidth,
          MediaQuery.devicePixelRatioOf(context),
        );
        final placeholder = ColoredBox(
          color: theme.colorScheme.primary.withValues(alpha: 0.10),
          child: Center(
            child: Icon(
              step.icon,
              size: 72,
              color: theme.colorScheme.primary.withValues(alpha: 0.8),
            ),
          ),
        );

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: AspectRatio(
                  aspectRatio: 16 / 11,
                  child: Image(
                    image: AppImages.provider(step.urlFor(pixels)),
                    fit: BoxFit.cover,
                    // The picture only illustrates the text beside it.
                    excludeFromSemantics: true,
                    frameBuilder: (_, child, frame, sync) =>
                        sync || frame != null ? child : placeholder,
                    errorBuilder: (_, _, _) => placeholder,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                context.t(step.title, step.titleNe),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                context.t(step.body, step.bodyNe),
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: glass.textSecondary,
                  height: 1.5,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExcludeSemantics(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == index ? 22 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: i == index
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
        ],
      ),
    );
  }
}
