import 'package:flutter/foundation.dart';

import '../data/festival_image_credits.g.dart';
import '../models/festival_model.dart';
import 'nepali_date_service.dart';

/// A calendar entry before its Gregorian date has been resolved.
///
/// The BS month/day pair is the authoritative coordinate; the Gregorian date is
/// derived from it per BS year at request time.
@immutable
class FestivalEntry {
  const FestivalEntry({
    required this.id,
    required this.name,
    required this.nameNe,
    required this.bsMonth,
    required this.bsDay,
    required this.category,
    required this.description,
    this.tithi,
    this.bsYear,
    this.isPublicHoliday = false,
    this.holidayNote,
    this.icon = 'celebration',
    this.dateBasis = DateBasis.civil,
  });

  final String id;
  final String name;
  final String nameNe;
  final int bsMonth;
  final int bsDay;
  final FestivalCategory category;
  final String description;
  final String? tithi;

  /// The BS year this entry is filed under, or null when the BS date is a fixed
  /// solar date that recurs every year.
  ///
  /// Lunar and astrological festivals must be filed under a specific year,
  /// because the tithi that defines them lands on a different BS day each year.
  /// Assigning them a single "typical" month/day is how this data set went wrong
  /// before: in BS 2083 an intercalary month pushed Dashain from Ashwin into
  /// Kartik and Tihar three weeks later, so a fixed table was off by weeks.
  final int? bsYear;

  final bool isPublicHoliday;

  /// Scope qualifier for [isPublicHoliday], e.g. `Kathmandu Valley only`.
  final String? holidayNote;

  final String icon;
  final DateBasis dateBasis;

  /// True when the BS date recurs in every year.
  bool get recursAnnually => bsYear == null;
}

/// A gazetted multi-day public holiday block, such as the seven days of Dashain
/// or the five days of Tihar.
@immutable
class HolidayBlock {
  const HolidayBlock({
    required this.name,
    required this.nameNe,
    required this.startMonth,
    required this.startDay,
    required this.endMonth,
    required this.endDay,
  });

  final String name;
  final String nameNe;
  final int startMonth;
  final int startDay;
  final int endMonth;
  final int endDay;
}

/// Serves the Nepali calendar's dated entries.
///
/// Entries come in two tiers, because "a festival date" is not one kind of fact:
///
/// * **Fixed solar dates** ([_annual]) are definitional. Nepali New Year is
///   always 1/1, Constitution Day is always 6/3, so the same BS day applies in
///   every year and the Gregorian date is derived from it directly.
/// * **Lunar and astrological dates** ([_yearEntries]) depend on the panchang,
///   so they are stored per BS year from that year's published calendar. There
///   is no default placement, because a "typical" one is wrong in most years.
///
/// A year with no entry in [_yearEntries] therefore reports only its fixed solar
/// dates. That is deliberate: the alternative is inventing a date.
class FestivalService {
  FestivalService(this._dates);

  final NepaliDateService _dates;

  /// BS years for which a gazetted calendar is bundled.
  static const List<int> _publishedYears = <int>[2083];

  /// Earliest and latest BS year with bundled year-specific data.
  static int get firstSupportedYear => _publishedYears.first;
  static int get lastSupportedYear => _publishedYears.last;

