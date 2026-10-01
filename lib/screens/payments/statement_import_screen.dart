import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/errors/app_failure.dart';
import '../../core/l10n/app_l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../models/statement_entry.dart';
import '../../providers/transaction_provider.dart';
import '../../services/statement_import_service.dart';
import '../../widgets/common/form_helpers.dart';
import '../../widgets/common/glass_background.dart';
import '../../widgets/common/glass_card.dart';
import '../../widgets/common/primary_button.dart';
import 'statement_guide_screen.dart';

/// Bring transactions in from a bank or eSewa statement:
/// choose the source, see how to download it, pick the file, review what was
/// read, then confirm. Nothing is saved before the confirmation.
class StatementImportScreen extends StatefulWidget {
  const StatementImportScreen({super.key, this.service, this.initialResult});

  /// Replaces the server call in tests.
  final StatementImportService? service;

  /// Opens straight on the review of an already-parsed statement. Used by
  /// tests; the app always starts from the file picker.
  final StatementParseResult? initialResult;

  @override
  State<StatementImportScreen> createState() => _StatementImportScreenState();
}

class _StatementImportScreenState extends State<StatementImportScreen> {
  late final StatementImportService _service =
      widget.service ?? StatementImportService();

  bool _busy = false;
  bool _importing = false;
  String? _error;
  StatementParseResult? _result;

  static const List<String> _extensions = <String>['pdf', 'xls', 'xlsx', 'csv'];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final initial = widget.initialResult;
    if (initial != null && _result == null) {
      _markAlreadyImported(initial.entries);
      _result = initial;
    }
  }

  void _openGuide(StatementSource source) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => StatementGuideScreen(source: source),
      ),
    );
  }

  Future<void> _pickAndParse() async {
    if (_busy) return;
    final PlatformFile? file = await FilePicker.pickFile(
      dialogTitle: 'Choose a statement',
      type: FileType.custom,
      allowedExtensions: _extensions,
    );
    if (file == null) return;

    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final bytes = await file.readAsBytes();
      final result = await _service.parseStatement(bytes);
      if (!mounted) return;
      _markAlreadyImported(result.entries);
      setState(() {
        _busy = false;
        _result = result;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = AppFailure.from(error).message;
      });
    }
  }

  /// Flags rows that are already in the app and leaves them unticked, so
  /// importing a statement a second time adds nothing by default.
  void _markAlreadyImported(List<StatementEntry> entries) {
    final transactions = context.read<TransactionProvider>();
    // Rows brought in before imports had stable ids are matched by content.
    final known = transactions.statementMatchKeys();
    for (final entry in entries) {
      final imported =
          transactions.exists(entry.importId) || known.contains(entry.matchKey);
      entry.alreadyImported = imported;
      if (imported) entry.selected = false;
    }
  }

  Future<void> _import() async {
    final result = _result;
    if (result == null || _importing) return;
    final selected = result.entries.where((e) => e.selected).toList();
    if (selected.isEmpty) {
      showMessage(
        context,
        context.t(
          'Select at least one transaction.',
          'कम्तीमा एउटा कारोबार छान्नुहोस्।',
        ),
      );
      return;
    }

    final transactions = context.read<TransactionProvider>();
    setState(() => _importing = true);
    var imported = 0;
    var failed = 0;
    for (final entry in selected) {
      final ok = await transactions.create(
        // The same row always gets the same id, so it can only ever be one
        // record however many times the statement is imported.
        id: entry.importId,
        title: entry.title,
        amount: entry.amount,
        type: entry.type,
        occurredAt: entry.occurredAt,
        paymentMethod: entry.paymentMethod,
      );
      if (ok) {
        imported++;
      } else {
        failed++;
      }
    }
    if (!mounted) return;
    setState(() => _importing = false);
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
                          _SummaryCard(result: result),
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
                                context.t('Cancel', 'रद्द गर्नुहोस्'),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: PrimaryButton(
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

  Widget _intro(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 48),
      children: <Widget>[
        Text(
          context.t(
            'Download a statement from your bank or eSewa, then import the '
                'file here. You review every row before anything is added.',
            'आफ्नो बैंक वा eSewa बाट स्टेटमेन्ट डाउनलोड गरी यहाँ फाइल आयात '
                'गर्नुहोस्। केही थपिनुअघि हरेक पङ्क्ति तपाईंले जाँच्नुहुन्छ।',
          ),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: glass.textSecondary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 16),
        _SourceCard(
          icon: Icons.account_balance_rounded,
          color: const Color(0xFF0A84FF),
          title: context.t('Bank statement', 'बैंक स्टेटमेन्ट'),
          subtitle: context.t(
            'Any bank. Excel, CSV or PDF.',
            'जुनसुकै बैंक। Excel, CSV वा PDF।',
          ),
          onGuide: _busy ? null : () => _openGuide(StatementSource.bank),
        ),
        const SizedBox(height: 12),
        _SourceCard(
          icon: Icons.account_balance_wallet_rounded,
          color: const Color(0xFF30D158),
          title: context.t('eSewa statement', 'eSewa स्टेटमेन्ट'),
          subtitle: context.t(
            'The Excel (.xls) export from eSewa.',
            'eSewa बाट निकालिएको Excel (.xls) फाइल।',
          ),
          onGuide: _busy ? null : () => _openGuide(StatementSource.esewa),
        ),
        const SizedBox(height: 20),
        PrimaryButton(
          label: context.t('Choose file', 'फाइल छान्नुहोस्'),
          icon: Icons.upload_file_rounded,
          onPressed: _busy ? null : _pickAndParse,
          isLoading: _busy,
        ),
        const SizedBox(height: 10),
        Text(
          context.t(
            'Supported: PDF, Excel (.xls, .xlsx) and CSV, up to 5 MB. The '
                'file type and source are worked out from the file itself.',
            'समर्थित: PDF, Excel (.xls, .xlsx) र CSV, ५ MB सम्म। फाइलको '
                'प्रकार र स्रोत फाइलबाटै पत्ता लगाइन्छ।',
          ),
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall?.copyWith(
            color: glass.textTertiary,
            height: 1.4,
          ),
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: 16),
          GlassCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  Icons.error_outline_rounded,
                  size: 20,
                  color: glass.danger,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(_error!, style: theme.textTheme.bodySmall),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// One kind of statement, with the way into its download guide.
class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onGuide,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback? onGuide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    return GlassCard(
      onTap: onGuide,
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: glass.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onGuide,
            child: Text(context.t('How to get it', 'कसरी पाउने')),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.result});

  final StatementParseResult result;

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
          Text(
            context.t(
              '${result.source.label} statement · ${entries.length} '
                  'transactions found',
              '${result.source.label} स्टेटमेन्ट · ${entries.length} '
                  'कारोबार भेटियो',
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
                '${rows.length} rows could not be read',
                '${rows.length} पङ्क्ति पढ्न सकिएन',
              ),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: Text(
              context.t(
                'They are left out, not guessed. Add them by hand if needed.',
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
  const _EntriesCard({required this.entries, required this.onChanged});

  final List<StatementEntry> entries;
  final void Function(StatementEntry entry, bool value) onChanged;

  @override
  Widget build(BuildContext context) {
    final glass = context.glass;
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: <Widget>[
          for (var i = 0; i < entries.length; i++) ...<Widget>[
            if (i != 0)
              Divider(
                height: 1,
                color: glass.textTertiary.withValues(alpha: 0.2),
              ),
            _EntryRow(entry: entries[i], onChanged: onChanged),
          ],
        ],
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
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
    );
  }
}
