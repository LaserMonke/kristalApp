import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/lesson.dart';
import '../data/models/lesson_progress.dart';
import 'progress_controller.dart';
import 'repository_providers.dart';

/// All lessons, ordered.
final FutureProvider<List<Lesson>> lessonsProvider =
    FutureProvider<List<Lesson>>(
      (Ref ref) => ref.watch(lessonRepoProvider).loadLessons(),
    );

final lessonProvider = FutureProvider.family<Lesson?, String>(
  (Ref ref, String lessonId) =>
      ref.watch(lessonRepoProvider).loadLesson(lessonId),
);

/// A lesson plus the learner's state for it.
class LessonNode {
  const LessonNode({
    required this.lesson,
    required this.progress,
    required this.isUnlocked,
  });

  final Lesson lesson;
  final LessonProgress progress;

  /// False when an earlier lesson still has to be finished.
  final bool isUnlocked;

  /// Whether this lesson counts as done for the purpose of unlocking the next.
  ///
  /// Once a lesson has Q&A questions (Phase 2), reading the cards is no longer
  /// enough — the gate moves to the quiz automatically, because [Lesson.hasQuiz]
  /// flips as soon as questions are added to the JSON.
  bool get isFinished =>
      lesson.hasQuiz ? progress.quizCompleted : progress.lessonCompleted;

  bool get isStarted => progress.cardsViewed > 0 && !isFinished;

  /// Where to drop the learner back in, clamped to a valid card index.
  int get resumeCardIndex {
    if (isFinished || lesson.cards.isEmpty) return 0;
    return progress.cardsViewed.clamp(0, lesson.cards.length - 1);
  }

  double get fractionRead => lesson.cards.isEmpty
      ? 0
      : (progress.cardsViewed / lesson.cards.length).clamp(0.0, 1.0);
}

/// The learning path: lessons in order, each with its progress and lock state.
///
/// The first lesson is always open; every later one waits on the one before it.
final FutureProvider<List<LessonNode>> lessonPathProvider =
    FutureProvider<List<LessonNode>>((Ref ref) async {
      final List<Lesson> lessons = await ref.watch(lessonsProvider.future);
      final Map<String, LessonProgress> progress = await ref.watch(
        progressControllerProvider.future,
      );

      final List<LessonNode> path = <LessonNode>[];
      bool previousFinished = true;

      for (final Lesson lesson in lessons) {
        final LessonNode node = LessonNode(
          lesson: lesson,
          progress: progress[lesson.id] ?? LessonProgress(lessonId: lesson.id),
          isUnlocked: previousFinished,
        );
        path.add(node);
        previousFinished = node.isFinished;
      }

      return path;
    });
