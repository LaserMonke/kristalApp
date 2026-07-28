import '../models/lesson.dart';

/// Source of lesson content.
///
/// Behind an interface like the other repositories so lessons can later be
/// served (and updated without an app release) from Supabase storage without
/// touching the engine or the UI. Phase 1 ships them as a bundled asset.
abstract interface class LessonRepo {
  /// All lessons, ordered by [Lesson.order].
  Future<List<Lesson>> loadLessons();

  Future<Lesson?> loadLesson(String lessonId);
}
