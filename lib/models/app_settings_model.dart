import '../core/utils/json_parsers.dart';

enum AppThemeMode {
  system('system'),
  light('light'),
  dark('dark');

  const AppThemeMode(this.code);

  final String code;

  static AppThemeMode fromCode(String? code) {
    for (final mode in AppThemeMode.values) {
      if (mode.code == code) return mode;
    }
    return AppThemeMode.system;
  }
}

/// Which calendar the dates across the app are displayed in.
enum CalendarSystem {
  bs('bs'),
  ad('ad');

  const CalendarSystem(this.code);

  final String code;

  static CalendarSystem fromCode(String? code) {
    for (final system in CalendarSystem.values) {
      if (system.code == code) return system;
    }
    return CalendarSystem.bs;
  }
}

class NotificationPrefs {
  const NotificationPrefs({
    this.recurringReminders = true,
    this.budgetWarnings = true,
    this.friendDebtReminders = true,
    this.overdueReminders = true,
    this.dailySummary = false,
    this.weeklySummary = false,
    this.pasalMonthEnd = true,
    this.festivalReminders = true,
    this.aiContent = false,
    this.dailyBuddy = true,
    this.reminderHour = 9,
    this.dailySummaryHour = 21,
    this.utcOffsetMinutes,
  });

  final bool recurringReminders;
  final bool budgetWarnings;
  final bool friendDebtReminders;
  final bool overdueReminders;
  final bool dailySummary;
  final bool weeklySummary;
  final bool pasalMonthEnd;
  final bool festivalReminders;
  final bool aiContent;

  /// Good morning / good night / daytime nudges from the flame.
  final bool dailyBuddy;
  final int reminderHour;
  final int dailySummaryHour;

  /// Minutes east of UTC for the device, e.g. 345 for Nepal's +5:45.
  ///
  /// The two hour fields above are local times, so the server has to know where
  /// "local" is before it can honour them or judge quiet hours. An offset is
  /// used rather than a zone name because it needs no plugin and no timezone
  /// database, and because it stays exact for half-hour zones. Null until the
  /// app has reported it once, which the server treats as UTC.
  final int? utcOffsetMinutes;

  factory NotificationPrefs.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const NotificationPrefs();
    bool flag(String key, bool fallback) => (json[key] as bool?) ?? fallback;
    return NotificationPrefs(
      recurringReminders: flag('recurring_reminders', true),
      budgetWarnings: flag('budget_warnings', true),
      friendDebtReminders: flag('friend_debt_reminders', true),
      overdueReminders: flag('overdue_reminders', true),
      dailySummary: flag('daily_summary', false),
      weeklySummary: flag('weekly_summary', false),
      pasalMonthEnd: flag('pasal_month_end', true),
      festivalReminders: flag('festival_reminders', true),
      aiContent: flag('ai_content', false),
      dailyBuddy: flag('daily_buddy', true),
      reminderHour: jsonInt(json['reminder_hour'], fallback: 9),
      dailySummaryHour: jsonInt(json['daily_summary_hour'], fallback: 21),
      // Absent and zero are different: absent means this app has never
      // reported, which the server treats as UTC, and a real UTC device still
      // reports 0. Collapsing them would make a UTC user re-report forever.
      utcOffsetMinutes: json['utc_offset_minutes'] is num
          ? (json['utc_offset_minutes'] as num).toInt()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'recurring_reminders': recurringReminders,
      'budget_warnings': budgetWarnings,
      'friend_debt_reminders': friendDebtReminders,
      'overdue_reminders': overdueReminders,
      'daily_summary': dailySummary,
      'weekly_summary': weeklySummary,
      'pasal_month_end': pasalMonthEnd,
      'festival_reminders': festivalReminders,
      'ai_content': aiContent,
      'daily_buddy': dailyBuddy,
      'reminder_hour': reminderHour,
      'daily_summary_hour': dailySummaryHour,
      if (utcOffsetMinutes != null) 'utc_offset_minutes': utcOffsetMinutes,
    };
  }

  NotificationPrefs copyWith({
    bool? recurringReminders,
    bool? budgetWarnings,
    bool? friendDebtReminders,
    bool? overdueReminders,
    bool? dailySummary,
    bool? weeklySummary,
    bool? pasalMonthEnd,
    bool? festivalReminders,
    bool? aiContent,
    bool? dailyBuddy,
    int? reminderHour,
    int? dailySummaryHour,
    int? utcOffsetMinutes,
  }) {
    return NotificationPrefs(
      recurringReminders: recurringReminders ?? this.recurringReminders,
      budgetWarnings: budgetWarnings ?? this.budgetWarnings,
      friendDebtReminders: friendDebtReminders ?? this.friendDebtReminders,
      overdueReminders: overdueReminders ?? this.overdueReminders,
      dailySummary: dailySummary ?? this.dailySummary,
      weeklySummary: weeklySummary ?? this.weeklySummary,
      pasalMonthEnd: pasalMonthEnd ?? this.pasalMonthEnd,
      festivalReminders: festivalReminders ?? this.festivalReminders,
      aiContent: aiContent ?? this.aiContent,
      dailyBuddy: dailyBuddy ?? this.dailyBuddy,
      reminderHour: reminderHour ?? this.reminderHour,
      dailySummaryHour: dailySummaryHour ?? this.dailySummaryHour,
      utcOffsetMinutes: utcOffsetMinutes ?? this.utcOffsetMinutes,
    );
  }
}

