import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:optionsschool/core/router/app_router.dart';
import 'package:optionsschool/data/local/lesson_resume_store.dart';
import 'package:optionsschool/data/models/app_user.dart';
import 'package:optionsschool/data/models/education_level.dart';
import 'package:optionsschool/data/models/lesson.dart';
import 'package:optionsschool/data/models/lesson_progress.dart';
import 'package:optionsschool/data/models/lesson_resume.dart';
import 'package:optionsschool/data/models/quiz.dart';
import 'package:optionsschool/data/repositories/lesson_repo.dart';
import 'package:optionsschool/data/repositories/progress_repo.dart';
import 'package:optionsschool/engagement/streak.dart';
import 'package:optionsschool/features/learn/lesson_player_screen.dart';
import 'package:optionsschool/features/quiz/quiz_screen.dart';
import 'package:optionsschool/providers/auth_controller.dart';
import 'package:optionsschool/providers/lesson_resume_controller.dart';
import 'package:optionsschool/providers/progress_controller.dart';
import 'package:optionsschool/providers/repository_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Coming back to a lesson or a Q&A where you left it.
///
/// The rule under all of this: a learner who is interrupted — a phone call, a
/// swipe to another tab, a killed app — should lose nothing they had already
/// read or already answered. Answers are locked to one attempt, so a dropped
/// Q&A run is not a small loss.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a bookmarked Q&A run', () {
    test('is dropped when the lesson no longer asks the same questions', () {
      const QuizResume saved = QuizResume(
        seed: 7,
        questionIndex: 1,
        questionIds: <String>['a', 'b', 'c'],
        responses: <String, QuizResponse>{},
      );

      expect(saved.matches(_lesson.questions), isTrue);
      // A question added, removed or reordered — an app update, or a learner
      // changing their education level, which changes which are asked.
      expect(
        saved.matches(_lesson.questions.sublist(0, 2)),
        isFalse,
        reason: 'a shorter Q&A must not restore against the wrong prompts',
      );
      expect(
        saved.matches(<QuizQuestion>[
          _lesson.questions[1],
          _lesson.questions[0],
          _lesson.questions[2],
        ]),
        isFalse,
      );
    });

    test('replays the same choice order and the verdicts it was given', () {
      // The order the learner saw is reproduced from the seed, not stored, so
      // the tile they tapped is still the tile under their answer.
      final QuizSession original = QuizSession.shuffled(
        questions: _lesson.questions,
        seed: 4242,
      );

      const QuizResume saved = QuizResume(
        seed: 4242,
        questionIndex: 1,
        questionIds: <String>['a', 'b', 'c'],
        responses: <String, QuizResponse>{
          // Recorded as wrong even though 'a' has a right answer: a restored
          // run replays how it was marked, it never re-grades.
          'a': QuizResponse(correct: false, choiceIndex: 1),
        },
      );

      final QuizSession restored = saved.restore(_lesson.questions);

      expect(
        restored.questions.whereType<MultipleChoiceQuestion>().map(
          (MultipleChoiceQuestion q) => q.choices.first.text,
        ),
        original.questions.whereType<MultipleChoiceQuestion>().map(
          (MultipleChoiceQuestion q) => q.choices.first.text,
        ),
      );
      expect(restored.verdictFor('a'), isFalse);
      expect(restored.verdictFor('b'), isNull);
      expect(restored.answered, 1);
    });
  });

  group('the bookmark store', () {
    test('round-trips a card and a half-finished run', () async {
      final SharedPreferences prefs = await _prefs();
      final LessonResumeStore store = LessonResumeStore(prefs);

      await store.writeAll(
        userId: 'learner-1',
        bookmarks: <String, LessonResume>{
          'one': const LessonResume(
            lessonId: 'one',
            cardIndex: 2,
            quiz: QuizResume(
              seed: 9,
              questionIndex: 1,
              questionIds: <String>['a', 'b', 'c'],
              responses: <String, QuizResponse>{
                'a': QuizResponse(correct: true, choiceIndex: 0),
                'b': QuizResponse(correct: false, text: r'$12'),
              },
            ),
          ),
        },
      );

      final LessonResume? read = LessonResumeStore(
        prefs,
      ).read(userId: 'learner-1', lessonId: 'one');

      expect(read!.cardIndex, 2);
      expect(read.quiz!.seed, 9);
      expect(read.quiz!.questionIndex, 1);
      expect(read.quiz!.responses['a']!.choiceIndex, 0);
      expect(read.quiz!.responses['b']!.text, r'$12');
      expect(read.quiz!.responses['b']!.correct, isFalse);
    });

    test('keeps one learner out of another learner\'s lessons', () async {
      final SharedPreferences prefs = await _prefs();
      final LessonResumeStore store = LessonResumeStore(prefs);

      await store.writeAll(
        userId: 'learner-1',
        bookmarks: <String, LessonResume>{
          'one': const LessonResume(lessonId: 'one', cardIndex: 3),
        },
      );

      expect(store.read(userId: 'learner-2', lessonId: 'one'), isNull);
    });

    test('drops a bookmark that no longer points anywhere', () async {
      final SharedPreferences prefs = await _prefs();
      final LessonResumeStore store = LessonResumeStore(prefs);

      await store.writeAll(
        userId: 'learner-1',
        bookmarks: <String, LessonResume>{
          'one': const LessonResume(lessonId: 'one'),
        },
      );

      expect(store.readAll('learner-1'), isEmpty);
    });
  });

  group('retiring a bookmark', () {
    test('finishing the deck clears the card but keeps the Q&A run', () async {
      final ProviderContainer container = await _container();
      addTearDown(container.dispose);

      await container.read(progressControllerProvider.future);
      final LessonResumeController bookmarks = container.read(
        lessonResumeControllerProvider.notifier,
      );

      await bookmarks.saveCard(lessonId: 'one', cardIndex: 2);
      await bookmarks.saveQuiz(lessonId: 'one', quiz: _savedRun);

      await container
          .read(progressControllerProvider.notifier)
          .markLessonCompleted(lessonId: 'one', totalCards: 3);

      final LessonResume? left = container.read(
        lessonResumeControllerProvider,
      )['one'];
      expect(left!.cardIndex, 0, reason: 'a read deck reopens at the top');
      expect(
        left.quiz,
        isNotNull,
        reason: 'the Q&A run is separate and still unfinished',
      );
    });

    test('finishing the Q&A clears the run that was scored', () async {
      final ProviderContainer container = await _container();
      addTearDown(container.dispose);

      await container.read(progressControllerProvider.future);
      await container
          .read(lessonResumeControllerProvider.notifier)
          .saveQuiz(lessonId: 'one', quiz: _savedRun);

      await container
          .read(progressControllerProvider.notifier)
          .recordQuizResult(lessonId: 'one', correct: 2, total: 3);

      expect(container.read(lessonResumeControllerProvider), isEmpty);
    });

    test('resetting progress leaves no bookmark behind', () async {
      final ProviderContainer container = await _container();
      addTearDown(container.dispose);

      await container.read(progressControllerProvider.future);
      await container
          .read(lessonResumeControllerProvider.notifier)
          .saveCard(lessonId: 'one', cardIndex: 2);

      await container.read(progressControllerProvider.notifier).reset();

      expect(container.read(lessonResumeControllerProvider), isEmpty);
      // And on disk, not just in memory — a "not started" lesson must not
      // reopen half-way through after a restart.
      expect(
        container.read(lessonResumeStoreProvider).readAll('learner-1'),
        isEmpty,
      );
    });
  });

  group('the lesson deck', () {
    testWidgets('reopens on the card that was on screen', (
      WidgetTester tester,
    ) async {
      await _pumpPlayer(
        tester,
        progress: const LessonProgress(lessonId: 'one', cardsViewed: 3),
        bookmark: const LessonResume(lessonId: 'one', cardIndex: 2),
      );

      expect(find.text('Card three'), findsOneWidget);
      expect(find.text('3/3'), findsOneWidget);
      expect(find.text('Picked up where you left off'), findsOneWidget);
    });

    testWidgets('honours a swipe back, not just the furthest card reached', (
      WidgetTester tester,
    ) async {
      // Progress says all three cards have been seen; the bookmark says the
      // learner went back to re-read the first one and left from there.
      await _pumpPlayer(
        tester,
        progress: const LessonProgress(lessonId: 'one', cardsViewed: 3),
        bookmark: const LessonResume(lessonId: 'one', cardIndex: 1),
      );

      expect(find.text('Card two'), findsOneWidget);
    });

    testWidgets('falls back to the last card progress recorded', (
      WidgetTester tester,
    ) async {
      // No bookmark: progress synced from another device, or a reinstall. Two
      // cards viewed means card two was on screen — opening card three would
      // skip one the learner may only have glanced at.
      await _pumpPlayer(
        tester,
        progress: const LessonProgress(lessonId: 'one', cardsViewed: 2),
      );

      expect(find.text('Card two'), findsOneWidget);
    });

    testWidgets('starts a finished lesson from the top, quietly', (
      WidgetTester tester,
    ) async {
      await _pumpPlayer(
        tester,
        progress: const LessonProgress(
          lessonId: 'one',
          cardsViewed: 3,
          lessonCompleted: true,
        ),
        bookmark: const LessonResume(lessonId: 'one', cardIndex: 2),
      );

      expect(find.text('Card one'), findsOneWidget);
      expect(find.text('Picked up where you left off'), findsNothing);
    });

    testWidgets('records the card it was left on', (WidgetTester tester) async {
      final SharedPreferences prefs = await _pumpPlayer(
        tester,
        progress: const LessonProgress(lessonId: 'one', cardsViewed: 1),
      );

      await tester.fling(find.byType(PageView), const Offset(0, -320), 900);
      await tester.pumpAndSettle();

      expect(find.text('Card two'), findsOneWidget);
      expect(
        LessonResumeStore(
          prefs,
        ).read(userId: 'learner-1', lessonId: 'one')?.cardIndex,
        1,
      );
      // The note belongs to the card it explains, so moving on takes it away.
      expect(find.text('Picked up where you left off'), findsNothing);
    });
  });

  group('the Q&A', () {
    testWidgets('reopens on the question that was on screen, answer and all', (
      WidgetTester tester,
    ) async {
      // The order the learner saw, reproduced here so the test can say which
      // tile they actually tapped.
      final MultipleChoiceQuestion asked =
          QuizSession.shuffled(
                questions: _lesson.questions,
                seed: 4242,
              ).questions.first
              as MultipleChoiceQuestion;
      final int picked = asked.choices.indexWhere(
        (QuizChoice c) => !c.isCorrect,
      );

      await _pumpQuiz(
        tester,
        quiz: QuizResume(
          seed: 4242,
          questionIndex: 0,
          questionIds: const <String>['a', 'b', 'c'],
          responses: <String, QuizResponse>{
            'a': QuizResponse(correct: false, choiceIndex: picked),
          },
        ),
      );

      expect(find.text('Question 1 of 3'), findsOneWidget);
      expect(find.text('Picked up where you left off'), findsOneWidget);
      // Marked, with the reasoning for the tile they picked — the whole state
      // of the question, not just the fact that it was answered.
      expect(find.text('Not quite'), findsOneWidget);
      expect(find.text(asked.choices[picked].explanation), findsOneWidget);
      // And it is not re-answerable: the single attempt was already spent.
      await tester.tap(find.text(asked.correctChoice.text));
      await tester.pumpAndSettle();
      expect(find.text('Correct'), findsNothing);
    });

    testWidgets('reopens on a later question with the answers kept', (
      WidgetTester tester,
    ) async {
      await _pumpQuiz(
        tester,
        quiz: const QuizResume(
          seed: 4242,
          questionIndex: 2,
          questionIds: <String>['a', 'b', 'c'],
          responses: <String, QuizResponse>{
            'a': QuizResponse(correct: true, choiceIndex: 0),
            'b': QuizResponse(correct: true, text: '5'),
          },
        ),
      );

      expect(find.text('Question 3 of 3'), findsOneWidget);
      expect(find.text('Where does it break even?'), findsOneWidget);
    });

    testWidgets('puts a graded short answer back in the field', (
      WidgetTester tester,
    ) async {
      await _pumpQuiz(
        tester,
        quiz: const QuizResume(
          seed: 4242,
          questionIndex: 1,
          questionIds: <String>['a', 'b', 'c'],
          responses: <String, QuizResponse>{
            'a': QuizResponse(correct: true, choiceIndex: 0),
            'b': QuizResponse(correct: false, text: '3'),
          },
        ),
      );

      expect(find.widgetWithText(TextField, '3'), findsOneWidget);
      expect(find.text('Not quite'), findsOneWidget);
    });

    testWidgets('starts fresh when the bookmark no longer fits the lesson', (
      WidgetTester tester,
    ) async {
      await _pumpQuiz(
        tester,
        quiz: const QuizResume(
          seed: 4242,
          questionIndex: 2,
          // A question this lesson no longer asks.
          questionIds: <String>['a', 'b', 'gone'],
          responses: <String, QuizResponse>{
            'a': QuizResponse(correct: true, choiceIndex: 0),
          },
        ),
      );

      expect(find.text('Question 1 of 3'), findsOneWidget);
      expect(find.text('Picked up where you left off'), findsNothing);
      expect(find.text('Correct'), findsNothing);
    });

    testWidgets('writes the run down as it is answered', (
      WidgetTester tester,
    ) async {
      final SharedPreferences prefs = await _pumpQuiz(tester);

      await tester.tap(find.text('The buyer'));
      await tester.pumpAndSettle();

      final QuizResume? saved = LessonResumeStore(
        prefs,
      ).read(userId: 'learner-1', lessonId: 'one')?.quiz;

      expect(saved, isNotNull);
      expect(saved!.responses['a']!.correct, isTrue);
      expect(saved.questionIndex, 0);

      await tester.tap(find.widgetWithText(FilledButton, 'Next question'));
      await tester.pumpAndSettle();

      expect(
        LessonResumeStore(
          prefs,
        ).read(userId: 'learner-1', lessonId: 'one')!.quiz!.questionIndex,
        1,
        reason: 'moving on is itself worth recording',
      );
    });
  });
}

