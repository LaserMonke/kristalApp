import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:optionsschool/core/widgets/level_badge_icons.dart';
import 'package:optionsschool/data/models/app_user.dart';
import 'package:optionsschool/data/models/education_level.dart';
import 'package:optionsschool/data/models/lesson.dart';
import 'package:optionsschool/data/models/lesson_progress.dart';
import 'package:optionsschool/data/models/quiz.dart';
import 'package:optionsschool/data/repositories/lesson_repo.dart';
import 'package:optionsschool/data/repositories/progress_repo.dart';
import 'package:optionsschool/engagement/levels.dart';
import 'package:optionsschool/engagement/streak.dart';
import 'package:optionsschool/providers/auth_controller.dart';
import 'package:optionsschool/providers/engagement_providers.dart';
import 'package:optionsschool/providers/progress_controller.dart';
import 'package:optionsschool/providers/repository_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The wiring between learning activity and the engagement system: points
/// summed from real progress records, the streak fed by the progress
/// controller, and the certificate gated on finishing every lesson's Q&A.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('completing a deck and its Q&A feeds points and the streak', () async {
    final _MemoryProgressRepo repo = _MemoryProgressRepo();
    final ProviderContainer container = await _container(repo);
    addTearDown(container.dispose);

    await container.read(progressControllerProvider.future);
    final ProgressController progress = container.read(
      progressControllerProvider.notifier,
    );

    await progress.markLessonCompleted(lessonId: 'one', totalCards: 2);
    await progress.recordQuizResult(lessonId: 'one', correct: 2, total: 2);

    // 20 deck + 2 × 10 correct + 15 perfect.
    expect(container.read(totalPointsProvider), 55);
    expect(container.read(levelProvider).name, 'Observer');

    // Today became an active day, and it was persisted.
    final StreakState streak = container
        .read(streakControllerProvider)
        .value!;
    expect(streak.current, 1);
    expect(StreakState.dateOnly(DateTime.now()), streak.lastActiveDay);
    expect(repo.streak, isNotNull);
  });

  test('two quizzes in one day still count as one streak day', () async {
    final ProviderContainer container = await _container(_MemoryProgressRepo());
    addTearDown(container.dispose);

    await container.read(progressControllerProvider.future);
    final ProgressController progress = container.read(
      progressControllerProvider.notifier,
    );

    await progress.recordQuizResult(lessonId: 'one', correct: 1, total: 2);
    await progress.recordQuizResult(lessonId: 'two', correct: 1, total: 1);

    expect(container.read(streakControllerProvider).value!.current, 1);
  });

  test('the certificate waits for every lesson, then reports earned',
      () async {
    final ProviderContainer container = await _container(_MemoryProgressRepo());
    addTearDown(container.dispose);

    await container.read(progressControllerProvider.future);
    final ProgressController progress = container.read(
      progressControllerProvider.notifier,
    );

    await progress.recordQuizResult(lessonId: 'one', correct: 2, total: 2);
    CertificateStatus status = await container.read(
      certificateStatusProvider.future,
    );
    expect(status.earned, isFalse);
    expect(status.finishedLessons, 1);
    expect(status.totalLessons, 2);

    // The second lesson has no Q&A, so finishing its deck finishes it.
    await progress.markLessonCompleted(lessonId: 'two', totalCards: 1);
    container.invalidate(certificateStatusProvider);
    status = await container.read(certificateStatusProvider.future);
    expect(status.earned, isTrue);
    expect(status.earnedOn, isNotNull);
  });

  test('every level names a badge glyph the UI actually has', () {
    for (final Level level in levels) {
      expect(
        knownBadgeIconNames,
        contains(level.iconName),
        reason: '${level.name} names a missing glyph',
      );
    }
  });
}

final Lesson _one = Lesson(
  id: 'one',
  order: 1,
  title: 'Lesson one',
  summary: 'First',
  cards: const <LessonCard>[TitleCard(title: 'One', subtitle: 'First')],
  questions: const <QuizQuestion>[
    MultipleChoiceQuestion(
      id: 'a',
      prompt: 'Who holds the right?',
      choices: <QuizChoice>[
        QuizChoice(text: 'The buyer', isCorrect: true, explanation: 'Yes.'),
        QuizChoice(text: 'The seller', isCorrect: false, explanation: 'No.'),
      ],
    ),
    MultipleChoiceQuestion(
      id: 'b',
      prompt: 'Who carries the obligation?',
      choices: <QuizChoice>[
        QuizChoice(text: 'The seller', isCorrect: true, explanation: 'Yes.'),
        QuizChoice(text: 'The buyer', isCorrect: false, explanation: 'No.'),
      ],
    ),
  ],
);

final Lesson _two = Lesson(
  id: 'two',
  order: 2,
  title: 'Lesson two',
  summary: 'Second',
  cards: const <LessonCard>[TitleCard(title: 'Two', subtitle: 'Second')],
);

final AppUser _learner = AppUser(
  id: 'learner-1',
  username: 'sam',
  educationLevel: EducationLevel.undergraduate,
  createdAt: DateTime(2026),
);

Future<ProviderContainer> _container(_MemoryProgressRepo repo) async {
  // The progress controller retires the learner's resume bookmarks when a run
  // finishes, and those live in shared_preferences.
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();

  return ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      lessonRepoProvider.overrideWithValue(_FakeLessonRepo()),
      progressRepoProvider.overrideWithValue(repo),
      currentUserProvider.overrideWithValue(_learner),
    ],
  );
}

class _FakeLessonRepo implements LessonRepo {
  @override
  Future<List<Lesson>> loadLessons() async => <Lesson>[_one, _two];

  @override
  Future<Lesson?> loadLesson(String lessonId) async {
    for (final Lesson lesson in <Lesson>[_one, _two]) {
      if (lesson.id == lessonId) return lesson;
    }
    return null;
  }
}

class _MemoryProgressRepo implements ProgressRepo {
  final Map<String, LessonProgress> store = <String, LessonProgress>{};
  StreakState? streak;

  @override
  Future<Map<String, LessonProgress>> loadAll(String userId) async =>
      Map<String, LessonProgress>.of(store);

  @override
  Future<LessonProgress?> loadLesson({
    required String userId,
    required String lessonId,
  }) async => store[lessonId];

  @override
  Future<void> saveLesson({
    required String userId,
    required LessonProgress progress,
  }) async {
    store[progress.lessonId] = progress;
  }

  @override
  Future<int> totalPoints(String userId) async => store.values.fold<int>(
    0,
    (int sum, LessonProgress p) => sum + p.pointsEarned,
  );

  @override
  Future<StreakState?> loadStreak(String userId) async => streak;

  @override
  Future<void> saveStreak({
    required String userId,
    required StreakState streak,
  }) async {
    this.streak = streak;
  }

  @override
  Future<void> clear(String userId) async {
    store.clear();
    streak = null;
  }
}
