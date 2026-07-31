import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/app_user.dart';
import '../data/models/education_level.dart';
import '../data/models/learning_profile.dart';
import '../data/models/lesson.dart';
import '../data/models/lesson_progress.dart';
import 'auth_controller.dart';
import 'progress_controller.dart';
import 'repository_providers.dart';

/// How the app is pitched for the signed-in learner.
///
/// Falls back to [EducationLevel.other] — the neutral, everything-in-order
/// profile — while auth is loading or when nobody is signed in, so no screen
/// has to handle a null profile.
final Provider<LearningProfile> learningProfileProvider =
    Provider<LearningProfile>((Ref ref) {
      final AppUser? user = ref.watch(currentUserProvider);
      return LearningProfile.forLevel(
        user?.educationLevel ?? EducationLevel.other,
      );
    });

/// All lessons, in the order this learner should meet them, each narrowed to
/// the questions their level is asked.
///
/// Personalisation is applied once, here, rather than at every call site: the
/// path, the player, the Q&A and the certificate count all read from this, so
/// they cannot disagree about what a lesson contains or what finishing it
/// requires.
final FutureProvider<List<Lesson>> lessonsProvider =
    FutureProvider<List<Lesson>>((Ref ref) async {
      final LearningProfile profile = ref.watch(learningProfileProvider);
      final List<Lesson> raw = await ref.watch(lessonRepoProvider).loadLessons();

      final List<Lesson> personalised = <Lesson>[
        for (final Lesson lesson in raw) lesson.forProfile(profile),
      ];
      personalised.sort(
        (Lesson a, Lesson b) => a.orderFor(profile).compareTo(
          b.orderFor(profile),
        ),
      );
      return personalised;
    });

final lessonProvider = FutureProvider.family<Lesson?, String>((
  Ref ref,
  String lessonId,
) async {
  // Derived from the personalised list rather than read again from the repo,
  // so the player and the Q&A never show a lesson the path does not agree with.
  final List<Lesson> lessons = await ref.watch(lessonsProvider.future);
  for (final Lesson lesson in lessons) {
    if (lesson.id == lessonId) return lesson;
  }
  return null;
});

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

  /// Cards read, questions still outstanding — so the tile should open the
  /// Q&A rather than replay a deck the learner has already been through.
  bool get needsQuiz =>
      lesson.hasQuiz && progress.lessonCompleted && !progress.quizCompleted;

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

/// Whether the "options-strategies" lesson is done — the gate the Sandbox's
/// Strategy tab checks before it lets a learner past the preset picker.
///
/// Reuses [lessonPathProvider] rather than re-deriving finished-ness from
/// [Lesson.hasQuiz]/[LessonProgress] here, so there is exactly one place
/// that decides what "finished" means for a lesson.
final FutureProvider<bool> strategiesLessonCompletedProvider =
    FutureProvider<bool>((Ref ref) async {
      final List<LessonNode> path = await ref.watch(lessonPathProvider.future);
      for (final LessonNode node in path) {
        if (node.lesson.id == 'options-strategies') return node.isFinished;
      }
      return false;
    });