  /// Fixed solar BS dates. These are exact in every year, so they are not filed
  /// under a particular year.
  static const List<FestivalEntry> _annual = <FestivalEntry>[
    FestivalEntry(
      id: 'nepali-new-year',
      name: 'Nepali New Year',
      nameNe: 'नेपाली नयाँ वर्ष',
      bsMonth: 1,
      bsDay: 1,
      category: FestivalCategory.national,
      tithi: 'मेष संक्रान्ति (वैशाख १)',
      description:
          'The first day of the Nepali solar year, which begins on the new moon '
          'in Baisakh. It is a national public holiday, marked by the singing of '
          'Deuda songs in the first rays of the sun and by families welcoming the '
          'new year at home.',
      isPublicHoliday: true,
      icon: 'new_year',
    ),
    FestivalEntry(
      id: 'saune-sankranti',
      name: 'Saune Sankranti',
      nameNe: 'साउने संक्रान्ति',
      bsMonth: 4,
      bsDay: 1,
      category: FestivalCategory.seasonal,
      tithi: 'कर्कट संक्रान्ति (साउन १)',
      description:
          'The solar transit marking the holy month of Shrawan, celebrated with '
          'applying Mehendi, worshipping Lord Shiva, and preparing festive meals.',
      icon: 'sun',
    ),
    FestivalEntry(
      id: 'constitution-day',
      name: 'Constitution Day',
      nameNe: 'राष्ट्रिय संविधान दिवस',
      bsMonth: 6,
      bsDay: 3,
      category: FestivalCategory.national,
      tithi: 'आश्विन ३',
      description:
          'The Constitution of Nepal was promulgated on Ashwin 3, 2072, ending the '
          'monarchy and establishing the republic. A national public holiday.',
      isPublicHoliday: true,
      icon: 'book',
    ),
    FestivalEntry(
      id: 'martyrs-day',
      name: "Martyrs' Day",
      nameNe: 'शहीद दिवस',
      bsMonth: 10,
      bsDay: 16,
      category: FestivalCategory.national,
      tithi: 'माघ १६',
      description:
          "Shaheed Diwas remembers those who died in the 2006 People's Movement. "
          'The President confers Martyrs’ Medals and the day is a national public '
          'holiday.',
      isPublicHoliday: true,
      icon: 'flag',
    ),
    FestivalEntry(
      id: 'maghe-sankranti',
      name: 'Maghe Sankranti',
      nameNe: 'माघे संक्रान्ति',
      bsMonth: 10,
      bsDay: 1,
      category: FestivalCategory.seasonal,
      tithi: 'मकर संक्रान्ति (माघ १)',
      description:
          'The solar transit into Magh, the coldest month of the year, and the '
          'day the sun reaches the tropic of Capricorn. Families gather around a '
          'fire to roast sweet potatoes and sesame balls, and it is a national '
          'public holiday.',
      isPublicHoliday: true,
      icon: 'sun',
    ),
    FestivalEntry(
      id: 'poush-sankranti',
      name: 'Poush Sankranti',
      nameNe: 'पौष संक्रान्ति',
      bsMonth: 9,
      bsDay: 1,
      category: FestivalCategory.seasonal,
      tithi: 'धनु संक्रान्ति (पुस १)',
      description:
          'The solar transit into Poush, marking the start of the new lunar year '
          'in the Terai and of the mid-winter season. Rice and millet are cooked '
          'as an offering and eaten as a family meal.',
      icon: 'sun',
    ),
    FestivalEntry(
      id: 'gudi-yatra',
      name: 'Gudi Yatra',
      nameNe: 'गुडी यात्रा',
      bsMonth: 12,
      bsDay: 1,
      category: FestivalCategory.cultural,
      tithi: 'मीन संक्रान्ति (चैत १)',
      description:
          'The Newar new year. A gude, a pole wrapped in coloured cloth, is '
          'erected and gunusu dabu chari is towed through the streets, followed '
          'by masked Lakhey dances. It is a public holiday in Kathmandu Valley.',
      icon: 'temple',
    ),
  ];

