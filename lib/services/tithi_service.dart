import 'dart:math' as math;

/// One lunar day of the panchang.
class Tithi {
  const Tithi(this.index);

  /// 0..29. 0-14 are Shukla Pratipada..Purnima, 15-29 Krishna Pratipada..Aunsi.
  final int index;

  bool get isShukla => index < 15;

  /// 1..15 within the fortnight.
  int get number => index % 15 + 1;

  bool get isPurnima => index == 14;
  bool get isAunsi => index == 29;
  bool get isEkadashi => number == 11;

  static const List<String> _en = <String>[
    'Pratipada', 'Dwitiya', 'Tritiya', 'Chaturthi', 'Panchami', 'Shashthi',
    'Saptami', 'Ashtami', 'Navami', 'Dashami', 'Ekadashi', 'Dwadashi',
    'Trayodashi', 'Chaturdashi', //
  ];
  static const List<String> _ne = <String>[
    'प्रतिपदा', 'द्वितीया', 'तृतीया', 'चतुर्थी', 'पञ्चमी', 'षष्ठी', 'सप्तमी',
    'अष्टमी', 'नवमी', 'दशमी', 'एकादशी', 'द्वादशी', 'त्रयोदशी', 'चतुर्दशी', //
  ];

  String name({bool nepali = false}) {
    if (isPurnima) return nepali ? 'पूर्णिमा' : 'Purnima';
    if (isAunsi) return nepali ? 'औंसी' : 'Aunsi';
    return (nepali ? _ne : _en)[number - 1];
  }

  String paksha({bool nepali = false}) => isShukla
      ? (nepali ? 'शुक्ल पक्ष' : 'Shukla Paksha')
      : (nepali ? 'कृष्ण पक्ष' : 'Krishna Paksha');

  /// e.g. "Shukla Dashami" / "शुक्ल दशमी". Purnima and Aunsi stand alone.
  String label({bool nepali = false}) {
    if (isPurnima || isAunsi) return name(nepali: nepali);
    final side = isShukla
        ? (nepali ? 'शुक्ल' : 'Shukla')
        : (nepali ? 'कृष्ण' : 'Krishna');
    return '$side ${name(nepali: nepali)}';
  }

  @override
  bool operator ==(Object other) => other is Tithi && other.index == index;

  @override
  int get hashCode => index;
}

/// Computes the tithi the way the Nepali panchang assigns it: the tithi in
/// force at **sunrise in Kathmandu** (udaya tithi).
///
/// A tithi is each 12° of Moon-minus-Sun elongation. Positions come from
/// Meeus, *Astronomical Algorithms*: the Sun from ch. 25 and the Moon from the
/// main terms of ch. 47, good to a few arc-seconds, i.e. a tithi boundary to
/// within a couple of minutes. The only days that can differ from a printed
/// panchang are ones where a tithi changes within minutes of sunrise, which is
/// why the UI labels this as computed.
///
/// Pure and synchronous (~microseconds per day), so it is safe to call from
/// `build`, but results are memoised per day anyway.
class TithiService {
  TithiService();

  /// Shared, so the per-day memo survives rebuilds of the calendar.
  static final TithiService instance = TithiService();

  static const double _lat = 27.7172;
  static const double _lon = 85.3240;

  /// Approximate TT - UT for the 2020s/2030s, in seconds.
  static const double _deltaT = 70;

  final Map<int, Tithi> _cache = <int, Tithi>{};

  /// Tithi for a civil (Gregorian) date in Nepal.
  Tithi forDate(DateTime date) {
    final key = date.year * 10000 + date.month * 100 + date.day;
    return _cache[key] ??= Tithi(_indexAt(sunriseUtc(date)));
  }

