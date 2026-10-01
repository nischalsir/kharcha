import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/errors/app_failure.dart';
import '../../core/l10n/app_l10n.dart';
import '../../core/router/route_paths.dart';
import '../../core/theme/app_theme.dart';
import '../../models/statement_entry.dart';
import '../../providers/transaction_provider.dart';
import '../../services/flamey_controller.dart';
import '../../services/incoming_file_service.dart';
import '../../services/statement_import_service.dart';
import '../../services/statement_importer.dart';
import '../../widgets/common/form_helpers.dart';
import '../../widgets/common/glass_background.dart';
import '../../widgets/common/glass_card.dart';
import '../../widgets/common/primary_button.dart';
import 'statement_guide_screen.dart';

/// Bring transactions in from a bank or wallet statement: pick the file (or
/// share it into the app from the bank's own app), review what was read, then
/// confirm. Nothing is saved before the confirmation.
///
/// There is nothing to choose before the file: whose statement it is, and
/// what kind of file, are worked out from the file itself.
///
/// This screen only shows things. Reading, duplicate detection and saving
/// are [StatementImporter]'s.
class StatementImportScreen extends StatefulWidget {
  const StatementImportScreen({
    super.key,
    this.service,
    this.initialResult,
    this.incoming,
    this.incomingFiles,
  });

  /// Replaces the server call in tests.
  final StatementImportService? service;

  /// Opens straight on the review of an already-parsed statement. Used by
  /// tests; the app always starts from a file.
  final StatementParseResult? initialResult;

  /// A file another app shared into Kharcha. It is read as soon as the screen
  /// opens, exactly as if it had been chosen here.
  final IncomingFile? incoming;

  /// Reads [incoming]. Only needed together with it.
  final IncomingFileService? incomingFiles;

  @override
  State<StatementImportScreen> createState() => _StatementImportScreenState();
}

class _StatementImportScreenState extends State<StatementImportScreen> {
  late final StatementImporter _importer = StatementImporter(
    transactions: context.read<TransactionProvider>(),
    service: widget.service,
  );

  bool _busy = false;
  bool _importing = false;
  String? _fileName;
  String? _error;
  StatementReadProblem? _problem;
  List<int> _unreadPages = const <int>[];
  StatementParseResult? _result;

  @override
  void initState() {
    super.initState();
    final incoming = widget.incoming;
    if (incoming != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _readShared(incoming),
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final initial = widget.initialResult;
    if (initial != null && _result == null) {
      _importer.markAlreadyImported(initial.entries);
      _result = initial;
    }
  }

  /// The download guides, one per kind of statement. Only for someone who
  /// does not have the file yet; importing never needs one picked.
  Future<void> _openGuides() async {
    final source = await showModalBottomSheet<StatementSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final source in StatementSource.values)
              ListTile(
                key: ValueKey<String>('guide-${source.id}'),
                leading: Icon(
                  _sourceLook[source]!.$1,
                  color: _sourceLook[source]!.$2,
                ),
                title: Text(_sourceTitle(sheetContext, source)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pop(sheetContext, source),
              ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => StatementGuideScreen(source: source),
      ),
    );
  }

  /// Ticks every row that can be imported, or unticks them all. Rows already
  /// in the app are never ticked.
  void _selectAll(bool value) {
    final result = _result;
    if (result == null) return;
    setState(() {
      for (final entry in result.entries) {
        entry.selected = value && !entry.alreadyImported;
      }
    });
  }

