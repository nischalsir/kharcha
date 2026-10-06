import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/l10n/app_l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../models/transaction_model.dart';
import '../../providers/report_provider.dart';
import '../../services/nepali_date_service.dart';
import '../../services/report_exporter.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/form_helpers.dart';
import '../../widgets/common/glass_button.dart';
import '../../widgets/common/glass_card.dart';
import '../../widgets/common/grouped_list.dart';
import '../../widgets/common/page_header.dart';
import '../../widgets/common/page_refresh.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, this.lastMonth = false});

  /// Opens on the month before this one instead of the current month: where
  /// the monthly report's notification leads.
  final bool lastMonth;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

/// The two files a report can be exported as.
enum _ExportFormat {
  pdf('pdf', 'application/pdf'),
  csv('csv', 'text/csv');

  const _ExportFormat(this.extension, this.mimeType);

  final String extension;
  final String mimeType;
}

class _ReportsScreenState extends State<ReportsScreen> {
  int _tab = 0;

  /// The format being written, while it is being written.
  _ExportFormat? _exporting;

  /// Asks what the report should cover and where it should go, then writes
  /// it. Saving puts the file wherever the user picks on their phone;
  /// sharing hands it to another app.
  Future<void> _export(_ExportFormat format) async {
    if (_exporting != null) return;
    final reports = context.read<ReportProvider>();
    final choice = await showModalBottomSheet<(ReportPeriod, bool)>(
      context: context,
      showDragHandle: true,
      builder: (_) => _ExportSheet(format: format, reports: reports),
    );
    if (choice == null || !mounted) return;
    final (period, share) = choice;

    setState(() => _exporting = format);
    try {
      final data = reports.exportData(period);
      final bytes = format == _ExportFormat.pdf
          ? await ReportExporter.pdf(data)
          : ReportExporter.csv(data);
      final name = '${ReportExporter.fileName(data)}.${format.extension}';
      if (!mounted) return;

      if (share) {
        final folder = Directory(
          '${(await getTemporaryDirectory()).path}/reports',
        )..createSync(recursive: true);
        final file = File('${folder.path}/$name')..writeAsBytesSync(bytes);
        if (!mounted) return;
        final box = context.findRenderObject() as RenderBox?;
        await SharePlus.instance.share(
          ShareParams(
            files: <XFile>[XFile(file.path, mimeType: format.mimeType)],
            subject: 'Kharcha report: ${data.periodLabel}',
            sharePositionOrigin: box == null
                ? null
                : box.localToGlobal(Offset.zero) & box.size,
          ),
        );
        return;
      }

      final saved = await FilePicker.saveFile(
        dialogTitle: 'Save report',
        fileName: name,
        bytes: bytes,
        mimeType: format.mimeType,
      );
      // Backing out of the save dialog saves nothing and says nothing.
      if (saved == null || !mounted) return;
      showMessage(
        context,
        context.t(
          'Report saved as $name.',
          'प्रतिवेदन $name नाममा सुरक्षित भयो।',
        ),
      );
    } catch (error) {
      debugPrint('Report export failed: $error');
      if (mounted) {
        showMessage(
          context,
          context.t(
            'The report could not be exported. Please try again.',
            'प्रतिवेदन निर्यात हुन सकेन। फेरि प्रयास गर्नुहोस्।',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = null);
    }
  }

  @override
  void initState() {
    super.initState();
    // Every visit starts on a known month, not wherever the last one ended.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final dates = context.read<NepaliDateService>();
      final today = dates.today();
      final thisMonth = BsDate(today.year, today.month, 1);
      context.read<ReportProvider>().setAnchor(
        widget.lastMonth ? dates.shiftMonth(thisMonth, -1) : thisMonth,
      );
    });
  }