  /// Sunrise in Kathmandu on [date], as a UTC instant (NOAA algorithm,
  /// refraction-corrected, accurate to about a minute).
  static DateTime sunriseUtc(DateTime date) {
    final noon = DateTime.utc(date.year, date.month, date.day, 6, 15);
    final jd = _julianDay(noon);
    final t = (jd - 2451545.0) / 36525.0;

    final l0 = _norm(280.46646 + t * (36000.76983 + t * 0.0003032));
    final m = 357.52911 + t * (35999.05029 - 0.0001537 * t);
    final e = 0.016708634 - t * (0.000042037 + 0.0000001267 * t);
    final c = _sin(m) * (1.914602 - t * (0.004817 + 0.000014 * t)) +
        _sin(2 * m) * (0.019993 - 0.000101 * t) +
        _sin(3 * m) * 0.000289;
    final omega = 125.04 - 1934.136 * t;
    final lambda = l0 + c - 0.00569 - 0.00478 * _sin(omega);
    final eps0 = 23 +
        (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) /
            60;
    final eps = eps0 + 0.00256 * _cos(omega);
    final decl = _asin(_sin(eps) * _sin(lambda));

    final y = math.pow(math.tan(_rad(eps / 2)), 2).toDouble();
    final eqTime = 4 *
        _deg(
          y * _sin(2 * l0) -
              2 * e * _sin(m) +
              4 * e * y * _sin(m) * _cos(2 * l0) -
              0.5 * y * y * _sin(4 * l0) -
              1.25 * e * e * _sin(2 * m),
        );

    final cosH = (_cos(90.833) - _sin(_lat) * _sin(decl)) /
        (_cos(_lat) * _cos(decl));
    final hourAngle = _deg(math.acos(cosH.clamp(-1.0, 1.0)));
    final minutesUtc = 720 - 4 * (_lon + hourAngle) - eqTime;

    return DateTime.utc(date.year, date.month, date.day)
        .add(Duration(seconds: (minutesUtc * 60).round()));
  }

  /// Moon-minus-Sun elongation in degrees, 0..360, at [instant].
  static double elongation(DateTime instant) {
    final jde = _julianDay(instant.toUtc()) + _deltaT / 86400.0;
    final t = (jde - 2451545.0) / 36525.0;
    return _norm(_moonLongitude(t) - _sunApparentLongitude(t));
  }

  static int _indexAt(DateTime instant) =>
      (elongation(instant) / 12).floor() % 30;

  // --- Sun (Meeus ch. 25) ---------------------------------------------------

  /// Nutation is omitted from both bodies because it cancels in the
  /// elongation; aberration applies to the Sun only.
  static double _sunApparentLongitude(double t) {
    final l0 = 280.46646 + t * (36000.76983 + t * 0.0003032);
    final m = 357.52911 + t * (35999.05029 - 0.0001537 * t);
    final c = _sin(m) * (1.914602 - t * (0.004817 + 0.000014 * t)) +
        _sin(2 * m) * (0.019993 - 0.000101 * t) +
        _sin(3 * m) * 0.000289;
    return _norm(l0 + c - 0.00569);
  }

  // --- Moon (Meeus ch. 47, periodic terms for longitude) --------------------

