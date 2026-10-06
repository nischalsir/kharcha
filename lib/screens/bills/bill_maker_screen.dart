import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/l10n/app_l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../models/bill_draft.dart';
import '../../providers/auth_provider.dart';
import '../../services/bill_pdf.dart';
import '../../services/cache_service.dart';
import '../../services/nepali_date_service.dart';
import '../../widgets/common/form_helpers.dart';
import '../../widgets/common/glass_back_button.dart';
import '../../widgets/common/glass_background.dart';
import '../../widgets/common/glass_card.dart';
import '../../widgets/common/primary_button.dart';

/// Makes the PDF of a bill. Replaced in tests, where there is no PDF font
/// loader worth waiting for.
typedef BillPdfBuilder = Future<List<int>> Function(
  BillDraft bill, {
  String currency,
  String? dateLabel,
});

/// Write a bill and make a PDF of it: a monthly rent bill with rent, water
/// and electricity by the meter, or any bill of your own lines.
///
/// Nothing here is a transaction; it is a paper to hand to someone. The bill
/// is remembered on this phone, so next month only the readings change.
class BillMakerScreen extends StatefulWidget {
  const BillMakerScreen({super.key, this.now, this.buildPdf});

  /// "Today", fixed in tests.
  final DateTime? now;
  final BillPdfBuilder? buildPdf;

  @override
  State<BillMakerScreen> createState() => _BillMakerScreenState();
}

/// The text fields of one line of the bill.
class _LineFields {
  _LineFields(BillLine line)
    : name = TextEditingController(text: line.name),
      amount = TextEditingController(text: _number(line.amount)),
      previous = TextEditingController(text: _number(line.previousReading)),
      current = TextEditingController(text: _number(line.currentReading)),
      rate = TextEditingController(text: _number(line.rate)),
      metered = line.metered;

  final Key key = UniqueKey();
  final TextEditingController name;
  final TextEditingController amount;
  final TextEditingController previous;
  final TextEditingController current;
  final TextEditingController rate;
  bool metered;

  static String _number(double? value) =>
      value == null || value == 0 ? '' : BillPdf.plain(value);

  static double? _parse(String text) =>
      double.tryParse(text.replaceAll(',', '').trim());

  BillLine get line => BillLine(
    name: name.text.trim(),
    amount: _parse(amount.text) ?? 0,
    previousReading: metered ? _parse(previous.text) : null,
    currentReading: metered ? _parse(current.text) : null,
    rate: metered ? (_parse(rate.text) ?? 0) : null,
  );

  void dispose() {
    name.dispose();
    amount.dispose();
    previous.dispose();
    current.dispose();
    rate.dispose();
  }
}