// ---------------------------------------------------------------- fixtures

final Lesson _lesson = Lesson(
  id: 'one',
  order: 1,
  title: 'Lesson one',
  summary: 'First',
  cards: const <LessonCard>[
    TitleCard(title: 'Card one', subtitle: 'The first one'),
    TitleCard(title: 'Card two', subtitle: 'The second one'),
    TitleCard(title: 'Card three', subtitle: 'The third one'),
  ],
  questions: const <QuizQuestion>[
    MultipleChoiceQuestion(
      id: 'a',
      prompt: 'Who holds the right?',
      choices: <QuizChoice>[
        QuizChoice(
          text: 'The buyer',
          isCorrect: true,
          explanation: 'The buyer pays for the choice.',
        ),
        QuizChoice(
          text: 'The seller',
          isCorrect: false,
          explanation: 'The seller carries the obligation, not the right.',
        ),
        QuizChoice(
          text: 'The exchange',
          isCorrect: false,
          explanation: 'The exchange only matches the two sides.',
        ),
      ],
    ),
    NumericQuestion(
      id: 'b',
      prompt: 'What is the premium?',
      answer: 5,
      explanation: r'It is given: $5.',
      unitPrefix: r'$',
    ),
    NumericQuestion(
      id: 'c',
      prompt: 'Where does it break even?',
      answer: 105,
      explanation: r'Strike $100 plus the $5 premium.',
      unitPrefix: r'$',
    ),
  ],
);

