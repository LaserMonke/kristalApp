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
}
