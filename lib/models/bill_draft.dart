import '../core/utils/json_parsers.dart';

/// One line of a bill: something charged for, and how much.
///
/// A line can be a plain amount ("Rent, 12,000") or worked out from a meter
/// ("Electricity: 1,250 less 1,130 is 120 units, at 12 a unit").
class BillLine {
  const BillLine({
    required this.name,
    this.amount = 0,
    this.previousReading,
    this.currentReading,
    this.rate,
  });

  final String name;

  /// What is charged, for a plain line. Ignored for a metered one.
  final double amount;

  /// The meter last time and now, and the price of one unit. A line is
  /// metered when it has a [rate].
  final double? previousReading;
  final double? currentReading;
  final double? rate;

  bool get metered => rate != null;

  /// Units used: the meter now, less the meter before. Never below zero.
  double get units {
    final used = (currentReading ?? 0) - (previousReading ?? 0);
    return used < 0 ? 0 : used;
  }

  /// What this line comes to.
  double get total => roundMoney(metered ? units * (rate ?? 0) : amount);

  /// Whether there is anything on this line to put on a bill.
  bool get isFilled => name.trim().isNotEmpty && total > 0;

  BillLine copyWith({
    String? name,
    double? amount,
    double? Function()? previousReading,
    double? Function()? currentReading,
    double? Function()? rate,
  }) => BillLine(
    name: name ?? this.name,
    amount: amount ?? this.amount,
    previousReading: previousReading != null
        ? previousReading()
        : this.previousReading,
    currentReading: currentReading != null
        ? currentReading()
        : this.currentReading,
    rate: rate != null ? rate() : this.rate,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'amount': amount,
    'previous_reading': previousReading,
    'current_reading': currentReading,
    'rate': rate,
  };

  factory BillLine.fromJson(Map<String, dynamic> json) => BillLine(
    name: (json['name'] as String?) ?? '',
    amount: jsonDouble(json['amount']),
    previousReading: (json['previous_reading'] as num?)?.toDouble(),
    currentReading: (json['current_reading'] as num?)?.toDouble(),
    rate: (json['rate'] as num?)?.toDouble(),
  );
}

/// A bill being written: who it is from and to, what it is for, and its
/// lines. Not a record of money in the app; a paper to hand to someone.
class BillDraft {
  const BillDraft({
    required this.title,
    required this.date,
    this.from = '',
    this.to = '',
    this.period = '',
    this.number = '',
    this.lines = const <BillLine>[],
    this.notes = '',
  });

  /// The heading: "Rent bill".
  final String title;

  /// Who the bill is from, and who it is for.
  final String from;
  final String to;

  /// What it covers: "Ashwin 2083".
  final String period;

  /// A bill number, if the writer keeps one.
  final String number;
  final DateTime date;
  final List<BillLine> lines;
  final String notes;

  /// The lines that say something, in order.
  List<BillLine> get filledLines => <BillLine>[
    for (final line in lines)
      if (line.isFilled) line,
  ];

  double get total {
    var sum = 0.0;
    for (final line in filledLines) {
      sum += line.total;
    }
    return roundMoney(sum);
  }

  /// A monthly rent bill to start from: the usual lines, electricity by the
  /// meter, nothing filled in.
  factory BillDraft.rent({required DateTime date, String period = ''}) =>
      BillDraft(
        title: 'Rent bill',
        date: date,
        period: period,
        lines: const <BillLine>[
          BillLine(name: 'Rent'),
          BillLine(name: 'Water'),
          BillLine(name: 'Electricity', rate: 0),
          BillLine(name: 'Internet'),
          BillLine(name: 'Garbage'),
        ],
      );

  /// A utility bill with electricity and water by meter.
  factory BillDraft.utilities({required DateTime date, String period = ''}) =>
      BillDraft(
        title: 'Utility bill',
        date: date,
        period: period,
        lines: const <BillLine>[
          BillLine(name: 'Electricity', rate: 0),
          BillLine(name: 'Water', rate: 0),
          BillLine(name: 'Gas'),
        ],
      );

  /// A service bill for internet, cable, or phone.
  factory BillDraft.service({required DateTime date, String period = ''}) =>
      BillDraft(
        title: 'Service bill',
        date: date,
        period: period,
        lines: const <BillLine>[
          BillLine(name: 'Internet'),
          BillLine(name: 'Cable TV'),
          BillLine(name: 'Phone'),
        ],
      );

  /// A maintenance or housing society bill.
  factory BillDraft.maintenance(
          {required DateTime date, String period = ''}) =>
      BillDraft(
        title: 'Maintenance bill',
        date: date,
        period: period,
        lines: const <BillLine>[
          BillLine(name: 'Common area maintenance'),
          BillLine(name: 'Lift maintenance'),
          BillLine(name: 'Security'),
          BillLine(name: 'Parking'),
          BillLine(name: 'Clubhouse'),
        ],
      );

  /// An empty bill with one line to fill.
  factory BillDraft.blank({required DateTime date, String period = ''}) =>
      BillDraft(
        title: 'Bill',
        date: date,
        period: period,
        lines: const <BillLine>[BillLine(name: '')],
      );

  /// The same bill for the next time it is written: the people, the lines
  /// and the prices stay, the date and the period are the new ones, and each
  /// meter starts from where it was read last.
  BillDraft forNextTime({required DateTime date, required String period}) =>
      BillDraft(
        title: title,
        from: from,
        to: to,
        period: period,
        // A number is for one bill; the next one gets its own.
        number: '',
        date: date,
        notes: notes,
        lines: <BillLine>[
          for (final line in lines)
            line.metered
                ? line.copyWith(
                    previousReading: () =>
                        line.currentReading ?? line.previousReading,
                    currentReading: () => null,
                  )
                : line,
        ],
      );

  BillDraft copyWith({
    String? title,
    String? from,
    String? to,
    String? period,
    String? number,
    DateTime? date,
    List<BillLine>? lines,
    String? notes,
  }) => BillDraft(
    title: title ?? this.title,
    from: from ?? this.from,
    to: to ?? this.to,
    period: period ?? this.period,
    number: number ?? this.number,
    date: date ?? this.date,
    lines: lines ?? this.lines,
    notes: notes ?? this.notes,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'title': title,
    'from': from,
    'to': to,
    'period': period,
    'number': number,
    'date': date.toIso8601String(),
    'notes': notes,
    'lines': <Map<String, dynamic>>[for (final line in lines) line.toJson()],
  };

  /// Null when [json] is not a bill.
  static BillDraft? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final lines = json['lines'];
    return BillDraft(
      title: (json['title'] as String?) ?? 'Bill',
      from: (json['from'] as String?) ?? '',
      to: (json['to'] as String?) ?? '',
      period: (json['period'] as String?) ?? '',
      number: (json['number'] as String?) ?? '',
      date: jsonDateTime(json['date']) ?? DateTime.now(),
      notes: (json['notes'] as String?) ?? '',
      lines: <BillLine>[
        if (lines is List)
          for (final line in lines)
            if (line is Map) BillLine.fromJson(Map<String, dynamic>.from(line)),
      ],
    );
  }
}
