// The push category contract, shared by the sender and mirrored in
// lib/models/push_category.dart.
//
// Keep the two in sync: the Dart file owns the enum, this file owns what the
// server will accept. `category` and `prefKey` values must match the
// NotificationPrefs keys in lib/models/app_settings_model.dart, because the
// sender reads the user's opt-out straight out of app_settings.notifications.

export type PushType = {
  /** Key in app_settings.notifications that gates this category. */
  prefKey: string;
  /** Fallback title when the caller does not supply one. */
  title: string;
  /** 'normal' | 'high' — maps to the FCM Android priority. */
  priority: 'normal' | 'high';
  /** FCM TTL, e.g. '3600s'. Expired messages are dropped rather than queued. */
  ttl: string;
  /** Android channel this category is posted to. */
  channel: string;
};

export const PUSH_TYPES: Record<string, PushType> = {
  recurring_reminders: {
    prefKey: 'recurring_reminders',
    title: 'Upcoming payment',
    priority: 'normal',
    ttl: '86400s',
    channel: 'kharcha_reminders',
  },
  budget_warnings: {
    prefKey: 'budget_warnings',
    title: 'Budget alert',
    priority: 'high',
    ttl: '3600s',
    channel: 'kharcha_budget',
  },
  friend_debt_reminders: {
    prefKey: 'friend_debt_reminders',
    title: 'Friend reminder',
    priority: 'normal',
    ttl: '86400s',
    channel: 'kharcha_social',
  },
  overdue_reminders: {
    prefKey: 'overdue_reminders',
    title: 'Payment overdue',
    priority: 'high',
    ttl: '86400s',
    channel: 'kharcha_reminders',
  },
  daily_summary: {
    prefKey: 'daily_summary',
    title: 'Your day in Kharcha',
    priority: 'normal',
    ttl: '3600s',
    channel: 'kharcha_insights',
  },
  weekly_summary: {
    prefKey: 'weekly_summary',
    title: 'Your week in Kharcha',
    priority: 'normal',
    ttl: '3600s',
    channel: 'kharcha_insights',
  },
  monthly_report: {
    prefKey: 'monthly_report',
    title: 'Your month in Kharcha',
    priority: 'normal',
    ttl: '86400s',
    channel: 'kharcha_insights',
  },
  pasal_month_end: {
    prefKey: 'pasal_month_end',
    title: 'Pasal reminder',
    priority: 'normal',
    ttl: '86400s',
    channel: 'kharcha_reminders',
  },
  festival_reminders: {
    prefKey: 'festival_reminders',
    title: 'Festival reminder',
    priority: 'normal',
    ttl: '86400s',
    channel: 'kharcha_reminders',
  },
  ai_content: {
    prefKey: 'ai_content',
    title: 'Insight',
    priority: 'normal',
    ttl: '3600s',
    channel: 'kharcha_insights',
  },
  // The flame reacting to a transaction the user just saved. Sent by the app
  // to its own devices through send-push, so it arrives as a real FCM
  // notification; high priority so it shows as a heads-up banner.
  mood_reaction: {
    prefKey: 'mood_reaction',
    title: 'Kharcha',
    priority: 'high',
    ttl: '300s',
    channel: 'kharcha_buddy',
  },
  daily_buddy: {
    prefKey: 'daily_buddy',
    title: 'Kharcha',
    priority: 'normal',
    ttl: '1800s',
    channel: 'kharcha_insights',
  },
};

/** Channel for a category, falling back to the general channel. */
export function resolveChannel(category: string): string {
  return PUSH_TYPES[category]?.channel ?? 'kharcha_default';
}