  /// Year-specific dates published in the Ministry of Home Affairs list of
  /// public holidays for that BS year, plus the named days of the festival
  /// seasons it brackets.
  static const Map<int, List<FestivalEntry>>
  _yearEntries = <int, List<FestivalEntry>>{
    2083: <FestivalEntry>[
      FestivalEntry(
        id: 'international-labor-day',
        name: 'International Labor Day',
        nameNe: 'अन्तर्राष्ट्रिय मजदुर दिवस',
        bsYear: 2083,
        bsMonth: 1,
        bsDay: 18,
        category: FestivalCategory.national,
        description:
            'May Day, gazetted together with Chandi Purnima. A national public '
            'holiday for government offices and public entities.',
        isPublicHoliday: true,
        icon: 'people',
      ),
      FestivalEntry(
        id: 'ubhauli-parwa',
        name: 'Ubhauli Parwa',
        nameNe: 'उभौली पर्व',
        bsYear: 2083,
        bsMonth: 1,
        bsDay: 18,
        category: FestivalCategory.religious,
        description:
            'Buddha Purnima as kept in the Terai and Himalayan traditions, '
            'observed on the full moon of Baisakh. The same day is also called '
            'Chandi Purnima.',
        isPublicHoliday: true,
        holidayNote: 'Gazetted jointly with International Labor Day',
        icon: 'moon',
      ),
      FestivalEntry(
        id: 'republic-day',
        name: 'Republic Day',
        nameNe: 'गणतन्त्र दिवस',
        bsYear: 2083,
        bsMonth: 2,
        bsDay: 15,
        category: FestivalCategory.national,
        description:
            'Jestha 15 marks the proclamation of the republic after the '
            'abolition of the monarchy in 2072 BS. A national public holiday.',
        isPublicHoliday: true,
        icon: 'flag',
      ),
      FestivalEntry(
        id: 'buddha-jayanti',
        dateBasis: DateBasis.panchang,
        name: 'Buddha Jayanti',
        nameNe: 'बुद्ध जयन्ती',
        bsYear: 2083,
        bsMonth: 2,
        bsDay: 15,
        category: FestivalCategory.religious,
        description:
            'The birth, enlightenment and passing away of Lord Buddha. '
            'Lumbini, the birthplace, and monasteries across the country hold '
            'prayer meetings, processions and the lighting of butter lamps.',
        isPublicHoliday: true,
        holidayNote: 'Lumbini and hill tradition; the Terai date is Baisakh 18',
        icon: 'lamp',
      ),
      FestivalEntry(
        id: 'janai-purnima',
        dateBasis: DateBasis.panchang,
        name: 'Janai Purnima',
        nameNe: 'जनै पूर्णिमा',
        bsYear: 2083,
        bsMonth: 5,
        bsDay: 12,
        category: FestivalCategory.religious,
        description:
            'The full moon of Bhadra, known as Raksha Bandhan. Sisters tie a '
            'sacred thread, or rakhi, on their brothers’ wrists and feed them '
            'sweets. A national public holiday.',
        isPublicHoliday: true,
        icon: 'hands',
      ),
      FestivalEntry(
        id: 'gai-jatra',
        dateBasis: DateBasis.panchang,
        name: 'Gai Jatra',
        nameNe: 'गै जात्रा',
        bsYear: 2083,
        bsMonth: 5,
        bsDay: 13,
        category: FestivalCategory.cultural,
        description:
            'Communities in the Kathmandu Valley take a decorated cow through '
            'their neighbourhood, singing and dancing, to honour the cow and '
            'ask for rain at the end of the monsoon.',
        isPublicHoliday: true,
        holidayNote: 'Kathmandu Valley and Newar community only',
        icon: 'flower',
      ),
      FestivalEntry(
        id: 'krishna-janmastami',
        dateBasis: DateBasis.panchang,
        name: 'Krishna Janmastami',
        nameNe: 'श्रीकृष्ण जन्माष्टमी',
        bsYear: 2083,
        bsMonth: 5,
        bsDay: 19,
        category: FestivalCategory.religious,
        description:
            'The birth of Lord Krishna, celebrated with fasting, the singing of '
            'kirtan and the breaking of a pot of curd over the head. A '
            'national public holiday.',
        isPublicHoliday: true,
        icon: 'music',
      ),
      FestivalEntry(
        id: 'haritalika-teej',
        dateBasis: DateBasis.panchang,
        name: 'Haritalika Teej',
        nameNe: 'हरितालिका तीज',
        bsYear: 2083,
        bsMonth: 5,
        bsDay: 29,
        category: FestivalCategory.cultural,
        description:
            'Married women fast in honour of their husbands and offer green '
            'leaf offerings to Shiva, wearing red and yellow, singing Deuda '
            'songs and exchanging gifts of sweets.',
        isPublicHoliday: true,
        holidayNote: 'For women only',
        icon: 'flower',
      ),
      FestivalEntry(
        id: 'indra-jatra',
        dateBasis: DateBasis.panchang,
        name: 'Indra Jatra',
        nameNe: 'इन्द्र जात्रा',
        bsYear: 2083,
        bsMonth: 6,
        bsDay: 9,
        category: FestivalCategory.cultural,
        description:
            'The eight-day festival honouring the rain god Indra, which opens '
            'the eight-day festival of Indra Jatra in Kathmandu with the '
            'raising of a pole, chariot processions and Lakhey dances.',
        isPublicHoliday: true,
        holidayNote: 'Kathmandu Valley only',
        icon: 'mountain',
      ),
      FestivalEntry(
        id: 'jitiya-parwa',
        dateBasis: DateBasis.panchang,
        name: 'Jitiya Parwa',
        nameNe: 'जितिया पर्व',
        bsYear: 2083,
        bsMonth: 6,
        bsDay: 18,
        category: FestivalCategory.religious,
        description:
            'Women in the Terai offer arghya to the rising sun, singing '
            'Chhath songs, and fast for the whole day. The festival marks the '
            'victory of the mythical queen of the frogs.',
        isPublicHoliday: true,
        holidayNote: 'For women only',
        icon: 'sun',
      ),
      FestivalEntry(
        id: 'ghatasthapana',
        dateBasis: DateBasis.panchang,
        name: 'Ghatasthapana',
        nameNe: 'घटस्थापना',
        bsYear: 2083,
        bsMonth: 6,
        bsDay: 25,
        category: FestivalCategory.religious,
        description:
            'Dashain begins. The day after sowing barley in a pot, jamara '
            'barley is sown in a room purified with cow dung and a Ghat is '
            'established with a stone and a copper vessel, and worship begins '
            'at dusk. A national public holiday.',
        isPublicHoliday: true,
        icon: 'temple',
      ),
      FestivalEntry(
        id: 'phulpati',
        dateBasis: DateBasis.panchang,
        name: 'Phulpati',
        nameNe: 'फूलपाती',
        bsYear: 2083,
        bsMonth: 6,
        bsDay: 31,
        category: FestivalCategory.religious,
        description:
            'The seventh day of Dashain, when a heap of flowers, or ful, is '
            'offered to the matri goddess, and the formal Dashain holiday '
            'begins.',
        isPublicHoliday: true,
        icon: 'flower',
      ),
      FestivalEntry(
        id: 'maha-ashtami',
        dateBasis: DateBasis.panchang,
        name: 'Maha Ashtami',
        nameNe: 'महाअष्टमी',
        bsYear: 2083,
        bsMonth: 7,
        bsDay: 1,
        category: FestivalCategory.religious,
        description:
            'The eighth night of Dashain, Kalratri, the darkest and most '
            'solemn day of the festival. Devotees fast and offer torma to '
            'Durga in her fiercest form, and temples stay open all night. A '
            'national public holiday.',
        isPublicHoliday: true,
        icon: 'lamp',
      ),
      FestivalEntry(
        id: 'maha-navami',
        dateBasis: DateBasis.panchang,
        name: 'Maha Navami',
        nameNe: 'महानवमी',
        bsYear: 2083,
        bsMonth: 7,
        bsDay: 3,
        category: FestivalCategory.religious,
        description:
            'The ninth day of Dashain. Houses are washed and decorated, Durga '
            'is worshipped in her fullest form, and Vishwakarma Puja honours '
            'tools and vehicles. A national public holiday.',
        isPublicHoliday: true,
        icon: 'lamp',
      ),
      FestivalEntry(
        id: 'vijaya-dashami',
        dateBasis: DateBasis.panchang,
        name: 'Vijaya Dashami',
        nameNe: 'विजयादशमी',
        bsYear: 2083,
        bsMonth: 7,
        bsDay: 4,
        category: FestivalCategory.national,
        description:
            'Dashami, the tenth and final day of Dashain, marks Durga’s '
            'victory over Mahishasura. Kites are flown from morning until '
            'dusk, elders mark a tika and jamara on the forehead, and people '
            'travel home from the cities. A national public holiday and the '
            'busiest travel day of the year.',
        isPublicHoliday: true,
        icon: 'swing',
      ),
      FestivalEntry(
        id: 'kojagrat-pournima',
        dateBasis: DateBasis.panchang,
        name: 'Kojagrat Purnima',
        nameNe: 'कोजाग्रत पूर्णिमा',
        bsYear: 2083,
        bsMonth: 7,
        bsDay: 8,
        category: FestivalCategory.religious,
        description:
            'The full moon that closes Dashain. Kojagrat, an auspicious month '
            'for marriage, has begun, and the day is a favourite date for '
            'weddings and for Laxmi Puja at home.',
        icon: 'moon',
      ),
      FestivalEntry(
        id: 'kaag-tihar',
        dateBasis: DateBasis.panchang,
        name: 'Kaag Tihar',
        nameNe: 'काग तिहार',
        bsYear: 2083,
        bsMonth: 7,
        bsDay: 21,
        category: FestivalCategory.religious,
        description:
            'Tihar begins. Crows, the messengers of Yama, are fed on the '
            'rooftops at sunrise so that no sorrow is sent to the house.',
        icon: 'bird',
      ),
      FestivalEntry(
        id: 'kukur-tihar',
        dateBasis: DateBasis.panchang,
        name: 'Kukur Tihar',
        nameNe: 'कुकुर तिहार',
        bsYear: 2083,
        bsMonth: 7,
        bsDay: 22,
        category: FestivalCategory.cultural,
        description:
            'Dogs are garlanded with marigolds, fed delicacies and given a '
            'tika, and dogs with a lamp on their forehead walk the '
            'neighbourhood. In 2083 BS this day and Laxmi Puja fell on the '
            'same calendar day.',
        isPublicHoliday: true,
        icon: 'people',
      ),
      FestivalEntry(
        id: 'laxmi-puja',
        dateBasis: DateBasis.panchang,
        name: 'Laxmi Puja',
        nameNe: 'लक्ष्मी पूजा',
        bsYear: 2083,
        bsMonth: 7,
        bsDay: 22,
        category: FestivalCategory.national,
        description:
            'The Laxmi and Astitami Puja day. Houses and shops are cleaned, a '
            'rangoli is drawn to welcome the goddess, and oil lamps are lit '
            'and left burning through the night. It is the main day of '
            'Tihar and a national public holiday.',
        isPublicHoliday: true,
        icon: 'lamp',
      ),
      FestivalEntry(
        id: 'gai-tihar',
        dateBasis: DateBasis.panchang,
        name: 'Gai Tihar and Goru Tihar',
        nameNe: 'गाई तिहार',
        bsYear: 2083,
        bsMonth: 7,
        bsDay: 23,
        category: FestivalCategory.religious,
        description:
            'Oxen and cows are worshipped in the morning as Laxmi herself and '
            'as the giver of agricultural wealth, and fed the leftovers of '
            'Laxmi Puja.',
        isPublicHoliday: true,
        icon: 'flower',
      ),
      FestivalEntry(
        id: 'govardhan-puja-mha-puja',
        dateBasis: DateBasis.panchang,
        name: 'Govardhan Puja and Mha Puja',
        nameNe: 'गोवर्धन पूजा तथा म्ह पूजा',
        bsYear: 2083,
        bsMonth: 7,
        bsDay: 24,
        category: FestivalCategory.religious,
        description:
            'Cattle are honoured on Goru Tihar, and Newars draw a mandala in '
            'the courtyard and worship themselves in Mha Puja, the day that '
            'also begins the Nepal Sambat new year. A national public '
            'holiday.',
        isPublicHoliday: true,
        icon: 'star',
      ),
      FestivalEntry(
        id: 'bhai-tika',
        dateBasis: DateBasis.panchang,
        name: 'Bhai Tika',
        nameNe: 'भाइटीका',
        bsYear: 2083,
        bsMonth: 7,
        bsDay: 25,
        category: FestivalCategory.national,
        description:
            'The last day of Tihar. Sisters give their brothers a '
            'seven-colour tika, an oil ritual, a makhani thread and a '
            'makhamali garland, and give and ask for a long-term blessing. It '
            'is the most important family day of Tihar and a national public '
            'holiday.',
        isPublicHoliday: true,
        icon: 'people',
      ),
      FestivalEntry(
        id: 'nahay-khay',
        dateBasis: DateBasis.panchang,
        name: 'Nahay Khay',
        nameNe: 'नहाय खाय',
        bsYear: 2083,
        bsMonth: 7,
        bsDay: 27,
        category: FestivalCategory.religious,
        description:
            'Chhath begins. Devotees bathe at dawn and eat a single simple '
            'meal of rice and lentils, preparing for the fast that follows.',
        icon: 'water',
      ),
      FestivalEntry(
        id: 'kharna',
        dateBasis: DateBasis.panchang,
        name: 'Kharna',
        nameNe: 'खरना',
        bsYear: 2083,
        bsMonth: 7,
        bsDay: 28,
        category: FestivalCategory.religious,
        description:
            'The second day of Chhath, a day-long fast that ends after sunset '
            'with kheer made of rice and milk.',
        icon: 'water',
      ),
      FestivalEntry(
        id: 'chhath',
        dateBasis: DateBasis.panchang,
        name: 'Sandhya Arghya',
        nameNe: 'संध्या अर्घ्या',
        bsYear: 2083,
        bsMonth: 7,
        bsDay: 29,
        category: FestivalCategory.religious,
        description:
            'The third and principal day of Chhath, the gazetted public '
            'holiday. At sunset, women in yellow saris stand in the river '
            'holding baskets of the first harvest aloft, offering arghya to '
            'the setting sun as thanks for a good crop.',
        isPublicHoliday: true,
        icon: 'water',
      ),
      FestivalEntry(
        id: 'usha-arghya',
        dateBasis: DateBasis.panchang,
        name: 'Usha Arghya',
        nameNe: 'उषा अर्घ्या',
        bsYear: 2083,
        bsMonth: 7,
        bsDay: 30,
        category: FestivalCategory.religious,
        description:
            'The final day of Chhath. The fast ends after the arghya is '
            'offered to the rising sun, and water buffalo are washed in the '
            'river.',
        icon: 'sun',
      ),
      FestivalEntry(
        id: 'international-disabilities-day',
        name: 'International Day of People with Disabilities',
        nameNe: 'अन्तर्राष्ट्रिय अपाङ्गता दिवस',
        bsYear: 2083,
        bsMonth: 8,
        bsDay: 17,
        category: FestivalCategory.other,
        description:
            'Observed since 1992 to raise awareness of the rights and needs of '
            'persons with disabilities.',
        isPublicHoliday: true,
        holidayNote: 'For people with disabilities only',
        icon: 'people',
      ),
      FestivalEntry(
        id: 'dhanya-pournima',
        dateBasis: DateBasis.panchang,
        name: 'Dhanya Purnima',
        nameNe: 'धन्या पूर्णिमा',
        bsYear: 2083,
        bsMonth: 9,
        bsDay: 9,
        category: FestivalCategory.seasonal,
        description:
            'The harvest festival, when the last grain of the paddy harvest '
            'is brought in and eaten by the farmer, also called Udhauli '
            'Parwa in the eastern hills. A national public holiday.',
        isPublicHoliday: true,
        icon: 'sun',
      ),
      FestivalEntry(
        id: 'christmas-day',
        name: 'Christmas Day',
        nameNe: 'क्रिसमस डे',
        bsYear: 2083,
        bsMonth: 9,
        bsDay: 10,
        category: FestivalCategory.cultural,
        description:
            'A gazetted public holiday, observed by the Christian community.',
        isPublicHoliday: true,
        icon: 'star',
      ),
      FestivalEntry(
        id: 'tamu-lhosar',
        dateBasis: DateBasis.panchang,
        name: 'Tamu Lhosar',
        nameNe: 'तमु ल्होसार',
        bsYear: 2083,
        bsMonth: 9,
        bsDay: 15,
        category: FestivalCategory.cultural,
        description:
            'The Gurung and Tamu community celebrate the new year on the full '
            'moon of Poush with folk songs, dance and a feast of millet and '
            'rice wine. A national public holiday.',
        isPublicHoliday: true,
        icon: 'mountain',
      ),
      FestivalEntry(
        id: 'national-unity-day',
        name: 'National Unity Day',
        nameNe: 'राष्ट्रिय एकता दिवस',
        bsYear: 2083,
        bsMonth: 9,
        bsDay: 27,
        category: FestivalCategory.national,
        description:
            'Poush 27, the day King Prithvi Narayan Shah was born, observed as '
            'Prithvi Jayanti and as a call for national unity. A national '
            'public holiday.',
        isPublicHoliday: true,
        icon: 'people',
      ),
      FestivalEntry(
        id: 'sonam-lhosar',
        dateBasis: DateBasis.panchang,
        name: 'Sonam Lhosar',
        nameNe: 'सोनाम ल्होसार',
        bsYear: 2083,
        bsMonth: 10,
        bsDay: 24,
        category: FestivalCategory.cultural,
        description:
            'The Tamang community celebrates the new year by cleaning and '
            'whitewashing the house, worshipping the household deities and '
            'singing seasonal songs. A national public holiday.',
        isPublicHoliday: true,
        icon: 'mountain',
      ),
      FestivalEntry(
        id: 'basanta-panchami',
        dateBasis: DateBasis.panchang,
        name: 'Basanta Panchami',
        nameNe: 'बसन्त पञ्चमी',
        bsYear: 2083,
        bsMonth: 10,
        bsDay: 28,
        category: FestivalCategory.seasonal,
        description:
            'The first day of the month of Falgun marks the start of spring, '
            'when girls are married off in large numbers and the learned '
            'Mangal Shobhajatra procession is held.',
        isPublicHoliday: true,
        holidayNote: 'For educational institutions only',
        icon: 'flower',
      ),
      FestivalEntry(
        id: 'democracy-day',
        name: 'National Democracy Day',
        nameNe: 'राष्ट्रिय प्रजातन्त्र दिवस',
        bsYear: 2083,
        bsMonth: 11,
        bsDay: 7,
        category: FestivalCategory.national,
        description:
            'Democracy Day is fixed by the panchang rather than by the solar '
            'calendar, so its BS date moves from year to year; the gazette '
            'placed it on Falgun 7 in 2083 BS. A national public holiday.',
        isPublicHoliday: true,
        icon: 'flag',
      ),
      FestivalEntry(
        id: 'maha-shivaratri',
        dateBasis: DateBasis.panchang,
        name: 'Maha Shivaratri',
        nameNe: 'महाशिवरात्रि',
        bsYear: 2083,
        bsMonth: 11,
        bsDay: 22,
        category: FestivalCategory.religious,
        description:
            'The great night of Shiva, kept awake in the thousands at '
            'Pashupatinath and at every Shiva temple, with fasting, abhisheka '
            'and the singing of the night-long Shiva Bhajan. A national public '
            'holiday.',
        isPublicHoliday: true,
        icon: 'lamp',
      ),
      FestivalEntry(
        id: 'international-womens-day',
        name: "International Women's Day",
        nameNe: 'अन्तर्राष्ट्रिय नारी दिवस',
        bsYear: 2083,
        bsMonth: 11,
        bsDay: 24,
        category: FestivalCategory.other,
        description:
            'A gazetted holiday for women employees, marking the 1911 demand '
            'for women’s right to vote.',
        isPublicHoliday: true,
        holidayNote: 'For women employees only',
        icon: 'people',
      ),
      FestivalEntry(
        id: 'gyalpo-losar',
        dateBasis: DateBasis.panchang,
        name: 'Gyalpo Losar',
        nameNe: 'ग्याल्पो ल्होसार',
        bsYear: 2083,
        bsMonth: 11,
        bsDay: 25,
        category: FestivalCategory.cultural,
        description:
            'The Sherpa, Tamang and Tibetan-heritage communities mark the new '
            'year by cleaning their houses, boiling juniper and paying respect '
            'to the household deities. A national public holiday.',
        isPublicHoliday: true,
        icon: 'mountain',
      ),
      FestivalEntry(
        id: 'holi',
        dateBasis: DateBasis.panchang,
        name: 'Fagu Purnima (Holi)',
        nameNe: 'फाग पूर्णिमा',
        bsYear: 2083,
        bsMonth: 12,
        bsDay: 7,
        category: FestivalCategory.cultural,
        description:
            'The festival of colours, played with dry gulal and water on the '
            'full moon of Falgun, marking the coming of spring and the burning '
            'of Holika.',
        isPublicHoliday: true,
        holidayNote: 'Himalayan and hilly districts',
        icon: 'music',
      ),
      FestivalEntry(
        id: 'terai-holi',
        dateBasis: DateBasis.panchang,
        name: 'Terai Holi',
        nameNe: 'तराई होली',
        bsYear: 2083,
        bsMonth: 12,
        bsDay: 8,
        category: FestivalCategory.cultural,
        description:
            'The Terai communities follow a different tithi tradition and '
            'celebrate a day later than the hills, so Holi falls on Falgun 8 '
            'across the Terai districts.',
        isPublicHoliday: true,
        holidayNote: 'Terai districts only',
        icon: 'music',
      ),
      FestivalEntry(
        id: 'ghode-jatra',
        dateBasis: DateBasis.panchang,
        name: 'Ghode Jatra',
        nameNe: 'घोडे जात्रा',
        bsYear: 2083,
        bsMonth: 12,
        bsDay: 23,
        category: FestivalCategory.cultural,
        description:
            'Kathmandu Valley’s new year, on the day horses are released into '
            'the Bagmati river at Swayambhunath after being ridden in parade, '
            'closing the season of Indra Jatra and Patan Jatra.',
        isPublicHoliday: true,
        holidayNote: 'Kathmandu Valley only',
        icon: 'temple',
      ),
    ],
  };

