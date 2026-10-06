class Env {
  const Env._();

  /// The Supabase project URL and its *publishable* (anon) key are public
  /// client configuration: every install ships with them and all data access
  /// is gated by row level security. They are therefore baked in as a fallback
  /// so authentication still works when the app is launched without the
  /// `--dart-define` flags that `tool/run.ps1` injects (for example straight
  /// from the IDE or `flutter run`). A dart-define still wins, so CI/staging
  /// can point at a different project.
  ///
  /// Real secrets (the sync account password) are never embedded here — they
  /// stay dart-define only and simply disable auto-sign-in when absent.
  static const String defaultSupabaseUrl =
      'https://eazyeerunsxfyecjpyox.supabase.co';
  static const String defaultSupabaseAnonKey =
      'sb_publishable_ebJ9erWJ7s4wxm131Mt21w_ThZLH7TZ';

  static String get supabaseUrl {
    const value = String.fromEnvironment('SUPABASE_URL');
    return value.isEmpty ? defaultSupabaseUrl : value;
  }

  static String get supabaseAnonKey {
    const value = String.fromEnvironment('SUPABASE_ANON_KEY');
    return value.isEmpty ? defaultSupabaseAnonKey : value;
  }

  /// Optional manual override for the key-less Open-Meteo weather accent.
  ///
  /// By default the app resolves its own approximate location (see
  /// `LocationService`), so this is only needed to pin weather to a specific
  /// place. When no coordinates can be resolved the accent is skipped.
  ///
  /// NOTE: there is intentionally NO AI provider key here. Insight generation
  /// runs in the `ai-insight` Supabase Edge Function, which owns the server
  /// secret (`NVIDIA_API_KEY`). Keeping the key off the client is required.
  static const String weatherLatRaw = String.fromEnvironment('WEATHER_LAT');
  static const String weatherLonRaw = String.fromEnvironment('WEATHER_LON');

  static double? get weatherLat => double.tryParse(weatherLatRaw);
  static double? get weatherLon => double.tryParse(weatherLonRaw);

  static bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