const QuizResume _savedRun = QuizResume(
  seed: 4242,
  questionIndex: 1,
  questionIds: <String>['a', 'b', 'c'],
  responses: <String, QuizResponse>{
    'a': QuizResponse(correct: true, choiceIndex: 0),
  },
);

final AppUser _learner = AppUser(
  id: 'learner-1',
  username: 'sam',
  educationLevel: EducationLevel.undergraduate,
  createdAt: DateTime(2026),
);

Future<SharedPreferences> _prefs() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  return SharedPreferences.getInstance();
}

Future<ProviderContainer> _container() async {
  final SharedPreferences prefs = await _prefs();
  return ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      lessonRepoProvider.overrideWithValue(_FakeLessonRepo()),
      progressRepoProvider.overrideWithValue(_MemoryProgressRepo()),
      currentUserProvider.overrideWithValue(_learner),
    ],
  );
}

/// Opens the reel with a given progress record and, optionally, a bookmark
/// already on disk — the state a learner comes back to.
Future<SharedPreferences> _pumpPlayer(
  WidgetTester tester, {
  required LessonProgress progress,
  LessonResume? bookmark,
}) async {
  final SharedPreferences prefs = await _prefs();
  if (bookmark != null) {
    await LessonResumeStore(prefs).writeAll(
      userId: _learner.id,
      bookmarks: <String, LessonResume>{'one': bookmark},
    );
  }

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        lessonRepoProvider.overrideWithValue(_FakeLessonRepo()),
        progressRepoProvider.overrideWithValue(
          _MemoryProgressRepo(<String, LessonProgress>{'one': progress}),
        ),
        currentUserProvider.overrideWithValue(_learner),
      ],
      child: const MaterialApp(home: LessonPlayerScreen(lessonId: 'one')),
    ),
  );
  await tester.pumpAndSettle();
  return prefs;
}

