import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/data/festival_image_credits.g.dart';
import 'package:kharcha_app/models/festival_model.dart';
import 'package:kharcha_app/services/festival_service.dart';
import 'package:kharcha_app/services/nepali_date_service.dart';

/// The Bikram Sambat and Gregorian dates printed side by side in the Ministry of
/// Home Affairs List of Public Holidays for 2083 BS, which was published on
/// 2082/11/18 and runs from 2083/01/01 (14 April 2026) to 2083/12/31
/// (13 April 2027).
///
/// This is the reference the bundled calendar is checked against. The pairs are
/// transcribed from the gazette, so any disagreement means either the entry
/// table or the BS calendar itself is wrong.
const List<List<Object>> _gazette2083 = <List<Object>>[
  <Object>[1, 1, 2026, 4, 14, 'New Year'],
  <Object>[1, 18, 2026, 5, 1, 'International Labor Day / Chandi Purnima'],
  <Object>[2, 15, 2026, 5, 29, 'Republic Day'],
  <Object>[5, 12, 2026, 8, 28, 'Rakshya Bandhan'],
  <Object>[5, 13, 2026, 8, 29, 'Gai Jatra'],
  <Object>[5, 19, 2026, 9, 4, 'Krishna Janmastami'],
  <Object>[5, 29, 2026, 9, 14, 'Haritalika Teej'],
  <Object>[6, 3, 2026, 9, 19, 'Constitution Day'],
  <Object>[6, 9, 2026, 9, 25, 'Indra Jatra'],
  <Object>[6, 18, 2026, 10, 4, 'Jitiya Parwa'],
  <Object>[6, 25, 2026, 10, 11, 'Gatasthapana'],
  <Object>[6, 31, 2026, 10, 17, 'Dashain Holiday begins (Phulpati)'],
  <Object>[7, 6, 2026, 10, 23, 'Dashain Holiday ends'],
  <Object>[7, 22, 2026, 11, 8, 'Tihar Holiday begins (Laxmi Puja)'],
  <Object>[7, 25, 2026, 11, 11, 'Falgunand Jayanti / Bhai Tika'],
  <Object>[7, 26, 2026, 11, 12, 'Tihar Holiday ends'],
  <Object>[7, 29, 2026, 11, 15, 'Chhat Parwa'],
  <Object>[8, 17, 2026, 12, 3, 'International Day of People with Disabilities'],
  <Object>[9, 9, 2026, 12, 24, 'Dhanya Purnima'],
  <Object>[9, 10, 2026, 12, 25, 'Christmas Day'],
  <Object>[9, 15, 2026, 12, 30, 'Tamu Lhosar'],
  <Object>[9, 27, 2027, 1, 11, 'Prithivi Jayanti / National Unity Day'],
  <Object>[10, 1, 2027, 1, 15, 'Maghi Parwa / Maghe Sankranti'],
  <Object>[10, 16, 2027, 1, 30, "Martyrs' Day"],
  <Object>[10, 24, 2027, 2, 7, 'Sonam Lhosar'],
  <Object>[10, 28, 2027, 2, 11, 'Basanta Panchami'],
  <Object>[11, 7, 2027, 2, 19, 'National Democracy Day'],
  <Object>[11, 22, 2027, 3, 6, 'Maha Shivaratri'],
  <Object>[11, 24, 2027, 3, 8, "International Women's Day"],
  <Object>[11, 25, 2027, 3, 9, 'Gyalpo Loshar'],
  <Object>[12, 7, 2027, 3, 21, 'Fagu Purnima'],
  <Object>[12, 8, 2027, 3, 22, 'Terai Holi'],
  <Object>[12, 23, 2027, 4, 6, 'Ghode Jatra'],
];

