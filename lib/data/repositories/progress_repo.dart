import '../../engagement/streak.dart';
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

  /// The user's daily streak, or null if none has been recorded yet.
  Future<StreakState?> loadStreak(String userId);

  Future<void> saveStreak({
    required String userId,
    required StreakState streak,
  });

  /// Wipe the learner's progress, streak included ("reset progress" in
  /// Settings). Throws [ProgressException] if it could not be completed
  /// everywhere the progress is stored — a half-done reset that quietly comes
  /// back on the next sync would be worse than a visible failure.
  Future<void> clear(String userId);
}

/// Progress failure with a message safe to show a learner verbatim.
class ProgressException implements Exception {
  const ProgressException(this.message);
  final String message;

  @override
  String toString() => message;
}