  /// Gazetted multi-day holiday blocks, per BS year.
  static const Map<int, List<HolidayBlock>> _holidayBlocks =
      <int, List<HolidayBlock>>{
        2083: <HolidayBlock>[
          HolidayBlock(
            name: 'Dashain Holiday',
            nameNe: 'दशैं बिदा',
            startMonth: 6,
            startDay: 31,
            endMonth: 7,
            endDay: 6,
          ),
          HolidayBlock(
            name: 'Tihar Holiday',
            nameNe: 'तिहार बिदा',
            startMonth: 7,
            startDay: 22,
            endMonth: 7,
            endDay: 26,
          ),
        ],
      };

  /// Every known entry across every bundled year, in calendar order.
  ///
  /// Intended for data-integrity checks; use [forYear] to resolve a year.
  static List<FestivalEntry> get allEntries {
    final combined = <FestivalEntry>[
      ..._annual,
      for (final year in _publishedYears) ..._yearEntries[year]!,
    ];
    combined.sort((a, b) {
      final byMonth = a.bsMonth.compareTo(b.bsMonth);
      return byMonth != 0 ? byMonth : a.bsDay.compareTo(b.bsDay);
    });
    return combined;
  }

  /// Attribution line for a bundled photograph, e.g.
  /// `Photo: Jane Doe, CC BY-SA 4.0 — Wikimedia Commons`.
  static String creditLine(FestivalImageCredit credit) =>
      'Photo: ${credit.author}, ${credit.license} — ${credit.source}';