/// The festival days of the 2083 Dashain and Tihar seasons, with the BS dates
/// the published 2083 panchang places them on. An intercalary month in this year
/// pushed both seasons late, so these are exactly the dates a fixed month/day
/// table gets wrong.
const List<List<Object>> _festivals2083 = <List<Object>>[
  <Object>[6, 25, 2026, 10, 11, 'Ghatasthapana'],
  <Object>[6, 31, 2026, 10, 17, 'Phulpati'],
  <Object>[7, 1, 2026, 10, 18, 'Maha Ashtami'],
  <Object>[7, 3, 2026, 10, 20, 'Maha Navami'],
  <Object>[7, 4, 2026, 10, 21, 'Vijaya Dashami'],
  <Object>[7, 8, 2026, 10, 25, 'Kojagrat Purnima'],
  <Object>[7, 21, 2026, 11, 7, 'Kaag Tihar'],
  <Object>[7, 22, 2026, 11, 8, 'Kukur Tihar and Laxmi Puja'],
  <Object>[7, 23, 2026, 11, 9, 'Gai Tihar'],
  <Object>[7, 24, 2026, 11, 10, 'Govardhan Puja and Mha Puja'],
  <Object>[7, 25, 2026, 11, 11, 'Bhai Tika'],
  <Object>[7, 27, 2026, 11, 13, 'Nahay Khay'],
  <Object>[7, 28, 2026, 11, 14, 'Kharna'],
  <Object>[7, 29, 2026, 11, 15, 'Sandhya Arghya'],
  <Object>[7, 30, 2026, 11, 16, 'Usha Arghya'],
];

