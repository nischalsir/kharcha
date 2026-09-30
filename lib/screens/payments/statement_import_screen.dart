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

/// Pick a bank-statement PDF, preview the parsed rows, and import the selected
/// ones as transactions.
class StatementImportScreen extends StatefulWidget {
  const StatementImportScreen({super.key});

  @override
  State<StatementImportScreen> createState() => _StatementImportScreenState();
}

class _StatementImportScreenState extends State<StatementImportScreen> {
  final StatementImportService _service = StatementImportService();

  bool _busy = false;
  bool _importing = false;
  String? _error;
  List<StatementEntry>? _entries;

  Future<void> _pickAndParse() async {
    if (_busy) return;
    final PlatformFile? file = await FilePicker.pickFile(
      dialogTitle: 'Choose a bank statement',
      type: FileType.custom,
      allowedExtensions: const <String>['pdf'],
    );
    if (file == null) return;

    setState(() {
      _busy = true;
      _error = null;
      _entries = null;
    });
    try {
      final bytes = await file.readAsBytes();
      final entries = await _service.parsePdf(bytes);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _entries = entries;
      });
      if (entries.isEmpty && mounted) {
        showMessage(
          context,
          context.t(
            'No transactions found in this PDF.',
            'यो PDF मा कुनै कारोबार भेटिएन।',
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = AppFailure.from(error).message;
      });
    }
  }

  Future<void> _import() async {
    final entries = _entries;
    if (entries == null || _importing) return;
    final selected = entries.where((e) => e.selected).toList();
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
    for (final entry in selected) {
      try {
        await transactions.create(
          title: entry.title,
          amount: entry.amount,
          type: entry.type,
          occurredAt: entry.occurredAt,
          paymentMethod: entry.paymentMethod,
        );
        imported++;
      } catch (_) {
        // Skip rows that fail validation; report only successful imports.
      }
    }
    if (!mounted) return;
    setState(() => _importing = false);
    showMessage(
      context,
      context.t(
        'Imported $imported transactions.',
        '$imported वटा कारोबार आयात भयो।',
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = _entries;

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
            context.t('Import PDF', 'PDF बाट आयात'),
            style: theme.textTheme.titleLarge,
          ),
        ),
        body: SafeArea(
          child: entries == null
              ? _intro(context)
              : Column(
                  children: <Widget>[
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                        children: <Widget>[
                          _SummaryCard(entries: entries),
                          const SizedBox(height: 12),
                          _EntriesCard(
                            entries: entries,
                            onChanged: (entry, value) =>
                                setState(() => entry.selected = value),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                      child: PrimaryButton(
                        label: context.t(
                          'Import ${entries.where((e) => e.selected).length} '
                          'transactions',
                          '${entries.where((e) => e.selected).length} वटा '
                          'कारोबार आयात गर्नुहोस्',
                        ),
                        onPressed: _importing ? null : _import,
                        isLoading: _importing,
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
        GlassCard(
          strong: true,
          glow: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A84FF).withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.picture_as_pdf_rounded,
                      color: Color(0xFF0A84FF),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      context.t(
                        'Import from a bank statement',
                        'बैंक स्टेटमेन्टबाट आयात',
                      ),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                context.t(
                  'Choose a bank statement PDF. Kharcha reads the rows for '
                  'you, then you review and import the ones you want as '
                  'expenses and income.',
                  'बैंक स्टेटमेन्ट PDF छान्नुहोस्। खर्चाले पङ्क्तिहरू पढेर '
                  'देखाउँछ, अनि तपाईंले चाहेका कारोबारहरू खर्च र आम्दानीका '
                  'रूपमा आयात गर्न सक्नुहुन्छ।',
                ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: glass.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              PrimaryButton(
                label: context.t('Choose PDF', 'PDF छान्नुहोस्'),
                icon: Icons.upload_file_rounded,
                onPressed: _busy ? null : _pickAndParse,
                isLoading: _busy,
              ),
            ],
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
                  color: const Color(0xFFFF453A),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _error!,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.entries});

  final List<StatementEntry> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    final expenses =
        entries.where((e) => !e.isIncome).fold<double>(0, (s, e) => s + e.amount);
    final income =
        entries.where((e) => e.isIncome).fold<double>(0, (s, e) => s + e.amount);
    final expenseCount = entries.where((e) => !e.isIncome).length;
    final incomeCount = entries.where((e) => e.isIncome).length;

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
      child: Row(
        children: <Widget>[
          stat(
            context.t('$expenseCount expenses', '$expenseCount खर्च'),
            '- ${expenseCount == 0 ? '0' : _money(expenses)}',
            const Color(0xFFFF453A),
          ),
          const SizedBox(width: 12),
          stat(
            context.t('$incomeCount income', '$incomeCount आम्दानी'),
            '+ ${incomeCount == 0 ? '0' : _money(income)}',
            const Color(0xFF30D158),
          ),
        ],
      ),
    );
  }

  String _money(double value) {
    final text = value.toStringAsFixed(2);
    final parts = text.split('.');
    final whole = parts[0];
    return '$whole.${parts[1]}';
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
            if (i != 0) Divider(height: 1, color: glass.textTertiary.withValues(alpha: 0.2)),
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
    final color = entry.isIncome ? const Color(0xFF30D158) : const Color(0xFFFF453A);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Row(
        children: <Widget>[
          Checkbox(
            value: entry.selected,
            onChanged: (value) => onChanged(entry, value ?? false),
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
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '$dateLabel · ${entry.paymentMethod.label}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: glass.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${entry.isIncome ? '+' : '-'}${entry.amount.toStringAsFixed(2)}',
            style: theme.textTheme.titleSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