  Future<void> _pickAndParse() async {
    if (_busy) return;
    // Any file may be picked. Asking Android for only PDF, Excel and CSV
    // made it grey out every file whose type it does not label that way (a
    // download with an odd name, a sheet a wallet exports as plain data), so
    // a real statement could be seen but not tapped. What a file is is read
    // from its contents instead, and anything else is refused with a reason.
    final PlatformFile? file;
    try {
      file = await FilePicker.pickFile(
        dialogTitle: 'Choose a statement',
        type: FileType.any,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _problem = StatementReadProblem.unreadable;
        _error =
            'The file picker could not be opened. In your bank app or Files, '
            'tap Share on the statement and choose Kharcha instead.';
      });
      return;
    }
    // Backing out of the picker changes nothing.
    if (file == null || !mounted) return;
    await _read(file.name, file.readAsBytes);
  }

  /// A file shared into the app from somewhere else.
  Future<void> _readShared(IncomingFile file) async {
    if (!mounted) return;
    final service = widget.incomingFiles;
    if (file.error != null || file.path == null || service == null) {
      setState(() {
        _fileName = file.name;
        _problem = file.error == 'too_large'
            ? StatementReadProblem.tooLarge
            : StatementReadProblem.unreadable;
        _error = file.error == 'too_large'
            ? 'That file is too large. Statements up to 5 MB are supported. '
                  'Download a shorter period and import it in parts.'
            : 'Kharcha could not open the shared file. Save it to your phone '
                  'and choose it here instead.';
      });
      return;
    }
    if (!file.looksSupported) {
      await service.discard(file);
      if (!mounted) return;
      setState(() {
        _fileName = file.name;
        _problem = StatementReadProblem.unsupported;
        _error =
            'This is not a statement file Kharcha can read. Share a PDF, '
            'Excel (.xls, .xlsx) or CSV statement.';
      });
      return;
    }
    await _read(file.name, () => service.read(file));
  }

  Future<void> _read(String name, Future<Uint8List> Function() bytes) async {
    final flamey = FlameyController.maybeOf(context);
    setState(() {
      _busy = true;
      _fileName = name;
      _error = null;
      _problem = null;
      _unreadPages = const <int>[];
      _result = null;
    });
    flamey?.send(FlameyEvent.loading);
    try {
      final result = await _importer.read(await bytes());
      if (!mounted) return;
      flamey?.send(FlameyEvent.suggestion);
      setState(() {
        _busy = false;
        _result = result;
      });
    } catch (error) {
      if (!mounted) return;
      flamey?.send(FlameyEvent.error);
      final failure = AppFailure.from(error);
      setState(() {
        _busy = false;
        _error = failure.message;
        if (failure is StatementReadFailure) {
          _problem = failure.problem;
          _unreadPages = failure.unreadPages;
        } else {
          _problem = null;
        }
      });
    }
  }

  Future<void> _import() async {
    final result = _result;
    if (result == null || _importing) return;
    if (!result.entries.any((e) => e.selected)) {
      showMessage(
        context,
        context.t(
          'Select at least one transaction.',
          'कम्तीमा एउटा कारोबार छान्नुहोस्।',
        ),
      );
      return;
    }

    final flamey = FlameyController.maybeOf(context);
    setState(() => _importing = true);
    final outcome = await _importer.import(result.entries);
    if (!mounted) return;
    setState(() => _importing = false);
    final imported = outcome.imported;
    final failed = outcome.failed;
    flamey?.send(failed == 0 ? FlameyEvent.imported : FlameyEvent.error);
    showMessage(
      context,
      failed == 0
          ? context.t(
              'Imported $imported transactions.',
              '$imported वटा कारोबार आयात भयो।',
            )
          : context.t(
              'Imported $imported transactions. $failed could not be saved.',
              '$imported वटा कारोबार आयात भयो। $failed वटा सुरक्षित भएन।',
            ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result;
    final selectedCount = result?.entries.where((e) => e.selected).length ?? 0;
    // Rows that are not in the app yet. With none, there is nothing to
    // import, which is said outright rather than left as a dead button.
    final newCount =
        result?.entries.where((e) => !e.alreadyImported).length ?? 0;
    final nothingNew =
        result != null && result.entries.isNotEmpty && newCount == 0;

    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(
              Icons.arrow_back_rounded,
              color: theme.colorScheme.onSurface,
            ),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            context.t('Import statement', 'स्टेटमेन्ट आयात'),
            style: theme.textTheme.titleLarge,
          ),
        ),
        body: SafeArea(
          child: result == null
              ? _intro(context)
              : Column(
                  children: <Widget>[
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                        children: <Widget>[
                          _SummaryCard(result: result, fileName: _fileName),
                          if (nothingNew) ...<Widget>[
                            const SizedBox(height: 12),
                            _NothingNewCard(count: result.entries.length),
                          ],
                          if (result.unreadPages.isNotEmpty) ...<Widget>[
                            const SizedBox(height: 12),
                            _UnreadPagesCard(
                              pages: result.unreadPages,
                              pageCount: result.pageCount,
                            ),
                          ],
                          if (result.skipped.isNotEmpty) ...<Widget>[
                            const SizedBox(height: 12),
                            _SkippedCard(rows: result.skipped),
                          ],
                          const SizedBox(height: 12),
                          if (result.entries.isEmpty)
                            GlassCard(
                              child: Text(
                                context.t(
                                  'No transactions could be read from this '
                                      'file.',
                                  'यो फाइलबाट कुनै कारोबार पढ्न सकिएन।',
                                ),
                                style: theme.textTheme.bodyMedium,
                              ),
                            )
                          else
                            _EntriesCard(
                              entries: result.entries,
                              onChanged: (entry, value) =>
                                  setState(() => entry.selected = value),
                              onSelectAll: _selectAll,
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _importing
                                  ? null
                                  : () => setState(() => _result = null),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(50),
                              ),
                              child: Text(
                                nothingNew
                                    ? context.t('Another file', 'अर्को फाइल')
                                    : context.t('Cancel', 'रद्द गर्नुहोस्'),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: nothingNew
                                ? PrimaryButton(
                                    label: context.t('Done', 'सम्पन्न'),
                                    icon: Icons.check_rounded,
                                    onPressed: () => Navigator.pop(context),
                                  )
                                : PrimaryButton(
                                    label: context.t(
                                      'Import $selectedCount',
                                      '$selectedCount आयात गर्नुहोस्',
                                    ),
                                    icon: Icons.check_rounded,
                                    onPressed: _importing || selectedCount == 0
                                        ? null
                                        : _import,
                                    isLoading: _importing,
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

  static const Map<StatementSource, (IconData, Color)> _sourceLook =
      <StatementSource, (IconData, Color)>{
        StatementSource.bank: (
          Icons.account_balance_rounded,
          Color(0xFF0A84FF),
        ),
        StatementSource.esewa: (
          Icons.account_balance_wallet_rounded,
          Color(0xFF30D158),
        ),
        StatementSource.khalti: (Icons.wallet_rounded, Color(0xFF7D3CBF)),
        StatementSource.other: (Icons.description_rounded, Color(0xFFFF9F0A)),
      };

  String _sourceTitle(BuildContext context, StatementSource source) =>
      switch (source) {
        StatementSource.bank => context.t('Bank statement', 'बैंक स्टेटमेन्ट'),
        StatementSource.esewa => context.t(
          'eSewa statement',
          'eSewa स्टेटमेन्ट',
        ),
        StatementSource.khalti => context.t(
          'Khalti statement',
          'Khalti स्टेटमेन्ट',
        ),
        StatementSource.other => context.t(
          'Another wallet or app',
          'अर्को वालेट वा एप',
        ),
      };

  Widget _intro(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 48),
      children: <Widget>[
        Text(
          context.t(
            'Choose a statement file from your bank, eSewa, Khalti or any '
                'other wallet. Kharcha works out what it is from the file '
                'itself, and you review every row before anything is added.',
            'बैंक, eSewa, Khalti वा अरू कुनै वालेटको स्टेटमेन्ट फाइल '
                'छान्नुहोस्। फाइल के हो भन्ने Kharcha आफैँ पत्ता लगाउँछ, र केही '
                'थपिनुअघि हरेक पङ्क्ति तपाईंले जाँच्नुहुन्छ।',
          ),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: glass.textSecondary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 20),
        PrimaryButton(
          label: context.t('Choose file', 'फाइल छान्नुहोस्'),
          icon: Icons.upload_file_rounded,
          onPressed: _busy ? null : _pickAndParse,
          isLoading: _busy,
        ),
        if (_busy && _fileName != null) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            context.t('Reading $_fileName …', '$_fileName पढ्दै …'),
            textAlign: TextAlign.center,
            style: theme.textTheme.labelMedium?.copyWith(
              color: glass.textSecondary,
            ),
          ),
        ],
        const SizedBox(height: 10),
        Text(
          context.t(
            'Supported: PDF, Excel (.xls, .xlsx) and CSV, up to 5 MB.',
            'समर्थित: PDF, Excel (.xls, .xlsx) र CSV, ५ MB सम्म।',
          ),
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall?.copyWith(
            color: glass.textTertiary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 14),
        GlassCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                Icons.ios_share_rounded,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  context.t(
                    'Quicker: in your bank app or Files, tap Share on the '
                        'statement and choose Kharcha. It opens right here.',
                    'छिटो तरिका: बैंक एप वा Files मा स्टेटमेन्टको Share '
                        'थिचेर Kharcha छान्नुहोस्। यहीँ खुल्छ।',
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey<String>('open-guides'),
            onPressed: _busy ? null : _openGuides,
            icon: const Icon(Icons.help_outline_rounded, size: 18),
            label: Text(
              context.t(
                'How to download a statement',
                'स्टेटमेन्ट कसरी डाउनलोड गर्ने',
              ),
            ),
          ),
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: 12),
          _FailureCard(
            fileName: _fileName,
            message: _error!,
            problem: _problem,
            unreadPages: _unreadPages,
            onGuide: _openGuides,
            onAddManually: () =>
                Navigator.of(context).pushNamed(RoutePaths.addExpense),
          ),
        ],
      ],
    );
  }
}

/// What went wrong with a file, and what can be done instead.
class _FailureCard extends StatelessWidget {
  const _FailureCard({
    required this.fileName,
    required this.message,
    required this.problem,
    required this.unreadPages,
    required this.onGuide,
    required this.onAddManually,
  });

  final String? fileName;
  final String message;
  final StatementReadProblem? problem;
  final List<int> unreadPages;
  final VoidCallback onGuide;
  final VoidCallback onAddManually;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.error_outline_rounded, size: 20, color: glass.danger),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (fileName != null)
                      Text(
                        fileName!,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    Text(message, style: theme.textTheme.bodySmall),
                    if (unreadPages.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          context.t(
                            'Pages looked at with no transactions found: '
                                '${unreadPages.join(', ')}.',
                            'कारोबार नभेटिएका पृष्ठ: '
                                '${unreadPages.join(', ')}।',
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: glass.textSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            context.t(
              'Nothing was imported. You can choose another file above, or:',
              'केही आयात भएको छैन। माथिबाट अर्को फाइल छान्न सक्नुहुन्छ, वा:',
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: glass.textSecondary,
            ),
          ),
          Wrap(
            spacing: 4,
            children: <Widget>[
              TextButton.icon(
                onPressed: onGuide,
                icon: const Icon(Icons.help_outline_rounded, size: 18),
                label: Text(
                  context.t('How to get the file', 'फाइल कसरी पाउने'),
                ),
              ),
              TextButton.icon(
                onPressed: onAddManually,
                icon: const Icon(Icons.edit_note_rounded, size: 18),
                label: Text(context.t('Add by hand', 'हातैले थप्नुहोस्')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Pages of the PDF that had text but no transaction that could be read.
class _UnreadPagesCard extends StatelessWidget {
  const _UnreadPagesCard({required this.pages, required this.pageCount});

  final List<int> pages;
  final int? pageCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    final list = pages.join(', ');
    return GlassCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.find_in_page_rounded, size: 20, color: glass.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              context.t(
                pages.length == 1
                    ? 'No transactions were found on page $list'
                          '${pageCount == null ? '' : ' of $pageCount'}. If '
                          'that page has some, check them against your '
                          'statement and add them by hand.'
                    : 'No transactions were found on pages $list'
                          '${pageCount == null ? '' : ' of $pageCount'}. If '
                          'those pages have some, check them against your '
                          'statement and add them by hand.',
                'पृष्ठ $list मा कारोबार भेटिएन। त्यहाँ कारोबार भए '
                'स्टेटमेन्टसँग मिलाएर हातैले थप्नुहोस्।',
              ),
              style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.result, this.fileName});

  final StatementParseResult result;
  final String? fileName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    final entries = result.entries;
    final expenses = entries
        .where((e) => !e.isIncome)
        .fold<double>(0, (s, e) => s + e.amount);
    final income = entries
        .where((e) => e.isIncome)
        .fold<double>(0, (s, e) => s + e.amount);
    final expenseCount = entries.where((e) => !e.isIncome).length;
    final incomeCount = entries.where((e) => e.isIncome).length;
    final already = entries.where((e) => e.alreadyImported).length;
    final warnings = result.warningCount;
    // The bank the statement names itself, when it does; otherwise the kind
    // of source it was read as.
    final from = result.provider ?? result.source.label;

    Widget stat(String label, String value, Color color) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: glass.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (fileName != null)
            Text(
              fileName!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: glass.textTertiary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          Text(
            context.t(
              '$from statement · ${entries.length} transactions found',
              '$from स्टेटमेन्ट · ${entries.length} कारोबार भेटियो',
            ),
            style: theme.textTheme.labelMedium?.copyWith(
              color: glass.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              stat(
                context.t('$expenseCount money out', '$expenseCount खर्च'),
                '- ${expenses.toStringAsFixed(2)}',
                glass.danger,
              ),
              const SizedBox(width: 12),
              stat(
                context.t('$incomeCount money in', '$incomeCount आम्दानी'),
                '+ ${income.toStringAsFixed(2)}',
                glass.success,
              ),
            ],
          ),
          if (result.balanceChecked && warnings == 0) ...<Widget>[
            const SizedBox(height: 10),
            _Note(
              icon: Icons.fact_check_rounded,
              color: glass.success,
              text: context.t(
                'Every amount agrees with the running balance printed on '
                    'the statement.',
                'हरेक रकम स्टेटमेन्टमा छापिएको ब्यालेन्ससँग मिल्छ।',
              ),
            ),
          ],
          if (warnings > 0) ...<Widget>[
            const SizedBox(height: 10),
            _Note(
              icon: Icons.warning_amber_rounded,
              color: glass.warning,
              text: context.t(
                '$warnings marked to check: they do not agree with the '
                    'statement\'s running balance. They are left unticked; '
                    'tick one only after comparing it with your statement.',
                '$warnings वटा जाँच्नुपर्ने: ती स्टेटमेन्टको ब्यालेन्ससँग '
                    'मिल्दैनन्। ती छानिएका छैनन्; स्टेटमेन्टसँग दाँजेर मात्र '
                    'छान्नुहोस्।',
              ),
            ),
          ],
          if (already > 0) ...<Widget>[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  Icons.verified_rounded,
                  size: 16,
                  color: glass.textSecondary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    context.t(
                      '$already already imported. They are left unticked so '
                          'nothing is added twice.',
                      '$already वटा पहिल्यै आयात भएका छन्। दोहोरो नथपियोस् '
                          'भनेर ती छानिएका छैनन्।',
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: glass.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: context.glass.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

/// Every row of the file is in the app already: said plainly, with where to
/// find them, so the review is not a list of boxes that cannot be ticked.
class _NothingNewCard extends StatelessWidget {
  const _NothingNewCard({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    return GlassCard(
      key: const ValueKey<String>('nothing-new'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.verified_rounded, size: 20, color: glass.success),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  context.t('Nothing new to import', 'आयात गर्न नयाँ केही छैन'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  context.t(
                    count == 1
                        ? 'The transaction in this file is already in '
                              'Kharcha. You can find it under Payments.'
                        : 'All $count transactions in this file are already '
                              'in Kharcha. You can find them under Payments.',
                    'यो फाइलका सबै $count कारोबार Kharcha मा पहिल्यै छन्। '
                    'ती Payments मा भेटिन्छन्।',
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Rows the statement had that could not be read with confidence.
class _SkippedCard extends StatelessWidget {
  const _SkippedCard({required this.rows});

  final List<SkippedStatementRow> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    return GlassCard(
      padding: EdgeInsets.zero,
      // The tile draws its ink on the nearest Material; without one of its
      // own it would paint behind the card and be invisible.
      child: Material(
        type: MaterialType.transparency,
        child: Theme(
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 16),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            leading: Icon(Icons.warning_amber_rounded, color: glass.warning),
            title: Text(
              context.t(
                rows.length == 1
                    ? '1 row could not be read'
                    : '${rows.length} rows could not be read',
                '${rows.length} पङ्क्ति पढ्न सकिएन',
              ),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: Text(
              context.t(
                rows.length == 1
                    ? 'It is left out, not guessed. Add it by hand if needed.'
                    : 'They are left out, not guessed. Add them by hand if '
                          'needed.',
                'ती छोडिएका छन्, अनुमान गरिएको छैन। चाहिए हातैले थप्नुहोस्।',
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: glass.textSecondary,
              ),
            ),
            children: <Widget>[
              for (final row in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        row.row > 0
                            ? context.t(
                                'Row ${row.row}: ${row.reason}',
                                'पङ्क्ति ${row.row}: ${row.reason}',
                              )
                            : row.page > 0
                            ? context.t(
                                'Page ${row.page}: ${row.reason}',
                                'पृष्ठ ${row.page}: ${row.reason}',
                              )
                            : row.reason,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (row.text.isNotEmpty)
                        Text(
                          row.text,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: glass.textSecondary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
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

class _EntriesCard extends StatelessWidget {
  const _EntriesCard({
    required this.entries,
    required this.onChanged,
    required this.onSelectAll,
  });

  final List<StatementEntry> entries;
  final void Function(StatementEntry entry, bool value) onChanged;
  final void Function(bool value) onSelectAll;

  @override
  Widget build(BuildContext context) {
    final glass = context.glass;
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      // The rows draw their ink on the nearest Material; without one of
      // their own it would paint behind the card.
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: <Widget>[
            _SelectAllRow(entries: entries, onSelectAll: onSelectAll),
            for (final entry in entries) ...<Widget>[
              Divider(
                height: 1,
                color: glass.textTertiary.withValues(alpha: 0.2),
              ),
              _EntryRow(entry: entry, onChanged: onChanged),
            ],
          ],
        ),
      ),
    );
  }
}

/// Ticks or unticks every row that can be imported, and says how many are
/// ticked.
class _SelectAllRow extends StatelessWidget {
  const _SelectAllRow({required this.entries, required this.onSelectAll});

  final List<StatementEntry> entries;
  final void Function(bool value) onSelectAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    final available = entries.where((e) => !e.alreadyImported).length;
    final selected = entries.where((e) => e.selected).length;
    final all = available > 0 && selected == available;
    final toggle = available == 0 ? null : () => onSelectAll(!all);
    return InkWell(
      key: const ValueKey<String>('select-all'),
      onTap: toggle,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 2, 14, 2),
        child: Row(
          children: <Widget>[
            Checkbox(
              // A dash while only some rows are ticked.
              tristate: true,
              value: all ? true : (selected == 0 ? false : null),
              onChanged: toggle == null ? null : (_) => toggle(),
              activeColor: theme.colorScheme.primary,
            ),
            Expanded(
              child: Text(
                context.t('Select all', 'सबै छान्नुहोस्'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              context.t(
                '$selected of $available selected',
                '$available मध्ये $selected छानिएको',
              ),
              style: theme.textTheme.labelMedium?.copyWith(
                color: glass.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry, required this.onChanged});

  final StatementEntry entry;
  final void Function(StatementEntry entry, bool value) onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    final date = entry.occurredAt;
    final dateLabel =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    final color = entry.isIncome ? glass.success : glass.danger;
    final direction = entry.isIncome
        ? context.t('Credit', 'जम्मा')
        : context.t('Debit', 'खर्च');
    final imported = entry.alreadyImported
        ? ' · ${context.t('Already imported', 'पहिल्यै आयात')}'
        : '';

    return InkWell(
      // The whole row ticks, not only the small box.
      onTap: entry.alreadyImported
          ? null
          : () => onChanged(entry, !entry.selected),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 14, 6),
        child: Row(
          children: <Widget>[
            Checkbox(
              value: entry.selected,
              // A row that is already in the app stays unticked: ticking it
              // would only write the same record again.
              onChanged: entry.alreadyImported
                  ? null
                  : (value) => onChanged(entry, value ?? false),
              activeColor: theme.colorScheme.primary,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    entry.title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: entry.alreadyImported ? glass.textSecondary : null,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '$dateLabel · $direction · ${entry.source.label}$imported',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: glass.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (entry.warning != null && !entry.alreadyImported)
                    Row(
                      children: <Widget>[
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 13,
                          color: glass.warning,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            context.t(
                              'Check: ${entry.warning}',
                              'जाँच्नुहोस्: स्टेटमेन्टको ब्यालेन्ससँग मिलेन',
                            ),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: glass.warning,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${entry.isIncome ? '+' : '-'}${entry.amount.toStringAsFixed(2)}',
              style: theme.textTheme.titleSmall?.copyWith(
                color: entry.alreadyImported ? glass.textSecondary : color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