/// Tests for the calendar's dated entries.
///
/// Two things are checked. First, that the bundled dates are the gazetted ones
/// for 2083 BS, transcribed in [_gazette2083] and [_festivals2083]. Second,
/// that every entry is defined by its Bikram Sambat date and derives its
/// Gregorian date from it, so an entry can never sit on a Gregorian day that
/// contradicts the BS day it is named for.
void main() {
  final dates = NepaliDateService();
  final service = FestivalService(dates);

  BsDate bs(int month, int day) => BsDate(2083, month, day);

  DateTime ad(int y, int m, int d) => DateTime(y, m, d);

  group('2083 BS matches the gazetted calendar', () {
    test('every gazetted BS date converts to the published Gregorian date', () {
      for (final row in _gazette2083) {
        final label = row[5];
        expect(
          dates.toGregorian(bs(row[0] as int, row[1] as int)),
          ad(row[2] as int, row[3] as int, row[4] as int),
          reason: '$label is ${row[0]}/${row[1]} in the gazette',
        );
      }
    });

    test('the gazetted holidays are present on their published dates', () {
      // Each entry id, and the BS date the gazette prints beside it.
      const expected = <String, List<int>>{
        'international-labor-day': <int>[1, 18],
        'ubhauli-parwa': <int>[1, 18],
        'republic-day': <int>[2, 15],
        'janai-purnima': <int>[5, 12],
        'gai-jatra': <int>[5, 13],
        'krishna-janmastami': <int>[5, 19],
        'haritalika-teej': <int>[5, 29],
        'indra-jatra': <int>[6, 9],
        'jitiya-parwa': <int>[6, 18],
        'ghatasthapana': <int>[6, 25],
        'phulpati': <int>[6, 31],
        'maha-ashtami': <int>[7, 1],
        'maha-navami': <int>[7, 3],
        'vijaya-dashami': <int>[7, 4],
        'laxmi-puja': <int>[7, 22],
        'bhai-tika': <int>[7, 25],
        'chhath': <int>[7, 29],
        'international-disabilities-day': <int>[8, 17],
        'dhanya-pournima': <int>[9, 9],
        'christmas-day': <int>[9, 10],
        'tamu-lhosar': <int>[9, 15],
        'national-unity-day': <int>[9, 27],
        'sonam-lhosar': <int>[10, 24],
        'basanta-panchami': <int>[10, 28],
        'democracy-day': <int>[11, 7],
        'maha-shivaratri': <int>[11, 22],
        'international-womens-day': <int>[11, 24],
        'gyalpo-losar': <int>[11, 25],
        'holi': <int>[12, 7],
        'terai-holi': <int>[12, 8],
        'ghode-jatra': <int>[12, 23],
      };
      for (final id in expected.keys) {
        final festival = service.byId(id, 2083);
        expect(festival, isNotNull, reason: '$id is missing from 2083');
        expect(
          <int>[festival!.bsMonth, festival.bsDay],
          expected[id],
          reason: '$id moved off its gazetted date',
        );
        expect(festival.isPublicHoliday, isTrue, reason: '$id is gazetted');
      }
    });

    test('the festival seasons land on their published 2083 dates', () {
      const expected = <String, List<int>>{
        'ghatasthapana': <int>[6, 25],
        'phulpati': <int>[6, 31],
        'maha-ashtami': <int>[7, 1],
        'maha-navami': <int>[7, 3],
        'vijaya-dashami': <int>[7, 4],
        'kojagrat-pournima': <int>[7, 8],
        'kaag-tihar': <int>[7, 21],
        'kukur-tihar': <int>[7, 22],
        'laxmi-puja': <int>[7, 22],
        'gai-tihar': <int>[7, 23],
        'govardhan-puja-mha-puja': <int>[7, 24],
        'bhai-tika': <int>[7, 25],
        'nahay-khay': <int>[7, 27],
        'kharna': <int>[7, 28],
        'chhath': <int>[7, 29],
        'usha-arghya': <int>[7, 30],
      };
      for (final id in expected.keys) {
        final festival = service.byId(id, 2083);
        expect(festival, isNotNull, reason: '$id is missing from 2083');
        expect(
          <int>[festival!.bsMonth, festival.bsDay],
          expected[id],
          reason: '$id moved off its published 2083 date',
        );
      }
    });

    test('each published festival day converts to its Gregorian date', () {
      for (final row in _festivals2083) {
        final label = row[5];
        expect(
          dates.toGregorian(bs(row[0] as int, row[1] as int)),
          ad(row[2] as int, row[3] as int, row[4] as int),
          reason: '$label is ${row[0]}/${row[1]} in the 2083 panchang',
        );
      }
    });

    test(
      'Dashain and Tihar fall in Kartik in 2083, not Ashwin and Mangsir',
      () {
        // The intercalary month in 2083 is the whole reason a fixed month/day
        // table fails, so assert the shift explicitly.
        expect(service.byId('vijaya-dashami', 2083)!.bsMonth, 7);
        expect(service.byId('bhai-tika', 2083)!.bsMonth, 7);
        expect(service.byId('chhath', 2083)!.bsMonth, 7);
        expect(
          service.byId('vijaya-dashami', 2083)!.gregorianDate,
          DateTime(2026, 10, 21),
        );
        expect(
          service.byId('bhai-tika', 2083)!.gregorianDate,
          DateTime(2026, 11, 11),
        );
      },
    );
  });

  group('gazetted holiday blocks', () {
    test('the Dashain block covers Ashoj 31 to Kartik 6', () {
      final days = service.publicHolidayDays(2083);
      for (var day = 31; day <= 31; day++) {
        expect(days, contains(bs(6, day)), reason: 'Ashoj $day');
      }
      for (var day = 1; day <= 6; day++) {
        expect(days, contains(bs(7, day)), reason: 'Kartik $day');
      }
    });

    test('the Tihar block covers Kartik 22 to 26', () {
      final days = service.publicHolidayDays(2083);
      for (var day = 22; day <= 26; day++) {
        expect(days, contains(bs(7, day)), reason: 'Kartik $day');
      }
    });

    test('a day inside a block is a holiday even with no entry of its own', () {
      // Kartik 2 is inside the Dashain block and is not a named festival.
      expect(service.forDate(bs(7, 2)), isEmpty);
      expect(service.isPublicHoliday(bs(7, 2)), isTrue);
      expect(
        service.holidayBlocksFor(bs(7, 2)).map((b) => b.name),
        contains('Dashain Holiday'),
      );
    });

    test('a day outside every block is not a holiday', () {
      expect(service.isPublicHoliday(bs(1, 2)), isFalse);
      expect(service.holidayBlocksFor(bs(1, 2)), isEmpty);
    });
  });

  group('data integrity', () {
    test('every entry has a unique id', () {
      final ids = FestivalService.allEntries.map((e) => e.id).toList();
      expect(ids.toSet().length, ids.length, reason: 'duplicate entry id');
    });

    test('every entry has a name, a Nepali name and a description', () {
      for (final entry in FestivalService.allEntries) {
        expect(entry.name.trim(), isNotEmpty, reason: entry.id);
        expect(entry.nameNe.trim(), isNotEmpty, reason: entry.id);
        expect(entry.description.trim(), isNotEmpty, reason: entry.id);
      }
    });

    test('every entry names a real icon', () {
      const known = <String>{
        'celebration',
        'new_year',
        'flag',
        'star',
        'temple',
        'book',
        'lamp',
        'moon',
        'sun',
        'flower',
        'mountain',
        'bird',
        'axe',
        'water',
        'swing',
        'people',
        'hands',
        'music',
        'school',
      };
      for (final entry in FestivalService.allEntries) {
        expect(
          known,
          contains(entry.icon),
          reason: '${entry.id}: ${entry.icon}',
        );
      }
    });

    test('allEntries is sorted by BS month then day', () {
      final entries = FestivalService.allEntries;
      for (var i = 1; i < entries.length; i++) {
        final previous = entries[i - 1];
        final current = entries[i];
        final ordered =
            previous.bsMonth < current.bsMonth ||
            (previous.bsMonth == current.bsMonth &&
                previous.bsDay <= current.bsDay);
        expect(ordered, isTrue, reason: '${previous.id} before ${current.id}');
      }
    });

    test('a lunar entry is never filed without a year', () {
      // This is the invariant that keeps a "typical" date out of the data: an
      // entry whose date follows the panchang must name the year it applies to.
      for (final entry in FestivalService.allEntries) {
        if (entry.dateBasis == DateBasis.civil) continue;
        expect(entry.bsYear, isNotNull, reason: entry.id);
        expect(
          service.hasYearData(entry.bsYear!),
          isTrue,
          reason: '${entry.id} is filed under an unpublished year',
        );
      }
    });

    test('lunar festivals are classified as panchang, fixed days as civil', () {
      for (final id in <String>[
        'vijaya-dashami',
        'janai-purnima',
        'bhai-tika',
        'chhath',
        'holi',
        'maha-shivaratri',
        'indra-jatra',
      ]) {
        expect(
          service.byId(id, 2083)!.dateBasis,
          DateBasis.panchang,
          reason: '$id should follow the panchang',
        );
      }
      for (final id in <String>[
        'constitution-day',
        'democracy-day',
        'republic-day',
        'maghe-sankranti',
        'international-womens-day',
      ]) {
        expect(
          service.byId(id, 2083)!.dateBasis,
          DateBasis.civil,
          reason: '$id is a fixed calendar day',
        );
      }
    });

    test('a fixed date entry keeps its BS date in every year', () {
      for (final entry in FestivalService.allEntries) {
        if (entry.dateBasis != DateBasis.civil) continue;
        for (var year = 2080; year <= 2090; year++) {
          final resolved = service.byId(entry.id, year);
          if (resolved == null) continue;
          expect(resolved.bsMonth, entry.bsMonth, reason: '${entry.id} $year');
          expect(resolved.bsDay, entry.bsDay, reason: '${entry.id} $year');
        }
      }
    });
  });

  group('years without a gazetted calendar', () {
    test('only fixed dates are reported, and the year is flagged', () {
      expect(service.hasYearData(2084), isFalse);
      expect(service.supportsYear(2084), isFalse);
      final entries = service.forYear(2084);
      expect(entries, isNotEmpty);
      for (final festival in entries) {
        expect(festival.dateBasis, DateBasis.civil, reason: festival.id);
      }
    });

    test('a lunar festival is not guessed in an unpublished year', () {
      expect(service.byId('vijaya-dashami', 2084), isNull);
      expect(service.byId('holi', 2084), isNull);
      // A fixed date is still available.
      expect(service.byId('nepali-new-year', 2084), isNotNull);
    });

    test('Nepali New Year 2084 is 14 April 2027', () {
      expect(
        service.byId('nepali-new-year', 2084)!.gregorianDate,
        DateTime(2027, 4, 14),
      );
    });
  });

  group('Gregorian dates are derived from the BS date', () {
    test('every resolved Gregorian date matches its BS date', () {
      for (var year = 2080; year <= 2090; year++) {
        for (final festival in service.forYear(year)) {
          expect(
            dates.toBs(festival.gregorianDate),
            BsDate(festival.bsYear, festival.bsMonth, festival.bsDay),
            reason: '${festival.id} in $year contradicts its BS date',
          );
        }
      }
    });

    test('Nepali New Year 2083 is 14 April 2026', () {
      expect(
        service.byId('nepali-new-year', 2083)!.gregorianDate,
        DateTime(2026, 4, 14),
      );
    });

    test('dates are clamped to the real length of the BS month', () {
      for (var year = 2080; year <= 2090; year++) {
        for (final festival in service.forYear(year)) {
          expect(
            dates.isValid(
              BsDate(festival.bsYear, festival.bsMonth, festival.bsDay),
            ),
            isTrue,
            reason: '${festival.id} in $year is an impossible BS date',
          );
        }
      }
    });
  });

  group('lookup', () {
    test('forDate returns the entries on that BS day', () {
      final newYear = service.forDate(const BsDate(2083, 1, 1));
      expect(newYear.map((f) => f.id), contains('nepali-new-year'));
      for (final festival in newYear) {
        expect(festival.bsMonth, 1);
        expect(festival.bsDay, 1);
      }
    });

    test('two observances can share a day', () {
      // Kukur Tihar and Laxmi Puja fell on the same day in 2083.
      final ids = service.forDate(bs(7, 22)).map((f) => f.id).toSet();
      expect(ids, containsAll(<String>['kukur-tihar', 'laxmi-puja']));
    });

    test('forDate agrees with forGregorian', () {
      for (var day = 0; day < 400; day++) {
        final gregorian = DateTime(2026, 4, 14).add(Duration(days: day));
        final converted = dates.toBs(gregorian);
        expect(
          service.forGregorian(gregorian).map((f) => f.id).toList(),
          service.forDate(converted).map((f) => f.id).toList(),
          reason: 'disagreement on $gregorian ($converted)',
        );
      }
    });

    test('a time component does not change the result', () {
      final morning = service.forGregorian(DateTime(2026, 4, 14, 1));
      final evening = service.forGregorian(DateTime(2026, 4, 14, 23));
      expect(morning.map((f) => f.id), evening.map((f) => f.id));
    });

    test('a day with no entries returns an empty list', () {
      expect(service.forDate(const BsDate(2083, 1, 2)), isEmpty);
    });

    test('isPublicHoliday agrees with the entry flags and the blocks', () {
      final days = service.publicHolidayDays(2083);
      for (final festival in service.forYear(2083)) {
        if (!festival.isPublicHoliday) continue;
        expect(
          days,
          contains(BsDate(festival.bsYear, festival.bsMonth, festival.bsDay)),
          reason: festival.id,
        );
      }
    });

    test('Nepali New Year is a public holiday', () {
      expect(service.isPublicHoliday(const BsDate(2083, 1, 1)), isTrue);
      expect(
        service.publicHolidays(2083).map((f) => f.id),
        contains('nepali-new-year'),
      );
    });

    test('publicHolidays is in calendar order', () {
      for (var year = 2080; year <= 2090; year++) {
        final holidays = service.publicHolidays(year);
        for (var i = 1; i < holidays.length; i++) {
          final previous = holidays[i - 1];
          final current = holidays[i];
          expect(
            previous.bsMonth < current.bsMonth ||
                (previous.bsMonth == current.bsMonth &&
                    previous.bsDay <= current.bsDay),
            isTrue,
            reason: '${previous.id} out of order before ${current.id}',
          );
        }
      }
    });

    test('a regionally scoped holiday records its scope', () {
      expect(service.byId('indra-jatra', 2083)!.holidayNote, isNotNull);
      expect(service.byId('haritalika-teej', 2083)!.holidayNote, isNotNull);
      expect(service.byId('constitution-day', 2083)!.holidayNote, isNull);
    });

    test('byId returns null for an unknown id', () {
      expect(service.byId('not-a-real-festival', 2083), isNull);
    });
  });

  group('images', () {
    test('every bundled image credit points at a festival id', () {
      final ids = FestivalService.allEntries.map((e) => e.id).toSet();
      for (final id in festivalImageCredits.keys) {
        expect(ids, contains(id), reason: 'credit for unknown entry $id');
      }
    });

    test('every entry with an image has full attribution', () {
      for (var year = 2080; year <= 2090; year++) {
        for (final festival in service.forYear(year)) {
          if (festival.imageAsset == null) continue;
          final credit = festivalImageCredits[festival.id]!;
          expect(credit.assetPath, festival.imageAsset, reason: festival.id);
          expect(credit.author.trim(), isNotEmpty, reason: festival.id);
          expect(credit.license.trim(), isNotEmpty, reason: festival.id);
          expect(
            credit.source,
            startsWith('Wikimedia Commons'),
            reason: festival.id,
          );
          expect(
            festival.imageCredit,
            contains(credit.author),
            reason: festival.id,
          );
          expect(
            festival.imageCredit,
            contains(credit.license),
            reason: festival.id,
          );
        }
      }
    });

    test('asset paths are inside the festivals asset directory', () {
      for (final credit in festivalImageCredits.values) {
        expect(
          credit.assetPath,
          startsWith('assets/images/festivals/'),
          reason: credit.assetPath,
        );
        expect(credit.assetPath, endsWith('.jpg'), reason: credit.assetPath);
      }
    });

    test('only freely licensed images are used', () {
      for (final credit in festivalImageCredits.values) {
        expect(
          credit.license,
          anyOf(
            startsWith('CC '),
            startsWith('CC0'),
            startsWith('Public domain'),
          ),
          reason: '${credit.assetPath} is ${credit.license}',
        );
      }
    });
  });

  group('model', () {
    test('daysRemaining counts whole days regardless of time', () {
      final newYear = service.byId('nepali-new-year', 2083)!;
      expect(newYear.daysRemaining(DateTime(2026, 4, 14)), 0);
      expect(newYear.daysRemaining(DateTime(2026, 4, 14, 23, 59)), 0);
      expect(newYear.daysRemaining(DateTime(2026, 4, 13)), 1);
      expect(newYear.daysRemaining(DateTime(2026, 4, 15)), -1);
    });

    test('title switches on the devanagari setting', () {
      final newYear = service.byId('nepali-new-year', 2083)!;
      expect(newYear.title(devanagari: false), 'Nepali New Year');
      expect(newYear.title(devanagari: true), 'नेपाली नयाँ वर्ष');
    });

    test('survives a JSON round trip', () {
      final original = service.byId('bhai-tika', 2083)!;
      final restored = Festival.fromJson(original.toJson());
      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.nameNe, original.nameNe);
      expect(restored.bsYear, original.bsYear);
      expect(restored.bsMonth, original.bsMonth);
      expect(restored.bsDay, original.bsDay);
      expect(restored.gregorianDate, original.gregorianDate);
      expect(restored.isPublicHoliday, original.isPublicHoliday);
      expect(restored.holidayNote, original.holidayNote);
      expect(restored.category, original.category);
      expect(restored.dateBasis, original.dateBasis);
      expect(restored, original);
    });

    test('unknown categories fall back to other', () {
      expect(festivalCategoryFromString('nonsense'), FestivalCategory.other);
      expect(festivalCategoryFromString('national'), FestivalCategory.national);
    });
  });
}
