import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/services/festival_service.dart';
import 'package:kharcha_app/services/nepali_date_service.dart';
import 'package:kharcha_app/services/tithi_service.dart';

void main() {
  final tithi = TithiService();

  group('astronomy', () {
    test('full and new moons land on 180 and 0 degrees', () {
      // Published syzygies (UTC).
      final full = TithiService.elongation(DateTime.utc(2026, 8, 28, 4, 18));
      final newMoon = TithiService.elongation(DateTime.utc(2026, 11, 9, 7, 2));
      expect(full, closeTo(180, 0.3));
      expect(newMoon < 0.3 || newMoon > 359.7, isTrue, reason: '$newMoon');
    });

    test('Kathmandu sunrise is where it should be', () {
      // Nepal time is UTC+5:45.
      final june = TithiService.sunriseUtc(DateTime(2026, 6, 21))
          .add(const Duration(minutes: 345));
      final dec = TithiService.sunriseUtc(DateTime(2026, 12, 21))
          .add(const Duration(minutes: 345));
      expect(june.hour * 60 + june.minute, inInclusiveRange(5 * 60 + 5, 5 * 60 + 15));
      expect(dec.hour * 60 + dec.minute, inInclusiveRange(6 * 60 + 45, 6 * 60 + 58));
    });
  });

  test('matches the gazetted 2083 festivals kept by sunrise tithi', () {
    // Festivals observed by their sunrise (udaya) tithi. Ones kept by the
    // evening or midnight tithi (Laxmi Puja, Shivaratri, Kojagrat, Holi) are
    // deliberately excluded: the panchang places those by a different rule.
    const expected = <String, String>{
      'janai-purnima': 'Purnima',
      'gai-jatra': 'Krishna Pratipada',
      'krishna-janmastami': 'Krishna Ashtami',
      'haritalika-teej': 'Shukla Tritiya',
      'indra-jatra': 'Shukla Chaturdashi',
      'ghatasthapana': 'Shukla Pratipada',
      'maha-navami': 'Shukla Navami',
      'vijaya-dashami': 'Shukla Dashami',
      'bhai-tika': 'Shukla Dwitiya',
      'dhanya-pournima': 'Purnima',
      'basanta-panchami': 'Shukla Panchami',
    };
    final festivals = FestivalService(NepaliDateService()).forYear(2083);
    for (final entry in expected.entries) {
      final festival = festivals.firstWhere((f) => f.id == entry.key);
      expect(
        tithi.forDate(festival.gregorianDate).label(),
        entry.value,
        reason: entry.key,
      );
    }
  });

  test('labels in both languages', () {
    expect(const Tithi(14).label(), 'Purnima');
    expect(const Tithi(29).label(nepali: true), 'औंसी');
    expect(const Tithi(10).label(nepali: true), 'शुक्ल एकादशी');
    expect(const Tithi(25).isEkadashi, isTrue);
  });
}
