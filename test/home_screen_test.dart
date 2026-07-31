import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:optionsschool/core/router/app_router.dart';
import 'package:optionsschool/data/models/app_user.dart';
import 'package:optionsschool/data/models/education_level.dart';
import 'package:optionsschool/data/models/lesson.dart';
import 'package:optionsschool/data/models/lesson_progress.dart';
import 'package:optionsschool/data/models/quiz.dart';
import 'package:optionsschool/data/repositories/lesson_repo.dart';
import 'package:optionsschool/data/repositories/progress_repo.dart';
import 'package:optionsschool/engagement/streak.dart';
import 'package:optionsschool/features/home/home_screen.dart';
import 'package:optionsschool/providers/auth_controller.dart';
import 'package:optionsschool/providers/repository_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The Home tab is a dashboard, so what it must get right is telling the
/// learner the truth about where they are and pointing at one next action.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpHome(
    WidgetTester tester, {
    Map<String, LessonProgress> progress = const <String, LessonProgress>{},
  }) async {
    final GoRouter router = GoRouter(
      routes: <RouteBase>[
        GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
        GoRoute(
          path: Routes.lesson,
          builder: (_, _) => const Scaffold(body: Text('in the lesson')),
        ),
        GoRoute(
          path: Routes.quiz,
          builder: (_, _) => const Scaffold(body: Text('in the Q&A')),
        ),
        GoRoute(
          path: Routes.certificate,
          builder: (_, _) => const Scaffold(body: Text('the certificate')),
        ),
      ],
    );
    addTearDown(router.dispose);

    // The app-bar theme toggle reads persisted settings.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          lessonRepoProvider.overrideWithValue(_FakeLessonRepo()),
          progressRepoProvider.overrideWithValue(
            _MemoryProgressRepo(Map<String, LessonProgress>.of(progress)),
          ),
          currentUserProvider.overrideWithValue(_learner),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows points, level and streak', (WidgetTester tester) async {
    await pumpHome(tester);

    // The greeting and avatar this test once asserted were removed
    // deliberately in "Settings reachable from every tab; drop tab titles and
    // Home greeting" — the tab opens straight onto the learner's standing.
    // Every stat is words AND a number, never colour alone (accessibility).
    expect(find.text('0'), findsWidgets, reason: 'points and streak start at 0');
    expect(find.text('Newcomer'), findsOneWidget);
    expect(find.text('day streak'), findsOneWidget);
    expect(find.text('points'), findsOneWidget);
    expect(find.textContaining('level 1 of'), findsOneWidget);
  });

  testWidgets('a fresh learner is pointed at the first lesson', (
    WidgetTester tester,
  ) async {
    await pumpHome(tester);

    expect(find.textContaining('Lesson 1 · Lesson one'), findsOneWidget);
    expect(find.text('2 cards · about 3 min'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Start lesson'));
    await tester.pumpAndSettle();
    expect(find.text('in the lesson'), findsOneWidget);
  });

  testWidgets('a part-read lesson offers to continue where it stopped', (
    WidgetTester tester,
  ) async {
    await pumpHome(
      tester,
      progress: <String, LessonProgress>{
        'one': const LessonProgress(lessonId: 'one', cardsViewed: 1),
      },
    );

    expect(find.text('Card 1 of 2'), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'Continue lesson'),
      findsOneWidget,
    );
  });

  testWidgets('cards read but Q&A outstanding sends the learner to the Q&A', (
    WidgetTester tester,
  ) async {
    await pumpHome(
      tester,
      progress: <String, LessonProgress>{
        'one': const LessonProgress(
          lessonId: 'one',
          cardsViewed: 2,
          lessonCompleted: true,
        ),
      },
    );

    expect(find.textContaining('1 questions to go'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Start the Q&A'));
    await tester.pumpAndSettle();
    expect(find.text('in the Q&A'), findsOneWidget);
  });

  testWidgets('certificate progress counts only fully finished lessons', (
    WidgetTester tester,
  ) async {
    await pumpHome(
      tester,
      progress: <String, LessonProgress>{
        // Deck read but Q&A outstanding — not finished, so it must not count.
        'one': const LessonProgress(
          lessonId: 'one',
          cardsViewed: 2,
          lessonCompleted: true,
        ),
      },
    );

    // The hero fills the top of the tab, so the certificate card sits below
    // the fold on a test-sized surface and the ListView has not built it yet.
    await tester.scrollUntilVisible(
      find.text('0 of 2 lessons finished'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('0 of 2 lessons finished'), findsOneWidget);

    await tester.tap(find.text('0 of 2 lessons finished'));
    await tester.pumpAndSettle();
    expect(find.text('the certificate'), findsOneWidget);
  });

  testWidgets('finishing everything points at the certificate instead', (
    WidgetTester tester,
  ) async {
    await pumpHome(
      tester,
      progress: <String, LessonProgress>{
        'one': const LessonProgress(
          lessonId: 'one',
          cardsViewed: 2,
          lessonCompleted: true,
          quizCompleted: true,
        ),
        'two': const LessonProgress(
          lessonId: 'two',
          cardsViewed: 1,
          lessonCompleted: true,
        ),
      },
    );

    expect(find.text('Every lesson is finished'), findsOneWidget);
    expect(find.text('Earned — open to view it'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });
}

final Lesson _one = Lesson(
  id: 'one',
  order: 1,
  title: 'Lesson one',
  summary: 'What an option is',
  estimatedMinutes: 3,
  cards: const <LessonCard>[
    TitleCard(title: 'One', subtitle: 'First'),
    SummaryCard(heading: 'Recap', takeaways: <String>['Remember this']),
  ],
  questions: const <QuizQuestion>[
    MultipleChoiceQuestion(
      id: 'a',
      prompt: 'Who holds the right?',
      choices: <QuizChoice>[
        QuizChoice(text: 'The buyer', isCorrect: true, explanation: 'Yes.'),
        QuizChoice(text: 'The seller', isCorrect: false, explanation: 'No.'),
      ],
    ),
  ],
);

final Lesson _two = Lesson(
  id: 'two',
  order: 2,
  title: 'Lesson two',
  summary: 'Payoffs at expiry',
  cards: const <LessonCard>[TitleCard(title: 'Two', subtitle: 'Second')],
);

final AppUser _learner = AppUser(
  id: 'learner-1',
  username: 'sam',
  educationLevel: EducationLevel.undergraduate,
  createdAt: DateTime(2026),
);

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
  _MemoryProgressRepo(this.store);

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
