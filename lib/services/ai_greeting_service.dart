import '../models/app_settings_model.dart';
import '../providers/auth_provider.dart';

/// Service for generating AI-powered personalized greetings based on user profile
class AiGreetingService {
  /// Generates a personalized greeting based on time of day and user profile
  static String generateGreeting({
    required AuthProvider auth,
    String? customName,
  }) {
    final hour = DateTime.now().hour;
    final timeGreeting = _getTimeGreeting(hour);
    final name = customName ?? auth.profileName;
    final age = auth.computedAge;
    final gender = auth.profileGender;
    final birthDate = auth.profileBirthDate;

    // Check if it's the user's birthday
    final isBirthday = _isBirthdayToday(birthDate);

    if (isBirthday) {
      return _generateBirthdayGreeting(timeGreeting, name, age);
    }

    // Generate contextual greeting based on available profile data
    if (name != null && age != null && gender != null) {
      return _generateFullProfileGreeting(timeGreeting, name, age, gender);
    } else if (name != null && age != null) {
      return _generateNameAgeGreeting(timeGreeting, name, age);
    } else if (name != null) {
      return _generateNameGreeting(timeGreeting, name);
    }

    return timeGreeting;
  }

  static String _getTimeGreeting(int hour) {
    if (hour < 5) return 'Good night';
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    if (hour < 21) return 'Good evening';
    return 'Good night';
  }

  static bool _isBirthdayToday(DateTime? birthDate) {
    if (birthDate == null) return false;
    final now = DateTime.now();
    return birthDate.month == now.month && birthDate.day == now.day;
  }

  static String _generateBirthdayGreeting(String timeGreeting, String? name, int? age) {
    final ageText = age != null ? ' turning $age' : '';
    final nameText = name != null ? '$name, ' : '';
    return '$timeGreeting $nameText🎉 Happy Birthday$ageText!';
  }

  static String _generateFullProfileGreeting(
    String timeGreeting,
    String name,
    int age,
    UserGender gender,
  ) {
    final greetings = <String>[
      '$timeGreeting, $name! Ready for another great day at $age?',
      '$timeGreeting $name! Looking sharp at $age.',
      '$timeGreeting, $name! $age years young and thriving.',
      'Hey $name! $timeGreeting. $age and fabulous!',
    ];

    // Add gender-specific touches
    if (gender == UserGender.male) {
      greetings.add('$timeGreeting, $name! Handsome as ever at $age.');
    } else if (gender == UserGender.female) {
      greetings.add('$timeGreeting $name! Radiant at $age as always.');
    }

    // Pick based on day of year for variety
    final dayOfYear = DateTime.now().difference(DateTime(DateTime.now().year, 1, 1)).inDays;
    return greetings[dayOfYear % greetings.length];
  }

  static String _generateNameAgeGreeting(String timeGreeting, String name, int age) {
    final greetings = <String>[
      '$timeGreeting, $name! Feeling good at $age?',
      '$timeGreeting $name! $age years of awesomeness.',
      '$timeGreeting, $name! $age and counting.',
    ];
    final dayOfYear = DateTime.now().difference(DateTime(DateTime.now().year, 1, 1)).inDays;
    return greetings[dayOfYear % greetings.length];
  }

  static String _generateNameGreeting(String timeGreeting, String name) {
    final greetings = <String>[
      '$timeGreeting, $name!',
      '$timeGreeting $name! How\'s your day going?',
      'Hey $name! $timeGreeting.',
      '$timeGreeting, $name! Ready to track some expenses?',
    ];
    final dayOfYear = DateTime.now().difference(DateTime(DateTime.now().year, 1, 1)).inDays;
    return greetings[dayOfYear % greetings.length];
  }

  /// Generates a smart financial tip based on user's profile and time
  static String generateFinancialTip({
    required AuthProvider auth,
    required double totalBalance,
    required double monthlyBudget,
    required double budgetSpent,
  }) {
    final tips = <String>[
      'Small daily savings compound into big results!',
      'Track every expense - awareness is the first step to control.',
      'Review your subscriptions monthly. Cancel what you don\'t use.',
      'Set up automatic savings - pay yourself first.',
      'The 50/30/20 rule: needs/wants/savings.',
      'Emergency fund: aim for 3-6 months of expenses.',
    ];

    // Add contextual tips based on budget usage
    if (monthlyBudget > 0) {
      final usage = budgetSpent / monthlyBudget;
      if (usage > 0.9) {
        tips.insert(0, 'You\'re at ${(usage * 100).round()}% of your budget. Time to review spending!');
      } else if (usage > 0.7) {
        tips.insert(0, 'Budget at ${(usage * 100).round()}%. Good pace, but stay mindful.');
      }
    }

    if (totalBalance < 0) {
      tips.insert(0, 'Your balance is negative. Consider a spending freeze this week.');
    }

    final dayOfYear = DateTime.now().difference(DateTime(DateTime.now().year, 1, 1)).inDays;
    return tips[dayOfYear % tips.length];
  }
}