enum UserGender { male, female, other, preferNotToSay }

class UserProfile {
  const UserProfile({
    this.fullName,
    this.gender,
    this.birthDate,
    this.age,
  });

  final String? fullName;
  final UserGender? gender;
  final DateTime? birthDate;
  final int? age;

  factory UserProfile.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const UserProfile();
    return UserProfile(
      fullName: json['full_name'] as String?,
      gender: json['gender'] != null
          ? UserGender.values.firstWhere(
              (e) => e.name == json['gender'],
              orElse: () => UserGender.preferNotToSay)
          : null,
      birthDate: json['birth_date'] != null
          ? DateTime.parse(json['birth_date'] as String)
          : null,
      age: json['age'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      if (fullName != null) 'full_name': fullName,
      if (gender != null) 'gender': gender!.name,
      if (birthDate != null) 'birth_date': birthDate!.toIso8601String().split('T').first,
      if (age != null) 'age': age,
    };
  }

  UserProfile copyWith({
    String? fullName,
    UserGender? gender,
    DateTime? birthDate,
    int? age,
  }) {
    return UserProfile(
      fullName: fullName ?? this.fullName,
      gender: gender ?? this.gender,
      birthDate: birthDate ?? this.birthDate,
      age: age ?? this.age,
    );
  }
}

class AppSettings {
  const AppSettings({
    required this.createdAt,
    required this.updatedAt,
    this.currency = 'NPR',
    this.themeMode = AppThemeMode.system,
    this.devanagariDates = false,
    this.calendarType = CalendarSystem.bs,
    this.notifications = const NotificationPrefs(),
    this.aiEnabled = false,
    this.hasSeenIntroduction = false,
    this.profile = const UserProfile(),
  });

  final String currency;
  final AppThemeMode themeMode;
  final bool devanagariDates;
  final CalendarSystem calendarType;
  final NotificationPrefs notifications;
  final bool aiEnabled;
  final bool hasSeenIntroduction;
  final UserProfile profile;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory AppSettings.defaults() {
    final now = DateTime.now();
    return AppSettings(createdAt: now, updatedAt: now);
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final notifications = json['notifications'];
    final profile = json['profile'];
    return AppSettings(
      currency: (json['currency'] as String?) ?? 'NPR',
      themeMode: AppThemeMode.fromCode(json['theme_mode'] as String?),
      devanagariDates: json['date_language'] == 'ne',
      calendarType: CalendarSystem.fromCode(json['calendar_type'] as String?),
      notifications: NotificationPrefs.fromJson(
        notifications is Map ? Map<String, dynamic>.from(notifications) : null,
      ),
      aiEnabled: (json['ai_enabled'] as bool?) ?? false,
      hasSeenIntroduction: (json['has_seen_introduction'] as bool?) ?? false,
      profile: UserProfile.fromJson(
        profile is Map ? Map<String, dynamic>.from(profile) : null,
      ),
      createdAt: jsonDateTime(json['created_at']) ?? now,
      updatedAt: jsonDateTime(json['updated_at']) ?? now,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': 'settings',
      'currency': currency,
      'theme_mode': themeMode.code,
      'date_language': devanagariDates ? 'ne' : 'en',
      'calendar_type': calendarType.code,
      'notifications': notifications.toJson(),
      'ai_enabled': aiEnabled,
      'has_seen_introduction': hasSeenIntroduction,
      'profile': profile.toJson(),
      'created_at': jsonTimestamp(createdAt),
      'updated_at': jsonTimestamp(updatedAt),
    };
  }

  AppSettings copyWith({
    String? currency,
    AppThemeMode? themeMode,
    bool? devanagariDates,
    CalendarSystem? calendarType,
    NotificationPrefs? notifications,
    bool? aiEnabled,
    bool? hasSeenIntroduction,
    UserProfile? profile,
    DateTime? updatedAt,
  }) {
    return AppSettings(
      currency: currency ?? this.currency,
      themeMode: themeMode ?? this.themeMode,
      devanagariDates: devanagariDates ?? this.devanagariDates,
      calendarType: calendarType ?? this.calendarType,
      notifications: notifications ?? this.notifications,
      aiEnabled: aiEnabled ?? this.aiEnabled,
      hasSeenIntroduction: hasSeenIntroduction ?? this.hasSeenIntroduction,
      profile: profile ?? this.profile,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