  /// The raw entries that apply to [bsYear]: the fixed solar dates plus that
  /// year's gazetted lunar and astrological dates.
  List<FestivalEntry> entriesForYear(int bsYear) => <FestivalEntry>[
    ..._annual,
    ...?_yearEntries[bsYear],
  ];

  /// True when a gazetted calendar is bundled for [bsYear].
  ///
  /// False means only the fixed solar dates are known, and the UI says so
  /// rather than filling the gap with estimated festival dates.
  bool hasYearData(int bsYear) => _yearEntries.containsKey(bsYear);

  /// The gazetted multi-day holiday blocks for [bsYear].
  List<HolidayBlock> holidayBlocks(int bsYear) =>
      List<HolidayBlock>.unmodifiable(_holidayBlocks[bsYear] ?? const []);

  /// Entries applicable to [bsYear], with Gregorian dates resolved.
  ///
  /// Each BS date is clamped to the real length of that BS month first, so a
  /// 29-day month can never produce Mangsir 30. The result is sorted by BS date
  /// rather than by the order the tables are authored in, so callers can rely on
  /// calendar order.
  List<Festival> forYear(int bsYear) {
    final resolved = <Festival>[];
    for (final entry in entriesForYear(bsYear)) {
      final safe = _dates.clamp(BsDate(bsYear, entry.bsMonth, entry.bsDay));
      final credit = festivalImageCredits[entry.id];
      resolved.add(
        Festival(
          id: entry.id,
          name: entry.name,
          nameNe: entry.nameNe,
          bsYear: safe.year,
          bsMonth: safe.month,
          bsDay: safe.day,
          gregorianDate: _dates.toGregorian(safe),
          category: entry.category,
          description: entry.description,
          tithi: entry.tithi,
          isPublicHoliday: entry.isPublicHoliday,
          holidayNote: entry.holidayNote,
          icon: entry.icon,
          imageAsset: credit?.assetPath,
          imageCredit: credit == null ? null : creditLine(credit),
          dateBasis: entry.dateBasis,
        ),
      );
    }
    resolved.sort((a, b) {
      final byMonth = a.bsMonth.compareTo(b.bsMonth);
      return byMonth != 0 ? byMonth : a.bsDay.compareTo(b.bsDay);
    });
    return resolved;
  }

