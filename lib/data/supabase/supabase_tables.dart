/// Table, column and function names, mirroring `supabase/migrations`.
///
/// Centralised so a schema rename is one edit here plus a migration, never a
/// hunt through string literals.
abstract final class Db {
  static const String profiles = 'profiles';
  static const String lessonProgress = 'lesson_progress';
  static const String streaks = 'streaks';

  /// `public.username_available(candidate text) returns boolean`
  static const String usernameAvailableFn = 'username_available';

  /// `public.leaderboard_page(period text, limit_count int)` — SECURITY
  /// DEFINER, the only cross-user read in the app.
  static const String leaderboardPageFn = 'leaderboard_page';

  /// `public.leaderboard_standing(period text)` — the caller's own rank.
  static const String leaderboardStandingFn = 'leaderboard_standing';
}