Future<SharedPreferences> _pumpQuiz(
  WidgetTester tester, {
  QuizResume? quiz,
}) async {
  final SharedPreferences prefs = await _prefs();
  if (quiz != null) {
    await LessonResumeStore(prefs).writeAll(
      userId: _learner.id,
      bookmarks: <String, LessonResume>{
        'one': LessonResume(lessonId: 'one', quiz: quiz),
      },
    );
  }

  final GoRouter router = GoRouter(
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (_, _) => const QuizScreen(lessonId: 'one'),
      ),
      GoRoute(
        path: Routes.learn,
        builder: (_, _) => const Scaffold(body: Text('back on the path')),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        lessonRepoProvider.overrideWithValue(_FakeLessonRepo()),
        progressRepoProvider.overrideWithValue(_MemoryProgressRepo()),
        currentUserProvider.overrideWithValue(_learner),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return prefs;
}

class _FakeLessonRepo implements LessonRepo {
  @override
  Future<List<Lesson>> loadLessons() async => <Lesson>[_lesson];

  @override
  Future<Lesson?> loadLesson(String lessonId) async =>
      lessonId == _lesson.id ? _lesson : null;
}

class _MemoryProgressRepo implements ProgressRepo {
  _MemoryProgressRepo([Map<String, LessonProgress>? seed])
    : store = <String, LessonProgress>{...?seed};

  final Map<String, LessonProgress> store;
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
    (int s, LessonProgress p) => s + p.pointsEarned,
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