  /// The month the figures are for, with a step back and a step forward.
  /// The current month is as far forward as it goes.
  Widget _monthSwitcher(ReportProvider provider, ThemeData theme) {
    final dates = context.read<NepaliDateService>();
    final today = dates.today();
    final anchor = provider.anchor;
    final current = anchor.year == today.year && anchor.month == today.month;
    final previous = dates.shiftMonth(BsDate(today.year, today.month, 1), -1);
    final last = anchor.year == previous.year && anchor.month == previous.month;
    void step(int months) => provider.setAnchor(
      dates.shiftMonth(BsDate(anchor.year, anchor.month, 1), months),
    );
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        children: <Widget>[
          IconButton(
            key: const ValueKey<String>('report-prev-month'),
            tooltip: context.t('Month before', 'अघिल्लो महिना'),
            onPressed: () => step(-1),
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  dates.formatMonth(anchor.year, anchor.month),
                  key: const ValueKey<String>('report-month'),
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                if (current || last)
                  Text(
                    current
                        ? context.t('This month', 'यो महिना')
                        : context.t('Last month', 'गत महिना'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: context.glass.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            key: const ValueKey<String>('report-next-month'),
            tooltip: context.t('Month after', 'पछिल्लो महिना'),
            onPressed: current ? null : () => step(1),
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ReportProvider>();
    final theme = Theme.of(context);
    final glass = context.glass;
    final tabs = <String>[
      context.t('Overview', 'सारांश'),
      context.t('Categories', 'श्रेणीहरू'),
      context.t('Trends', 'प्रवृत्ति'),
    ];

    return SafeArea(
      bottom: false,
      child: PageRefresh(
        pageName: 'Reports',
        pageNameNe: 'प्रतिवेदन',
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
          children: <Widget>[
            PageHeader(title: context.t('Reports', 'प्रतिवेदन')),
            const SizedBox(height: 12),
            // The trends tab is a run of months, not one of them.
            if (_tab != 2) ...<Widget>[
              _monthSwitcher(provider, theme),
              const SizedBox(height: 12),
            ],
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: <Widget>[
                  for (var i = 0; i < tabs.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(tabs[i]),
                        selected: _tab == i,
                        onSelected: (_) => setState(() => _tab = i),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_tab == 0) ..._overview(provider, glass, theme),
            if (_tab == 1) ..._categories(provider, glass, theme),
            if (_tab == 2) ..._trends(provider, glass, theme),
          ],
        ),
      ),
    );
  }

  List<Widget> _overview(
    ReportProvider provider,
    GlassThemeCompat glass,
    ThemeData theme,
  ) {
    final summary = provider.build();
    final income = summary.income;
    final expense = summary.expense;
    final net = summary.savings;

    return <Widget>[
      // One card for the month: what is left, and under it what came in and
      // what went out. It was two cards saying one thing between them.
      GlassCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              context.t('Net Balance', 'खुद बचत'),
              style: theme.textTheme.labelMedium?.copyWith(
                color: glass.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                CurrencyFormatter.format(net),
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: net >= 0 ? glass.success : glass.danger,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              net >= 0
                  ? context.t('You are saving!', 'तपाईं बचत गर्दै हुनुहुन्छ!')
                  : context.t(
                      'Spending exceeds income',
                      'खर्च आम्दानीभन्दा बढी छ',
                    ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: glass.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            Container(height: 0.5, color: glass.hairline),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                Expanded(
                  child: _StatCard(
                    label: context.t('Income', 'आम्दानी'),
                    value: CurrencyFormatter.format(income),
                    color: glass.success,
                    icon: Icons.arrow_downward_rounded,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    label: context.t('Expense', 'खर्च'),
                    value: CurrencyFormatter.format(expense),
                    color: glass.danger,
                    icon: Icons.arrow_upward_rounded,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      GroupLabel(context.t('Export this report', 'यो प्रतिवेदन निर्यात')),
      Row(
        children: <Widget>[
          Expanded(
            child: GlassButton(
              key: const ValueKey<String>('export-pdf'),
              icon: Icons.picture_as_pdf_rounded,
              label: context.t('Export PDF', 'PDF निर्यात'),
              isLoading: _exporting == _ExportFormat.pdf,
              onPressed: () => _export(_ExportFormat.pdf),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GlassButton(
              key: const ValueKey<String>('export-csv'),
              icon: Icons.table_chart_rounded,
              label: context.t('Export CSV', 'CSV निर्यात'),
              isLoading: _exporting == _ExportFormat.csv,
              onPressed: () => _export(_ExportFormat.csv),
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _categories(
    ReportProvider provider,
    GlassThemeCompat glass,
    ThemeData theme,
  ) {
    final categories = provider.categoryBreakdown;

    if (categories.isEmpty) {
      return <Widget>[
        SizedBox(
          height: 300,
          child: EmptyState(
            icon: Icons.category_rounded,
            title: context.t('No category data', 'श्रेणीको विवरण छैन'),
            message: context.t(
              'Add transactions with categories to see breakdown.',
              'विवरण हेर्न श्रेणीसहित कारोबार थप्नुहोस्।',
            ),
          ),
        ),
      ];
    }

    return <Widget>[
      GroupedCard(
        children: <Widget>[
          for (final item in categories)
            GroupedRow(
              leading: LeadingTile(
                color: Color(item.color),
                icon: _iconFromString(item.icon),
              ),
              title: Text(item.name),
              subtitle: Text(
                item.type == TransactionType.expense
                    ? context.t('Spent', 'खर्च भयो')
                    : context.t('Earned', 'आम्दानी भयो'),
              ),
              trailing: TrailingAmount(
                text: CurrencyFormatter.format(item.amount),
                color: item.type == TransactionType.expense
                    ? glass.danger
                    : glass.success,
              ),
            ),
        ],
      ),
    ];
  }

  List<Widget> _trends(
    ReportProvider provider,
    GlassThemeCompat glass,
    ThemeData theme,
  ) {
    final monthly = provider.monthlyTrends;

    if (monthly.isEmpty) {
      return <Widget>[
        SizedBox(
          height: 300,
          child: EmptyState(
            icon: Icons.trending_up_rounded,
            title: context.t('Not enough data', 'पर्याप्त विवरण छैन'),
            message: context.t(
              'Add more transactions over time to see trends.',
              'प्रवृत्ति हेर्न समयसँगै थप कारोबार थप्नुहोस्।',
            ),
          ),
        ),
      ];
    }

    return <Widget>[
      GroupedCard(
        dividerIndent: 14,
        children: <Widget>[
          for (final item in monthly)
            GroupedRow(
              title: Text(item.month),
              subtitle: Text(
                '${context.t('Income', 'आम्दानी')}: '
                '${CurrencyFormatter.format(item.income)}  •  '
                '${context.t('Expense', 'खर्च')}: '
                '${CurrencyFormatter.format(item.expense)}',
              ),
              trailing: TrailingAmount(
                text: CurrencyFormatter.format(item.net),
                color: item.net >= 0 ? glass.success : glass.danger,
              ),
            ),
        ],
      ),
    ];
  }

  IconData _iconFromString(String icon) {
    switch (icon) {
      case 'restaurant':
        return Icons.restaurant_rounded;
      case 'directions_bus':
        return Icons.directions_bus_rounded;
      case 'shopping_bag':
        return Icons.shopping_bag_rounded;
      case 'receipt_long':
        return Icons.receipt_long_rounded;
      case 'home':
        return Icons.home_rounded;
      case 'movie':
        return Icons.movie_rounded;
      case 'favorite':
        return Icons.favorite_rounded;
      case 'school':
        return Icons.school_rounded;
      case 'flight':
        return Icons.flight_rounded;
      case 'subscriptions':
        return Icons.subscriptions_rounded;
      case 'payments':
        return Icons.payments_rounded;
      case 'work':
        return Icons.work_rounded;
      default:
        return Icons.category_rounded;
    }
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: theme.textTheme.labelSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

/// What an export should cover and where it should go: a period, then
/// Save to phone or Share.
class _ExportSheet extends StatefulWidget {
  const _ExportSheet({required this.format, required this.reports});

  final _ExportFormat format;
  final ReportProvider reports;

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  ReportPeriod _period = ReportPeriod.thisMonth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    final data = widget.reports.exportData(_period);
    final count = data.rows.length;
    final pdf = widget.format == _ExportFormat.pdf;

    String label(ReportPeriod period) => switch (period) {
      ReportPeriod.thisMonth => context.t('This month', 'यो महिना'),
      ReportPeriod.thisYear => context.t('This year', 'यो वर्ष'),
      ReportPeriod.allTime => context.t('All time', 'सबै समय'),
    };

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              pdf
                  ? context.t('Export as PDF', 'PDF मा निर्यात')
                  : context.t('Export as CSV', 'CSV मा निर्यात'),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              pdf
                  ? context.t(
                      'Totals, categories, months and every transaction, '
                          'ready to print or send.',
                      'जम्मा, श्रेणी, महिना र हरेक कारोबार, छाप्न वा पठाउन '
                          'तयार।',
                    )
                  : context.t(
                      'Every transaction as a spreadsheet, for Excel or '
                          'Google Sheets.',
                      'हरेक कारोबार स्प्रेडसिटका रूपमा, Excel वा Google '
                          'Sheets का लागि।',
                    ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: glass.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: <Widget>[
                for (final period in ReportPeriod.values)
                  ChoiceChip(
                    key: ValueKey<String>('period-${period.name}'),
                    label: Text(label(period)),
                    selected: _period == period,
                    onSelected: (_) => setState(() => _period = period),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              count == 0
                  ? context.t(
                      '${data.periodLabel}: no transactions to export.',
                      '${data.periodLabel}: निर्यात गर्न कारोबार छैन।',
                    )
                  : context.t(
                      '${data.periodLabel}: $count transactions.',
                      '${data.periodLabel}: $count कारोबार।',
                    ),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey<String>('export-share'),
                    onPressed: count == 0
                        ? null
                        : () => Navigator.pop(context, (_period, true)),
                    icon: const Icon(Icons.ios_share_rounded, size: 18),
                    label: Text(context.t('Share', 'साझा गर्नुहोस्')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    key: const ValueKey<String>('export-save'),
                    onPressed: count == 0
                        ? null
                        : () => Navigator.pop(context, (_period, false)),
                    icon: const Icon(Icons.save_alt_rounded, size: 18),
                    label: Text(context.t('Save to phone', 'फोनमा सुरक्षित')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
