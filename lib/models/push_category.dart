// The categories of push notification Kharcha can deliver.
//
// This is the single source of truth shared by the sender (the `send-push`
// Edge Function copies this list into its own push_types), the preference UI,
// the settings screen, and the background renderer. Adding a category here
// means adding it to `NotificationPrefs` and to the Edge Function's
// `push_types` map, which the Edge Function validates on startup.
library;

/// A notification category, and where tapping it should land.
enum PushCategory {
  /// Recurring payment reminders (UPI/Fonepay, rent, subscriptions).
  recurringReminders(
    id: 'recurring_reminders',
    defaultEnabled: true,
    channel: PushChannel.reminders,
    importance: PushImportance.defaultImportance,
  ),

  /// A budget category crossing its limit.
  budgetWarnings(
    id: 'budget_warnings',
    defaultEnabled: true,
    channel: PushChannel.budget,
    importance: PushImportance.high,
  ),

  /// "You owe X" / "X owes you" nudges for a friend.
  friendDebtReminders(
    id: 'friend_debt_reminders',
    defaultEnabled: true,
    channel: PushChannel.social,
    importance: PushImportance.defaultImportance,
  ),

  /// A pasal contribution past its due date.
  overdueReminders(
    id: 'overdue_reminders',
    defaultEnabled: true,
    channel: PushChannel.reminders,
    importance: PushImportance.defaultImportance,
  ),

  /// End-of-day spending recap.
  dailySummary(
    id: 'daily_summary',
    defaultEnabled: false,
    channel: PushChannel.insights,
    importance: PushImportance.low,
  ),

  /// Start-of-week spending recap.
  weeklySummary(
    id: 'weekly_summary',
    defaultEnabled: false,
    channel: PushChannel.insights,
    importance: PushImportance.low,
  ),

  /// On the first day of a month: what the month that just ended came to.
  monthlyReport(
    id: 'monthly_report',
    defaultEnabled: true,
    channel: PushChannel.insights,
    importance: PushImportance.defaultImportance,
  ),

  /// A pasal reaching the end of its month.
  pasalMonthEnd(
    id: 'pasal_month_end',
    defaultEnabled: true,
    channel: PushChannel.reminders,
    importance: PushImportance.defaultImportance,
  ),

  /// A festival approaching.
  festivalReminders(
    id: 'festival_reminders',
    defaultEnabled: true,
    channel: PushChannel.reminders,
    importance: PushImportance.defaultImportance,
  ),

  /// Proactive AI nudges, e.g. "spending 20% above your usual on groceries".
  ///
  /// Off by default because these are the most promotional-sounding messages
  /// and the app can already show the same insight on demand.
  aiContent(
    id: 'ai_content',
    defaultEnabled: false,
    channel: PushChannel.insights,
    importance: PushImportance.low,
  ),

  /// The flame's daily chatter: good morning at 06:00, good night at 22:00,
  /// and a couple of AI-written nudges at random times in between.
  dailyBuddy(
    id: 'daily_buddy',
    defaultEnabled: true,
    channel: PushChannel.insights,
    importance: PushImportance.defaultImportance,
  ),

  /// The flame reacting to a transaction the user just saved ("Hmmm…
  /// money!"). Local only, never sent by the server. Posted as a heads-up
  /// banner so it reads like a real device notification.
  moodReaction(
    id: 'mood_reaction',
    defaultEnabled: true,
    channel: PushChannel.buddy,
    importance: PushImportance.high,
  );

  const PushCategory({
    required this.id,
    required this.defaultEnabled,
    required this.channel,
    required this.importance,
  });

  /// Wire name, matching the key in `app_settings.notifications`.
  final String id;

  /// Whether a new user has this on before they touch the settings screen.
  final bool defaultEnabled;

  /// Android channel this is posted to.
  final PushChannel channel;

  /// How insistent the notification is.
  final PushImportance importance;

  static PushCategory? byId(String id) {
    for (final category in PushCategory.values) {
      if (category.id == id) return category;
    }
    return null;
  }
}

/// Android notification channels.
///
/// One channel per notification "kind" rather than per category, so a user who
/// wants to silence budget warnings in system settings silences every budget
/// notification without muting, say, festival reminders.
enum PushChannel {
  /// Low-key, user-initiated-time reminders.
  reminders(id: 'kharcha_reminders', name: 'Reminders'),

  /// Overspend / limit warnings.
  budget(id: 'kharcha_budget', name: 'Budget alerts'),

  /// Friend and pasal social events.
  social(id: 'kharcha_social', name: 'Friends & pasals'),

  /// AI insights and recaps.
  insights(id: 'kharcha_insights', name: 'Insights'),

  /// The flame's reactions to transactions. High importance so they pop up.
  buddy(id: 'kharcha_buddy', name: 'Flame reactions'),

  /// Fallback when a message carries no category.
  fallback(id: 'kharcha_default', name: 'General');

  const PushChannel({required this.id, required this.name});

  final String id;
  final String name;

  static PushChannel? byId(String id) {
    for (final channel in PushChannel.values) {
      if (channel.id == id) return channel;
    }
    return null;
  }
}

/// Maps to `androidx.core.app.NotificationCompat` importance / priority.
enum PushImportance {
  /// Silent in the shade, no sound: recaps and AI nudges.
  low(
    androidChannel: AndroidChannelImportance.low,
    androidPriority: AndroidPriority.low,
    androidVisibility: AndroidVisibility.private,
  ),

  /// Standard: shows in the shade, no heads-up.
  defaultImportance(
    androidChannel: AndroidChannelImportance.defaultImportance,
    androidPriority: AndroidPriority.defaultPriority,
    androidVisibility: AndroidVisibility.private,
  ),

  /// Heads-up notification with sound: budget warnings.
  high(
    androidChannel: AndroidChannelImportance.high,
    androidPriority: AndroidPriority.high,
    androidVisibility: AndroidVisibility.public,
  );

  const PushImportance({
    required this.androidChannel,
    required this.androidPriority,
    required this.androidVisibility,
  });

  final AndroidChannelImportance androidChannel;
  final AndroidPriority androidPriority;
  final AndroidVisibility androidVisibility;
}

/// Subset of `AndroidNotificationImportance` that Kharcha uses.
enum AndroidChannelImportance {
  noImportance(0),
  low(1),
  defaultImportance(2),
  high(3),
  maximum(4);

  const AndroidChannelImportance(this.value);

  final int value;
}

/// Subset of `AndroidNotificationPriority`.
enum AndroidPriority {
  minimum(-2),
  low(-1),
  defaultPriority(0),
  high(1),
  maximum(2);

  const AndroidPriority(this.value);

  final int value;
}

/// Subset of `AndroidNotificationVisibility`.
///
/// Lock-screen content is a real privacy consideration for a finance app, so
/// only the category that genuinely needs to be read at a glance (budget
/// warnings) is [AndroidVisibility.public]; everything else is
/// [AndroidVisibility.private] so amounts are hidden until the device is
/// unlocked.
enum AndroidVisibility { secret, private, public }
