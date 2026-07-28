import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/app_user.dart';
import '../data/models/lesson_progress.dart';
import '../data/repositories/progress_repo.dart';
import 'auth_controller.dart';
import 'repository_providers.dart';

/// Placeholder award per correct answer until Phase 5 defines the real
/// points/streak/level scheme.
const int _pointsPerCorrectAnswer = 10;

/// Every lesson's progress for the signed-in learner, keyed by lesson id.
///
/// Rebuilds when the user changes, so signing out and back in as someone else
/// never shows the previous learner's progress. Empty map when signed out.
class ProgressController extends AsyncNotifier<Map<String, LessonProgress>> {
  ProgressRepo get _repo => ref.read(progressRepoProvider);
  String? get _userId => ref.read(currentUserProvider)?.id;

  @override
  Future<Map<String, LessonProgress>> build() async {
    final AppUser? user = ref.watch(currentUserProvider);
    if (user == null) return <String, LessonProgress>{};
    return ref.watch(progressRepoProvider).loadAll(user.id);
  }

  LessonProgress _existing(String lessonId) =>
      state.value?[lessonId] ?? LessonProgress(lessonId: lessonId);

  /// Records how far into the deck the learner has swiped, so a lesson can be
  /// resumed where it was left. [cardIndex] is zero-based.
  Future<void> recordCardViewed({
    required String lessonId,
    required int cardIndex,
  }) async {
    final LessonProgress current = _existing(lessonId);
    final int furthest = cardIndex + 1;
    if (furthest <= current.cardsViewed) return; // Never rewind on a swipe back.

    await _write(
      current.copyWith(
        cardsViewed: furthest,
        lastOpenedAt: DateTime.now(),
      ),
    );
  }

  /// Marks the deck finished. The Q&A (Phase 2) sets [quizCompleted]
  /// separately; both feed the unlock gate in `lesson_providers.dart`.
  Future<void> markLessonCompleted({
    required String lessonId,
    required int totalCards,
  }) async {
    final LessonProgress current = _existing(lessonId);
    final DateTime now = DateTime.now();

    await _write(
      current.copyWith(
        cardsViewed: totalCards,
        lessonCompleted: true,
        lastOpenedAt: now,
        completedAt: current.completedAt ?? now,
      ),
    );
  }

  /// Records a finished run through a lesson's Q&A.
  ///
  /// Completion — not a pass mark — is what unlocks the next lesson: a learner
  /// who answers badly has still met the material, and the results screen sends
  /// them back to the cards rather than a locked door. The stored score keeps
  /// the BEST attempt, so retaking can only help.
  Future<void> recordQuizResult({
    required String lessonId,
    required int correct,
    required int total,
  }) async {
    final LessonProgress current = _existing(lessonId);
    final bool improved = correct > current.correctAnswers ||
        current.totalQuestions != total;

    await _write(
      current.copyWith(
        quizCompleted: true,
        correctAnswers: improved ? correct : current.correctAnswers,
        totalQuestions: total,
        quizAttempts: current.quizAttempts + 1,
        // Phase 5 owns the real points scheme; this is a placeholder so the
        // field is populated consistently until then.
        pointsEarned: improved
            ? correct * _pointsPerCorrectAnswer
            : current.pointsEarned,
        lastOpenedAt: DateTime.now(),
        completedAt: current.completedAt ?? DateTime.now(),
      ),
    );
  }

  /// Wipes progress for the current learner (Settings → reset).
  Future<void> reset() async {
    final String? userId = _userId;
    if (userId == null) return;

    await _repo.clear(userId);
    state = const AsyncValue<Map<String, LessonProgress>>.data(
      <String, LessonProgress>{},
    );
  }

  Future<void> _write(LessonProgress progress) async {
    final String? userId = _userId;
    if (userId == null) return;

    await _repo.saveLesson(userId: userId, progress: progress);
    state = AsyncValue<Map<String, LessonProgress>>.data(
      <String, LessonProgress>{
        ...?state.value,
        progress.lessonId: progress,
      },
    );
  }
}

final AsyncNotifierProvider<ProgressController, Map<String, LessonProgress>>
progressControllerProvider =
    AsyncNotifierProvider<ProgressController, Map<String, LessonProgress>>(
      ProgressController.new,
    );
