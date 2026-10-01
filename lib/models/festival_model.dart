import 'package:flutter/material.dart';

/// Category of an entry in the Nepali calendar.
///
/// Kept deliberately close to the values already stored for existing rows so
/// that data migrated from Supabase still parses.
enum FestivalCategory { national, religious, cultural, seasonal, other }

FestivalCategory festivalCategoryFromString(String value) {
  return FestivalCategory.values.firstWhere(
    (c) => c.name == value,
    orElse: () => FestivalCategory.other,
  );
}

/// How an entry's BS date is determined.
enum DateBasis {
  /// The BS date is definitional and does not move: Nepali New Year is always
  /// 1/1, Constitution Day is always 6/3, and so on. These are exact for every
  /// year in range.
  civil,

  /// The BS date follows the Nepali panchang, because the festival is defined by
  /// a lunar or astrological event, so the same festival lands on a different
  /// BS day every year. The recorded month/day is the published placement *for
  /// the year it is filed under*, taken from that year's gazetted calendar.
  panchang,
}

/// A single dated entry on the Nepali calendar.
///
/// The authoritative coordinates are the Bikram Sambat [bsMonth]/[bsDay] pair:
/// the Nepali calendar *is* the BS calendar, so an entry is defined by its BS
/// date and the Gregorian date is always derived from it. [gregorianDate] is
/// therefore computed, never hand-written, which is what keeps a festival from
/// drifting away from the BS day it belongs to.
@immutable
class Festival {
  const Festival({
    required this.id,
    required this.name,
    required this.nameNe,
    required this.bsYear,
    required this.bsMonth,
    required this.bsDay,
    required this.gregorianDate,
    required this.category,
    required this.description,
    this.tithi,
    this.isPublicHoliday = false,
    this.holidayNote,
    this.icon = 'celebration',
    this.imageAsset,
    this.imageCredit,
    this.dateBasis = DateBasis.civil,
  });

  final String id;

  /// English name.
  final String name;

  /// Nepali (Devanagari) name.
  final String nameNe;

  final int bsYear;
  final int bsMonth;
  final int bsDay;

  /// Gregorian date derived from the BS date above.
  final DateTime gregorianDate;

  final FestivalCategory category;

  final String description;

  /// Panchang tithi (e.g. 'शुक्ल पूर्णिमा', 'कृष्ण अष्टमी', 'दशमी').
  final String? tithi;

  /// True when the Government of Nepal observes a public holiday on the day.
  final bool isPublicHoliday;

  /// Scope qualifier published alongside the holiday, e.g.
  /// `Kathmandu Valley only`, `For women only`, `Terai districts`. Null for a
  /// holiday that applies nationwide.
  final String? holidayNote;

  final String icon;

  /// Bundled asset path of a photograph of this specific festival.
  /// Null when no licensed photograph was available, in which case the UI
  /// falls back to a themed icon rather than an unrelated image.
  final String? imageAsset;

  /// Where this festival's photograph is looked up, bundled or uploaded.
  ///
  /// Built from [id] alone, never the year, so a festival keeps the same
  /// picture every year it comes round.
  String get imagePath => imageAsset ?? 'assets/images/festivals/$id.jpg';

  /// Attribution for [imageAsset], required whenever an image is bundled.
  final String? imageCredit;

  /// Whether [bsMonth]/[bsDay] is definitional or panchang-derived.
  final DateBasis dateBasis;

  /// True when the recorded BS date is exact rather than a panchang convention.
  bool get isExactDate => dateBasis == DateBasis.civil;

  /// Whole days from [from] until this festival's Gregorian date. Zero means it
  /// falls today, negative means it has already passed.
  ///
  /// Only the date components of [from] are used, so a time component on the
  /// argument cannot skew the result by a day.
  int daysRemaining(DateTime from) => gregorianDate
      .difference(DateTime(from.year, from.month, from.day))
      .inDays;

  /// Localised title for the current app locale setting.
  String title({required bool devanagari}) => devanagari ? nameNe : name;

  IconData get iconData => _icons[icon] ?? Icons.event_rounded;

  @override
  bool operator ==(Object other) =>
      other is Festival &&
      other.id == id &&
      other.bsYear == bsYear &&
      other.bsMonth == bsMonth &&
      other.bsDay == bsDay;

  @override
  int get hashCode => Object.hash(id, bsYear, bsMonth, bsDay);

  factory Festival.fromJson(Map<String, dynamic> json) {
    final rawCategory = (json['category'] ?? json['type'] ?? 'other')
        .toString();
    return Festival(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      nameNe: (json['name_ne'] ?? json['nameNe'] ?? json['name'] ?? '')
          .toString(),
      bsYear: _asInt(json['bs_year'] ?? json['bsYear'] ?? json['year']) ?? 0,
      bsMonth:
          _asInt(json['bs_month'] ?? json['bsMonth'] ?? json['month']) ?? 0,
      bsDay: _asInt(json['bs_day'] ?? json['bsDay'] ?? json['day']) ?? 0,
      gregorianDate:
          DateTime.tryParse((json['gregorian_date'] ?? '').toString()) ??
          DateTime(1970),
      category: festivalCategoryFromString(rawCategory),
      description: (json['description'] ?? '').toString(),
      tithi: json['tithi'] as String?,
      isPublicHoliday:
          json['is_public_holiday'] == true || json['isPublicHoliday'] == true,
      holidayNote:
          json['holiday_note'] as String? ?? json['holidayNote'] as String?,
      icon: (json['icon'] ?? 'celebration').toString(),
      imageAsset: json['image_asset'] as String?,
      imageCredit: json['image_credit'] as String?,
      dateBasis: (json['date_basis'] ?? 'civil').toString() == 'panchang'
          ? DateBasis.panchang
          : DateBasis.civil,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'name_ne': nameNe,
    'bs_year': bsYear,
    'bs_month': bsMonth,
    'bs_day': bsDay,
    'gregorian_date': gregorianDate.toIso8601String(),
    'category': category.name,
    'description': description,
    'tithi': tithi,
    'is_public_holiday': isPublicHoliday,
    'holiday_note': holidayNote,
    'icon': icon,
    'image_asset': imageAsset,
    'image_credit': imageCredit,
    'date_basis': dateBasis.name,
  };

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}

const Map<String, IconData> _icons = <String, IconData>{
  'celebration': Icons.celebration_rounded,
  'new_year': Icons.waving_hand_rounded,
  'flag': Icons.flag_rounded,
  'star': Icons.star_rounded,
  'temple': Icons.account_balance,
  'book': Icons.menu_book_rounded,
  'lamp': Icons.local_fire_department_rounded,
  'moon': Icons.nightlight_round,
  'sun': Icons.wb_sunny_rounded,
  'flower': Icons.local_florist_rounded,
  'mountain': Icons.terrain_rounded,
  'bird': Icons.flutter_dash_rounded,
  'axe': Icons.architecture_rounded,
  'water': Icons.water_rounded,
  'swing': Icons.toys_rounded,
  'people': Icons.groups_rounded,
  'hands': Icons.volunteer_activism_rounded,
  'music': Icons.music_note_rounded,
  'school': Icons.school_rounded,
};