  /// Entries falling on the given Bikram Sambat day, in calendar order.
  List<Festival> forDate(BsDate date) {
    final safe = _dates.clamp(date);
    return forYear(safe.year)
        .where((f) => f.bsMonth == safe.month && f.bsDay == safe.day)
        .toList(growable: false);
  }

  /// Entries falling on the given Gregorian day.
  ///
  /// Matches on the resolved Gregorian date rather than comparing timestamps,
  /// so a time component on the argument cannot cause a miss.
  List<Festival> forGregorian(DateTime date) => forDate(_dates.toBs(date));

  /// Every single-day public holiday in [bsYear], in calendar order.
  List<Festival> publicHolidays(int bsYear) =>
      forYear(bsYear).where((f) => f.isPublicHoliday).toList(growable: false);

  /// Every public holiday day in [bsYear], including the unnamed days inside a
  /// gazetted multi-day block such as Dashain or Tihar.
  Set<BsDate> publicHolidayDays(int bsYear) {
    final days = <BsDate>{
      for (final festival in publicHolidays(bsYear))
        BsDate(festival.bsYear, festival.bsMonth, festival.bsDay),
    };
    for (final block in holidayBlocks(bsYear)) {
      days.addAll(_blockDays(bsYear, block));
    }
    return days;
  }