  // D, M, M', F, coefficient in 1e-6 degrees.
  static const List<List<int>> _moonTerms = <List<int>>[
    <int>[0, 0, 1, 0, 6288774],
    <int>[2, 0, -1, 0, 1274027],
    <int>[2, 0, 0, 0, 658314],
    <int>[0, 0, 2, 0, 213618],
    <int>[0, 1, 0, 0, -185116],
    <int>[0, 0, 0, 2, -114332],
    <int>[2, 0, -2, 0, 58793],
    <int>[2, -1, -1, 0, 57066],
    <int>[2, 0, 1, 0, 53322],
    <int>[2, -1, 0, 0, 45758],
    <int>[0, 1, -1, 0, -40923],
    <int>[1, 0, 0, 0, -34720],
    <int>[0, 1, 1, 0, -30383],
    <int>[2, 0, 0, -2, 15327],
    <int>[0, 0, 1, 2, -12528],
    <int>[0, 0, 1, -2, 10980],
    <int>[4, 0, -1, 0, 10675],
    <int>[0, 0, 3, 0, 10034],
    <int>[4, 0, -2, 0, 8548],
    <int>[2, 1, -1, 0, -7888],
    <int>[2, 1, 0, 0, -6766],
    <int>[1, 0, -1, 0, -5163],
    <int>[1, 1, 0, 0, 4987],
    <int>[2, -1, 1, 0, 4036],
    <int>[2, 0, 2, 0, 3994],
    <int>[4, 0, 0, 0, 3861],
    <int>[2, 0, -3, 0, 3665],
    <int>[0, 1, -2, 0, -2689],
    <int>[2, 0, -1, 2, -2602],
    <int>[2, -1, -2, 0, 2390],
    <int>[1, 0, 1, 0, -2348],
    <int>[2, -2, 0, 0, 2236],
    <int>[0, 1, 2, 0, -2120],
    <int>[0, 2, 0, 0, -2069],
    <int>[2, -2, -1, 0, 2048],
    <int>[2, 0, 1, -2, -1773],
    <int>[2, 0, 0, 2, -1595],
    <int>[4, -1, -1, 0, 1215],
    <int>[0, 0, 2, 2, -1110],
    <int>[3, 0, -1, 0, -892],
    <int>[2, 1, 1, 0, -810],
    <int>[4, -1, -2, 0, 759],
    <int>[0, 2, -1, 0, -713],
    <int>[2, 2, -1, 0, -700],
    <int>[2, 1, -2, 0, 691],
    <int>[2, -1, 0, -2, 596],
    <int>[4, 0, 1, 0, 549],
    <int>[0, 0, 4, 0, 537],
    <int>[4, -1, 0, 0, 520],
    <int>[1, 0, -2, 0, -487],
  ];

  static double _moonLongitude(double t) {
    final t2 = t * t, t3 = t2 * t, t4 = t3 * t;
    final lp = 218.3164477 + 481267.88123421 * t - 0.0015786 * t2 +
        t3 / 538841 - t4 / 65194000;
    final d = 297.8501921 + 445267.1114034 * t - 0.0018819 * t2 +
        t3 / 545868 - t4 / 113065000;
    final m = 357.5291092 + 35999.0502909 * t - 0.0001536 * t2 +
        t3 / 24490000;
    final mp = 134.9633964 + 477198.8675055 * t + 0.0087414 * t2 +
        t3 / 69699 - t4 / 14712000;
    final f = 93.2720950 + 483202.0175233 * t - 0.0036539 * t2 -
        t3 / 3526000 + t4 / 863310000;
    final e = 1 - 0.002516 * t - 0.0000074 * t2;

    var sum = 0.0;
    for (final term in _moonTerms) {
      var coeff = term[4].toDouble();
      final mMul = term[1].abs();
      if (mMul == 1) coeff *= e;
      if (mMul == 2) coeff *= e * e;
      sum += coeff * _sin(term[0] * d + term[1] * m + term[2] * mp + term[3] * f);
    }
    final a1 = 119.75 + 131.849 * t;
    final a2 = 53.09 + 479264.290 * t;
    sum += 3958 * _sin(a1) + 1962 * _sin(lp - f) + 318 * _sin(a2);
    return _norm(lp + sum / 1000000);
  }

  // --- helpers ----------------------------------------------------------------

  static double _julianDay(DateTime utc) =>
      utc.millisecondsSinceEpoch / 86400000.0 + 2440587.5;

  static double _norm(double deg) {
    final r = deg % 360;
    return r < 0 ? r + 360 : r;
  }

  static double _rad(double deg) => deg * math.pi / 180;
  static double _deg(double rad) => rad * 180 / math.pi;
  static double _sin(double deg) => math.sin(_rad(deg));
  static double _cos(double deg) => math.cos(_rad(deg));
  static double _asin(double x) => _deg(math.asin(x));
}