class _BillMakerScreenState extends State<BillMakerScreen> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _from = TextEditingController();
  final TextEditingController _to = TextEditingController();
  final TextEditingController _period = TextEditingController();
  final TextEditingController _number = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  final List<_LineFields> _lines = <_LineFields>[];

  late DateTime _date;
  late final CacheService _cache = context.read<CacheService>();
  late final String _storeKey =
      'bill.draft.${context.read<AuthProvider>().userId ?? 'none'}';

  Timer? _saveTimer;

  /// Which of Share and Save is at work, if either.
  String? _busy;

  DateTime get _today => widget.now ?? DateTime.now();

  /// This month in words the PDF can draw: `Ashwin 2083`.
  String get _thisPeriod {
    final dates = context.read<NepaliDateService>();
    final bs = dates.toBs(_today);
    final label = dates.formatMonth(bs.year, bs.month);
    return BillPdf.latin(label).contains('?')
        ? '${dates.monthName(bs.month, useDevanagari: false)} ${bs.year}'
        : label;
  }

  @override
  void initState() {
    super.initState();
    BillDraft? saved;
    final raw = _cache.readSetting(_storeKey);
    if (raw != null) {
      try {
        saved = BillDraft.tryFromJson(jsonDecode(raw));
      } catch (_) {
        saved = null;
      }
    }
    final draft =
        saved ??
        BillDraft.rent(
          date: _today,
          period: _thisPeriod,
        ).copyWith(from: context.read<AuthProvider>().profileName ?? '');
    _fill(draft);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _save();
    for (final controller in <TextEditingController>[
      _title,
      _from,
      _to,
      _period,
      _number,
      _notes,
    ]) {
      controller.dispose();
    }
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  /// Puts [draft] into the fields, replacing what was there.
  void _fill(BillDraft draft) {
    _title.text = draft.title;
    _from.text = draft.from;
    _to.text = draft.to;
    _period.text = draft.period;
    _number.text = draft.number;
    _notes.text = draft.notes;
    _date = draft.date;
    for (final line in _lines) {
      line.dispose();
    }
    _lines
      ..clear()
      ..addAll(draft.lines.map(_LineFields.new));
    if (_lines.isEmpty) _lines.add(_LineFields(const BillLine(name: '')));
  }

  /// The bill as the fields have it now.
  BillDraft get _draft => BillDraft(
    title: _title.text.trim(),
    from: _from.text.trim(),
    to: _to.text.trim(),
    period: _period.text.trim(),
    number: _number.text.trim(),
    date: _date,
    notes: _notes.text.trim(),
    lines: <BillLine>[for (final line in _lines) line.line],
  );

  void _save() =>
      unawaited(_cache.writeSetting(_storeKey, jsonEncode(_draft.toJson())));

  /// Something was typed: show the new total, and remember the bill shortly.
  void _changed() {
    setState(() {});
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), _save);
  }

  Future<void> _startFrom(BillDraft Function() next, String name) async {
    final hasWork = _draft.filledLines.isNotEmpty;
    if (hasWork) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.t('Start $name?', '$name सुरु गर्ने?')),
          content: Text(
            context.t(
              'This replaces the bill you are writing now.',
              'यसले अहिले लेख्दै गरेको बिल हटाउँछ।',
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.t('Cancel', 'रद्द')),
            ),
            FilledButton(
              key: const ValueKey<String>('bill-replace'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.t('Start', 'सुरु')),
            ),
          ],
        ),
      );
      if (replace != true || !mounted) return;
    }
    setState(() => _fill(next()));
    _save();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(_today.year + 2),
    );
    if (picked == null || !mounted) return;
    _date = picked;
    _changed();
  }

  void _addLine() {
    _lines.add(_LineFields(const BillLine(name: '')));
    _changed();
  }

  void _removeLine(_LineFields line) {
    _lines.remove(line);
    line.dispose();
    if (_lines.isEmpty) _lines.add(_LineFields(const BillLine(name: '')));
    _changed();
  }

  Future<void> _make({required bool share}) async {
    if (_busy != null) return;
    final bill = _draft;
    if (bill.filledLines.isEmpty) {
      showMessage(
        context,
        context.t(
          'Add at least one line with a name and an amount.',
          'कम्तीमा एउटा नाम र रकम भएको लाइन थप्नुहोस्।',
        ),
      );
      return;
    }
    FocusScope.of(context).unfocus();
    final dateLabel = context.read<NepaliDateService>().format(bill.date);
    final saved = context.t('Bill saved as', 'बिल यो नाममा सुरक्षित भयो:');
    final failed = context.t(
      'Could not make the bill. Please try again.',
      'बिल बनाउन सकिएन। फेरि प्रयास गर्नुहोस्।',
    );
    setState(() => _busy = share ? 'share' : 'save');
    try {
      final build = widget.buildPdf ?? BillPdf.build;
      final bytes = Uint8List.fromList(
        await build(
          bill,
          currency: CurrencyFormatter.symbol,
          dateLabel: dateLabel,
        ),
      );
      final name = '${BillPdf.fileName(bill)}.pdf';
      if (!mounted) return;

      if (share) {
        final folder = Directory(
          '${(await getTemporaryDirectory()).path}/bills',
        )..createSync(recursive: true);
        final file = File('${folder.path}/$name')..writeAsBytesSync(bytes);
        if (!mounted) return;
        final box = context.findRenderObject() as RenderBox?;
        await SharePlus.instance.share(
          ShareParams(
            files: <XFile>[XFile(file.path, mimeType: 'application/pdf')],
            subject: bill.period.isEmpty
                ? bill.title
                : '${bill.title}: ${bill.period}',
            sharePositionOrigin: box == null
                ? null
                : box.localToGlobal(Offset.zero) & box.size,
          ),
        );
        return;
      }

      final path = await FilePicker.saveFile(
        dialogTitle: 'Save bill',
        fileName: name,
        bytes: bytes,
        mimeType: 'application/pdf',
      );
      // Backing out of the save dialog saves nothing and says nothing.
      if (path == null || !mounted) return;
      showMessage(context, '$saved $name');
    } catch (_) {
      if (mounted) showMessage(context, failed);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    final bill = _draft;
    final dates = context.read<NepaliDateService>();

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(
        text,
        style: theme.textTheme.labelMedium?.copyWith(
          color: glass.textSecondary,
          letterSpacing: 0.5,
        ),
      ),
    );

    Widget field(
      TextEditingController controller, {
      required String label,
      required IconData icon,
      String? hint,
      Key? key,
      bool number = false,
      int maxLines = 1,
      TextCapitalization capitalization = TextCapitalization.words,
    }) => TextField(
      key: key,
      controller: controller,
      maxLines: maxLines,
      textCapitalization: number ? TextCapitalization.none : capitalization,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : (maxLines > 1 ? TextInputType.multiline : TextInputType.text),
      inputFormatters: number
          ? <TextInputFormatter>[
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ]
          : null,
      decoration: buildInputDecoration(
        context,
        label: label,
        hint: hint,
        prefixIcon: icon,
      ),
      onChanged: (_) => _changed(),
    );

    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: Navigator.of(context).canPop()
              ? const GlassBackButton()
              : null,
          title: Text(
            context.t('Bill maker', 'बिल बनाउने'),
            style: theme.textTheme.titleLarge,
          ),
        ),
        bottomNavigationBar: _TotalBar(
          total: bill.total,
          busy: _busy,
          enabled: bill.filledLines.isNotEmpty,
          onShare: () => _make(share: true),
          onSave: () => _make(share: false),
        ),
        body: SafeArea(
          bottom: false,
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: <Widget>[
              heading(context.t('Start from', 'यसबाट सुरु गर्नुहोस्')),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  _StartChip(
                    key: const ValueKey<String>('bill-start-rent'),
                    icon: Icons.home_work_rounded,
                    label: context.t('Rent bill', 'भाडा बिल'),
                    onTap: () => _startFrom(
                      () => BillDraft.rent(
                        date: _today,
                        period: _thisPeriod,
                      ).copyWith(from: _from.text.trim(), to: _to.text.trim()),
                      context.t('a rent bill', 'भाडा बिल'),
                    ),
                  ),
                  _StartChip(
                    key: const ValueKey<String>('bill-start-next'),
                    icon: Icons.event_repeat_rounded,
                    label: context.t('Next month', 'अर्को महिना'),
                    onTap: () => _startFrom(
                      () =>
                          _draft.forNextTime(date: _today, period: _thisPeriod),
                      context.t('next month’s bill', 'अर्को महिनाको बिल'),
                    ),
                  ),
                  _StartChip(
                    key: const ValueKey<String>('bill-start-blank'),
                    icon: Icons.note_add_rounded,
                    label: context.t('Blank bill', 'खाली बिल'),
                    onTap: () => _startFrom(
                      () => BillDraft.blank(
                        date: _today,
                        period: _thisPeriod,
                      ).copyWith(from: _from.text.trim()),
                      context.t('a blank bill', 'खाली बिल'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              heading(context.t('The bill', 'बिल')),
              GlassCard(
                child: Column(
                  children: <Widget>[
                    field(
                      _title,
                      key: const ValueKey<String>('bill-title'),
                      label: context.t('Title', 'शीर्षक'),
                      hint: 'Rent bill',
                      icon: Icons.title_rounded,
                    ),
                    const SizedBox(height: 12),
                    field(
                      _period,
                      key: const ValueKey<String>('bill-period'),
                      label: context.t('For the month of', 'कुन महिनाको'),
                      hint: 'Ashwin 2083',
                      icon: Icons.calendar_month_rounded,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: InkWell(
                            key: const ValueKey<String>('bill-date'),
                            onTap: _pickDate,
                            borderRadius: BorderRadius.circular(12),
                            child: InputDecorator(
                              decoration: buildInputDecoration(
                                context,
                                label: context.t('Date', 'मिति'),
                                prefixIcon: Icons.event_rounded,
                              ),
                              child: Text(
                                dates.format(_date, style: BsFormat.short),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyLarge,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: field(
                            _number,
                            label: context.t('Bill no.', 'बिल नं.'),
                            hint: context.t('Optional', 'ऐच्छिक'),
                            icon: Icons.tag_rounded,
                            capitalization: TextCapitalization.characters,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              heading(context.t('From and to', 'कसबाट र कसलाई')),
              GlassCard(
                child: Column(
                  children: <Widget>[
                    field(
                      _from,
                      key: const ValueKey<String>('bill-from'),
                      label: context.t('Billed by', 'बिल दिने'),
                      hint: context.t('Your name', 'तपाईंको नाम'),
                      icon: Icons.person_rounded,
                    ),
                    const SizedBox(height: 12),
                    field(
                      _to,
                      key: const ValueKey<String>('bill-to'),
                      label: context.t('Billed to', 'बिल पाउने'),
                      hint: context.t(
                        'Tenant or customer',
                        'भाडावाल वा ग्राहक',
                      ),
                      icon: Icons.person_outline_rounded,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              heading(context.t('What it is for', 'केको लागि')),
              for (var i = 0; i < _lines.length; i++) ...<Widget>[
                _LineCard(
                  key: _lines[i].key,
                  index: i,
                  fields: _lines[i],
                  onChanged: _changed,
                  onRemove: () => _removeLine(_lines[i]),
                ),
                const SizedBox(height: 10),
              ],
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey<String>('bill-add-line'),
                  onPressed: _addLine,
                  icon: const Icon(Icons.add_rounded),
                  label: Text(context.t('Add a line', 'लाइन थप्नुहोस्')),
                ),
              ),
              const SizedBox(height: 12),
              heading(context.t('Note', 'टिप्पणी')),
              GlassCard(
                child: field(
                  _notes,
                  label: context.t('Note on the bill', 'बिलमा टिप्पणी'),
                  hint: context.t(
                    'Please pay by the 5th. eSewa: 98XXXXXXXX',
                    '५ गतेभित्र तिर्नुहोला। eSewa: 98XXXXXXXX',
                  ),
                  icon: Icons.sticky_note_2_outlined,
                  maxLines: 3,
                  capitalization: TextCapitalization.sentences,
                ),
              ),
              if (BillPdf.hasUndrawable(bill)) ...<Widget>[
                const SizedBox(height: 12),
                Row(
                  key: const ValueKey<String>('bill-nepali-warning'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      Icons.info_outline_rounded,
                      size: 18,
                      color: glass.warning,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        context.t(
                          'The PDF cannot draw Nepali letters yet; they come '
                              'out as "?". Please type the bill in English.',
                          'PDF ले अहिले नेपाली अक्षर देखाउन सक्दैन; ती "?" '
                              'बन्छन्। कृपया बिल अङ्ग्रेजीमा लेख्नुहोस्।',
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
        ),
      ),
    );
  }
}

/// A pill to start a bill from.
class _StartChip extends StatelessWidget {
  const _StartChip({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    return Material(
      color: primary.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 18, color: primary),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(color: primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One line of the bill: its name, and either an amount or a meter.
class _LineCard extends StatelessWidget {
  const _LineCard({
    super.key,
    required this.index,
    required this.fields,
    required this.onChanged,
    required this.onRemove,
  });

  final int index;
  final _LineFields fields;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    final line = fields.line;

    Widget number(
      TextEditingController controller,
      String label,
      IconData icon,
      String key,
    ) => TextField(
      key: ValueKey<String>('bill-line-$index-$key'),
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
      ],
      decoration: buildInputDecoration(context, label: label, prefixIcon: icon),
      onChanged: (_) => onChanged(),
    );

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  key: ValueKey<String>('bill-line-$index-name'),
                  controller: fields.name,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: buildInputDecoration(
                    context,
                    label: context.t('What for', 'केको'),
                    hint: context.t(
                      'Rent, water, electricity...',
                      'भाडा, पानी, बिजुली...',
                    ),
                    prefixIcon: Icons.receipt_long_rounded,
                  ),
                  onChanged: (_) => onChanged(),
                ),
              ),
              IconButton(
                key: ValueKey<String>('bill-line-$index-remove'),
                tooltip: context.t('Remove this line', 'यो लाइन हटाउनुहोस्'),
                onPressed: onRemove,
                icon: Icon(Icons.close_rounded, color: glass.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (fields.metered) ...<Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: number(
                    fields.previous,
                    context.t('Last reading', 'अघिल्लो रिडिङ'),
                    Icons.history_rounded,
                    'previous',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: number(
                    fields.current,
                    context.t('This reading', 'अहिलेको रिडिङ'),
                    Icons.speed_rounded,
                    'current',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            number(
              fields.rate,
              context.t('Price per unit', 'प्रति युनिट मूल्य'),
              Icons.bolt_rounded,
              'rate',
            ),
          ] else
            number(
              fields.amount,
              context.t('Amount', 'रकम'),
              Icons.payments_rounded,
              'amount',
            ),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              // By the meter, or a plain amount: a switch, like everywhere
              // else in the app.
              SizedBox(
                height: 36,
                child: FittedBox(
                  child: Switch(
                    key: ValueKey<String>('bill-line-$index-metered'),
                    value: fields.metered,
                    onChanged: (value) {
                      fields.metered = value;
                      onChanged();
                    },
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  fields.metered
                      ? context.t(
                          '${BillPdf.plain(line.units)} units used',
                          '${BillPdf.plain(line.units)} युनिट खपत',
                        )
                      : context.t('By meter reading', 'मिटर रिडिङ अनुसार'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: glass.textSecondary,
                  ),
                ),
              ),
              Text(
                CurrencyFormatter.format(line.total),
                key: ValueKey<String>('bill-line-$index-total'),
                style: theme.textTheme.titleSmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The total, and the two ways to take the bill away, kept in view under the
/// form.
class _TotalBar extends StatelessWidget {
  const _TotalBar({
    required this.total,
    required this.busy,
    required this.enabled,
    required this.onShare,
    required this.onSave,
  });

  final double total;
  final String? busy;
  final bool enabled;
  final VoidCallback onShare;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    // While typing, the bar rides on top of the keyboard and keeps to one
    // line, the total; the buttons come back when the keyboard goes.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final typing = keyboard > 0;
    return Material(
      color: theme.colorScheme.surface.withValues(alpha: 0.94),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 10, 20, 10 + keyboard),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      context.t('Total', 'जम्मा'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: glass.textSecondary,
                      ),
                    ),
                  ),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        CurrencyFormatter.format(total),
                        key: const ValueKey<String>('bill-total'),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (!typing) const SizedBox(height: 10),
              if (!typing)
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const ValueKey<String>('bill-save'),
                        onPressed: enabled && busy == null ? onSave : null,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.download_rounded),
                        label: Text(context.t('Save PDF', 'PDF सुरक्षित')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: PrimaryButton(
                        key: const ValueKey<String>('bill-share'),
                        label: context.t('Share PDF', 'PDF पठाउनुहोस्'),
                        icon: Icons.ios_share_rounded,
                        isLoading: busy == 'share',
                        onPressed: enabled && busy == null ? onShare : null,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