  /// The gazetted holiday blocks covering [date], which may be a day that is a
  /// holiday only because it falls inside a block.
  List<HolidayBlock> holidayBlocksFor(BsDate date) {
    final safe = _dates.clamp(date);
    final covering = <HolidayBlock>[];
    for (final block in holidayBlocks(safe.year)) {
      if (_blockDays(safe.year, block).contains(safe)) covering.add(block);
    }
    return covering;
  }

  /// True when the given BS day is a public holiday of any scope.
  bool isPublicHoliday(BsDate date) {
    final safe = _dates.clamp(date);
    return publicHolidayDays(safe.year).contains(safe);
  }

  /// The single entry with [id] resolved for [bsYear], if it applies.
  Festival? byId(String id, int bsYear) {
    for (final festival in forYear(bsYear)) {
      if (festival.id == id) return festival;
    }
    return null;
  }

  /// True when a gazetted calendar is bundled for [bsYear].
  bool supportsYear(int bsYear) => hasYearData(bsYear);

  /// Expands a holiday block into the BS days it covers.
  ///
  /// Walks in Gregorian space and converts back, so a block that crosses a month
  /// boundary, as Dashain does from Ashwin into Kartik, needs no special cases.
  List<BsDate> _blockDays(int bsYear, HolidayBlock block) {
    final start = _dates.clamp(
      BsDate(bsYear, block.startMonth, block.startDay),
    );
    final end = _dates.clamp(BsDate(bsYear, block.endMonth, block.endDay));
    final last = _dates.toGregorian(end);
    final days = <BsDate>[];
    for (
      var day = _dates.toGregorian(start);
      !day.isAfter(last);
      day = day.add(const Duration(days: 1))
    ) {
      days.add(_dates.toBs(day));
    }
    return days;
  }
}
