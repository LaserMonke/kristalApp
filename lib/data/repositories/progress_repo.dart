import '../models/lesson_progress.dart';

/// Learning progress: which lessons are done, Q&A results, points and streak.
///
/// Phase 0 defines the surface and a local implementation; Phases 2 and 5 fill
/// in Q&A results and the engagement system against this same interface.
abstract interface class ProgressRepo {
  /// All progress rows for a user, keyed by lesson id.
  Future<Map<String, LessonProgress>> loadAll(String userId);

  Future<LessonProgress?> loadLesson({
    required String userId,
    required String lessonId,
  });

  Future<void> saveLesson({
    required String userId,
    required LessonProgress progress,
  });

  /// Lifetime points earned by the user.
  Future<int> totalPoints(String userId);

  /// Wipe local progress (used by "reset progress" in Settings).
  Future<void> clear(String userId);
}
