import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:optionsschool/core/router/app_router.dart';
import 'package:optionsschool/data/local/asset_lesson_repo.dart';
import 'package:optionsschool/data/models/app_user.dart';
import 'package:optionsschool/data/models/education_level.dart';
import 'package:optionsschool/data/models/lesson.dart';
import 'package:optionsschool/data/models/lesson_progress.dart';
import 'package:optionsschool/data/models/quiz.dart';
import 'package:optionsschool/data/repositories/lesson_repo.dart';
import 'package:optionsschool/data/repositories/progress_repo.dart';
import 'package:optionsschool/features/quiz/quiz_screen.dart';
import 'package:optionsschool/providers/auth_controller.dart';
import 'package:optionsschool/providers/lesson_providers.dart';
import 'package:optionsschool/providers/progress_controller.dart';
import 'package:optionsschool/providers/repository_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('reading learner input', () {
    test('accepts the ways people actually write money', () {
      expect(parseNumericAnswer('105'), 105);
      expect(parseNumericAnswer(r' $105 '), 105);
      expect(parseNumericAnswer('105.00'), 105);
      expect(parseNumericAnswer('1,050'), 1050);
      expect(parseNumericAnswer('+9'), 9);
      expect(parseNumericAnswer('-9'), -9);
      // The payoff readouts render a Unicode minus; pasting one back should work.
      expect(parseNumericAnswer('−9'), -9);
    });

    test('gives back nothing when there is no number to grade', () {
      expect(parseNumericAnswer(''), isNull);
      expect(parseNumericAnswer('   '), isNull);
      expect(parseNumericAnswer('about a hundred'), isNull);
      expect(parseNumericAnswer(r'$'), isNull);
    });
  });

  group('grading a numeric question', () {
    const NumericQuestion question = NumericQuestion(
      id: 'break-even',
      prompt: 'Where does the position break even?',
      answer: 87,
      tolerance: 0.01,
      unitPrefix: r'$',
      explanation: r'Strike $80 plus premium $7.',
    );

    test('accepts the answer, and the same answer written as currency', () {
      expect(question.accepts(87), isTrue);
      expect(question.acceptsInput('87'), isTrue);
      expect(question.acceptsInput(r'$87.00'), isTrue);
    });

    test('rejects a near miss outside the tolerance', () {
      expect(question.accepts(87.5), isFalse);
      expect(question.accepts(80), isFalse, reason: 'strike, not break-even');
      expect(question.accepts(-87), isFalse);
    });

    test('unparseable input is wrong rather than an error', () {
      expect(question.acceptsInput('no idea'), isFalse);
      expect(question.acceptsInput(''), isFalse);
    });

    test('a tolerance is honoured on both sides', () {
      const NumericQuestion loose = NumericQuestion(
        id: 'loose',
        prompt: 'Roughly?',
        answer: 10,
        tolerance: 0.5,
        explanation: 'Anything close.',
      );
      expect(loose.accepts(9.5), isTrue);
      expect(loose.accepts(10.5), isTrue);
      expect(loose.accepts(9.4), isFalse);
      expect(loose.accepts(10.6), isFalse);
    });

    test('whole answers are shown without a stray decimal', () {
      expect(question.formattedAnswer, r'$87');
      expect(formatQuizNumber(2.5), '2.5');
      expect(formatQuizNumber(2.50), '2.5');
      expect(formatQuizNumber(0.25), '0.25');
    });
  });

  group('a run through the Q&A', () {
    final List<QuizQuestion> questions = <QuizQuestion>[
      const MultipleChoiceQuestion(
        id: 'a',
        prompt: 'Who holds the right?',
        choices: <QuizChoice>[
          QuizChoice(
            text: 'The buyer',
            isCorrect: true,
            explanation: 'The premium buys the choice.',
          ),
          QuizChoice(
            text: 'The seller',
            isCorrect: false,
            explanation: 'The seller carries the obligation.',
          ),
        ],
      ),
      const NumericQuestion(
        id: 'b',
        prompt: 'Break-even?',
        answer: 105,
        explanation: r'Strike $100 plus premium $5.',
      ),
    ];

    test('an untouched session has nothing scored', () {
      final QuizSession session = QuizSession(questions: questions);
      expect(session.total, 2);
      expect(session.answered, 0);
      expect(session.correct, 0);
      expect(session.score, 0);
      expect(session.isComplete, isFalse);
      expect(session.verdictFor('a'), isNull);
    });

    test('answering counts, and completes the run', () {
      final QuizSession session = QuizSession(questions: questions)
          .answer('a', correct: true)
          .answer('b', correct: false);

      expect(session.answered, 2);
      expect(session.correct, 1);
      expect(session.score, 0.5);
      expect(session.isComplete, isTrue);
      expect(session.verdictFor('a'), isTrue);
      expect(session.verdictFor('b'), isFalse);
    });

    test('only the first answer to a question counts', () {
      // Otherwise a learner could tap through options until one stuck, which
      // would measure persistence rather than understanding.
      final QuizSession session = QuizSession(questions: questions)
          .answer('a', correct: false)
          .answer('a', correct: true);

      expect(session.verdictFor('a'), isFalse);
      expect(session.answered, 1);
    });

    test('answering leaves the previous session untouched', () {
      final QuizSession before = QuizSession(questions: questions);
      final QuizSession after = before.answer('a', correct: true);

      expect(before.answered, 0);
      expect(after.answered, 1);
    });
  });

  group('bundled Q&A content', () {
    late List<Lesson> lessons;

    setUpAll(() async {
      lessons = await AssetLessonRepo().loadLessons();
    });

    test('every lesson ends in a Q&A', () {
      for (final Lesson lesson in lessons) {
        expect(lesson.hasQuiz, isTrue, reason: lesson.id);
        expect(lesson.questions.length, greaterThanOrEqualTo(3), reason: lesson.id);
        expect(lesson.quizQuestionCount, lesson.questions.length);
      }
    });

    test('question ids are unique within a lesson', () {
      // Answers are keyed by id, so a duplicate would silently overwrite a
      // learner's result for another question.
      for (final Lesson lesson in lessons) {
        final Set<String> ids = lesson.questions
            .map((QuizQuestion q) => q.id)
            .toSet();
        expect(ids, hasLength(lesson.questions.length), reason: lesson.id);
      }
    });

    test('both question types are used across the course', () {
      final Iterable<QuizQuestion> all = lessons.expand(
        (Lesson l) => l.questions,
      );
      expect(all.whereType<MultipleChoiceQuestion>(), isNotEmpty);
      expect(all.whereType<NumericQuestion>(), isNotEmpty);
    });

    test('each choice question has one right answer and explains them all', () {
      final Iterable<MultipleChoiceQuestion> choices = lessons
          .expand((Lesson l) => l.questions)
          .whereType<MultipleChoiceQuestion>();
      expect(choices, isNotEmpty);

      for (final MultipleChoiceQuestion q in choices) {
        expect(
          q.choices.where((QuizChoice c) => c.isCorrect),
          hasLength(1),
          reason: q.id,
        );
        expect(q.choices.length, greaterThanOrEqualTo(2), reason: q.id);
        for (final QuizChoice c in q.choices) {
          // A wrong answer with no explanation teaches nothing.
          expect(c.explanation, isNotEmpty, reason: '${q.id}: ${c.text}');
        }
      }
    });

    test('each numeric question accepts its own stated answer', () {
      final Iterable<NumericQuestion> numerics = lessons
          .expand((Lesson l) => l.questions)
          .whereType<NumericQuestion>();
      expect(numerics, isNotEmpty);

      for (final NumericQuestion q in numerics) {
        expect(q.accepts(q.answer), isTrue, reason: q.id);
        expect(q.tolerance, greaterThan(0), reason: q.id);
        expect(q.explanation, isNotEmpty, reason: q.id);
        // A tolerance wide enough to swallow a wrong method is not a tolerance.
        expect(q.tolerance, lessThan(1), reason: q.id);
      }
    });

    /// The finance has to be right, not just the plumbing (CLAUDE.md).
    test('the payoff arithmetic in the answers checks out', () {
      final Map<String, double> expected = <String, double>{
        // One contract of 100 shares at a $2.30 premium.
        'q3-contract-size': 230,
        // Long call, strike 80 + premium 7.
        'q1-call-break-even': 87,
        // Long put, strike 100, premium 6, settling at 88: (100-88) - 6.
        'q2-put-profit': 6,
        // Shares at 100 + put struck 95 costing 4: floor of (100-95) + 4.
        'q1-protective-put-floor': 9,
      };

      final Map<String, NumericQuestion> byId = <String, NumericQuestion>{
        for (final NumericQuestion q
            in lessons.expand((Lesson l) => l.questions).whereType<NumericQuestion>())
          q.id: q,
      };

      expected.forEach((String id, double answer) {
        expect(byId[id], isNotNull, reason: 'missing question $id');
        expect(byId[id]!.answer, answer, reason: id);
      });
    });

    test('every question carries the reasoning, not just a verdict', () {
      for (final Lesson lesson in lessons) {
        for (final QuizQuestion q in lesson.questions) {
          expect(q.prompt, isNotEmpty, reason: q.id);
          expect(q.teachingNote, isNotNull, reason: '${q.id} has no takeaway');
        }
      }
    });
  });

  group('recording a result', () {
    test('completing the Q&A unlocks the next lesson', () async {
      final ProviderContainer container = _containerWith(
        <String, LessonProgress>{},
      );
      addTearDown(container.dispose);

      await container.read(progressControllerProvider.future);
      await container
          .read(progressControllerProvider.notifier)
          .recordQuizResult(lessonId: 'one', correct: 2, total: 4);

      final List<LessonNode> path = await container.read(
        lessonPathProvider.future,
      );
      expect(path.first.progress.quizCompleted, isTrue);
      expect(path.first.isFinished, isTrue);
      expect(path[1].isUnlocked, isTrue, reason: 'a weak score still unlocks');
    });

    test('a retake can raise the recorded score but never lower it', () async {
      final ProviderContainer container = _containerWith(
        <String, LessonProgress>{},
      );
      addTearDown(container.dispose);

      await container.read(progressControllerProvider.future);
      final ProgressController progress = container.read(
        progressControllerProvider.notifier,
      );

      await progress.recordQuizResult(lessonId: 'one', correct: 4, total: 4);
      await progress.recordQuizResult(lessonId: 'one', correct: 1, total: 4);

      final LessonProgress result = container
          .read(progressControllerProvider)
          .value!['one']!;
      expect(result.correctAnswers, 4);
      expect(result.quizAttempts, 2);
      expect(result.pointsEarned, 40);
    });

    test('an improved retake replaces the old score', () async {
      final ProviderContainer container = _containerWith(
        <String, LessonProgress>{},
      );
      addTearDown(container.dispose);

      await container.read(progressControllerProvider.future);
      final ProgressController progress = container.read(
        progressControllerProvider.notifier,
      );

      await progress.recordQuizResult(lessonId: 'one', correct: 1, total: 4);
      await progress.recordQuizResult(lessonId: 'one', correct: 3, total: 4);

      final LessonProgress result = container
          .read(progressControllerProvider)
          .value!['one']!;
      expect(result.correctAnswers, 3);
      expect(result.score, 0.75);
    });

    test('reading the cards alone does not unlock a lesson with a Q&A', () async {
      final ProviderContainer container = _containerWith(
        <String, LessonProgress>{
          'one': const LessonProgress(
            lessonId: 'one',
            cardsViewed: 2,
            lessonCompleted: true,
          ),
        },
      );
      addTearDown(container.dispose);

      final List<LessonNode> path = await container.read(
        lessonPathProvider.future,
      );
      expect(path.first.isFinished, isFalse);
      expect(path.first.needsQuiz, isTrue);
      expect(path[1].isUnlocked, isFalse);
    });
  });

  group('the Q&A screen', () {
    testWidgets('feedback appears only after the learner commits', (
      WidgetTester tester,
    ) async {
      await _pumpQuiz(tester);

      expect(find.text('Question 1 of 2'), findsOneWidget);
      expect(find.text('The premium buys the choice.'), findsNothing);

      // Advancing is blocked until something has been answered.
      final Finder next = find.widgetWithText(FilledButton, 'Next question');
      expect(tester.widget<FilledButton>(next).onPressed, isNull);

      await tester.tap(find.text('The buyer'));
      await tester.pumpAndSettle();

      expect(find.text('Correct'), findsOneWidget);
      expect(find.text('The premium buys the choice.'), findsOneWidget);
      expect(tester.widget<FilledButton>(next).onPressed, isNotNull);
    });

    testWidgets('a wrong choice still shows what the answer was', (
      WidgetTester tester,
    ) async {
      await _pumpQuiz(tester);

      await tester.tap(find.text('The seller'));
      await tester.pumpAndSettle();

      expect(find.text('Not quite'), findsOneWidget);
      expect(find.textContaining('The answer was "The buyer"'), findsOneWidget);
    });

    testWidgets('a question cannot be re-answered once committed', (
      WidgetTester tester,
    ) async {
      await _pumpQuiz(tester);

      await tester.tap(find.text('The seller'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('The buyer'));
      await tester.pumpAndSettle();

      // Still the original verdict — tapping around does not upgrade a miss.
      expect(find.text('Not quite'), findsOneWidget);
      expect(find.text('Correct'), findsNothing);
    });

    testWidgets('two taps in one frame do not disagree with the score', (
      WidgetTester tester,
    ) async {
      final _MemoryProgressRepo repo = await _pumpQuiz(tester);

      // Both taps land before the parent can rebuild with a verdict. Without a
      // guard the panel would explain the second answer while the first was
      // the one recorded.
      await tester.tap(find.text('The seller'));
      await tester.tap(find.text('The buyer'));
      await tester.pumpAndSettle();

      expect(find.text('Not quite'), findsOneWidget);
      expect(find.text('Correct'), findsNothing);

      await tester.tap(find.text('Next question'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '105');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Check answer'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'See results'));
      await tester.pumpAndSettle();

      // The displayed verdict and the saved score tell the same story.
      expect(find.text('1/2'), findsOneWidget);
      expect(repo.store['one']!.correctAnswers, 1);
    });

    testWidgets('a double-tapped finish is recorded as one attempt', (
      WidgetTester tester,
    ) async {
      final _MemoryProgressRepo repo = await _pumpQuiz(tester);

      await tester.tap(find.text('The buyer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next question'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '105');
      await tester.pumpAndSettle();

      final Finder check = find.widgetWithText(FilledButton, 'Check answer');
      await tester.tap(check);
      await tester.tap(check, warnIfMissed: false);
      await tester.pumpAndSettle();

      final Finder finish = find.widgetWithText(FilledButton, 'See results');
      await tester.tap(finish);
      await tester.tap(finish, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(repo.store['one']!.quizAttempts, 1);
      expect(repo.store['one']!.correctAnswers, 2);
    });

    testWidgets('a short answer is graded and the working is shown', (
      WidgetTester tester,
    ) async {
      await _pumpQuiz(tester);

      await tester.tap(find.text('The buyer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next question'));
      await tester.pumpAndSettle();

      expect(find.text('Question 2 of 2'), findsOneWidget);

      // Nothing to check until a number has been typed.
      final Finder check = find.widgetWithText(FilledButton, 'Check answer');
      expect(tester.widget<FilledButton>(check).onPressed, isNull);

      await tester.enterText(find.byType(TextField), r'$105');
      await tester.pumpAndSettle();
      await tester.tap(check);
      await tester.pumpAndSettle();

      expect(find.text('Correct'), findsOneWidget);
      expect(find.textContaining('Strike'), findsOneWidget);
    });

    testWidgets('finishing records the score and reports it honestly', (
      WidgetTester tester,
    ) async {
      final _MemoryProgressRepo repo = await _pumpQuiz(tester);

      await tester.tap(find.text('The seller')); // wrong
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next question'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '99'); // wrong
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Check answer'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'See results'));
      await tester.pumpAndSettle();

      final LessonProgress saved = repo.store['one']!;
      expect(saved.quizCompleted, isTrue, reason: 'the next lesson opens');
      expect(saved.correctAnswers, 0);
      expect(saved.totalQuestions, 2);
      expect(saved.quizAttempts, 1);

      expect(find.text('0/2'), findsOneWidget);
      expect(find.text('Worth another look'), findsOneWidget);

      // A weak score sends the learner back to the cards, but does not trap
      // them: both ways out are offered.
      await tester.scrollUntilVisible(
        find.text('Read the lesson again'),
        250,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Read the lesson again'), findsOneWidget);
      expect(find.text('Back to the path'), findsOneWidget);
    });

    testWidgets('the recap lists the right answer for every question', (
      WidgetTester tester,
    ) async {
      await _pumpQuiz(tester);

      await tester.tap(find.text('The buyer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next question'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '105');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Check answer'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'See results'));
      await tester.pumpAndSettle();

      expect(find.text('2/2'), findsOneWidget);
      expect(find.text('All correct'), findsOneWidget);
      expect(find.text('Answer: The buyer'), findsOneWidget);
      expect(find.text(r'Answer: $105'), findsOneWidget);
    });

    testWidgets('leaving the Q&A returns to the path', (
      WidgetTester tester,
    ) async {
      await _pumpQuiz(tester);

      await tester.tap(find.byTooltip('Leave the Q&A'));
      await tester.pumpAndSettle();

      expect(find.text('back on the path'), findsOneWidget);
    });
  });
}

/// A two-question lesson: one of each question type.
final Lesson _lesson = Lesson(
  id: 'one',
  order: 1,
  title: 'Lesson one',
  summary: 'First',
  cards: const <LessonCard>[
    TitleCard(title: 'Lesson one', subtitle: 'First'),
    SummaryCard(heading: 'Recap', takeaways: <String>['Remember this']),
  ],
  questions: const <QuizQuestion>[
    MultipleChoiceQuestion(
      id: 'a',
      prompt: 'Who holds the right?',
      choices: <QuizChoice>[
        QuizChoice(
          text: 'The buyer',
          isCorrect: true,
          explanation: 'The premium buys the choice.',
        ),
        QuizChoice(
          text: 'The seller',
          isCorrect: false,
          explanation: 'The seller carries the obligation.',
        ),
      ],
    ),
    NumericQuestion(
      id: 'b',
      prompt: 'Break-even?',
      answer: 105,
      unitPrefix: r'$',
      explanation: r'Strike $100 plus premium $5.',
    ),
  ],
);

final Lesson _second = Lesson(
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

/// Only the two things that need a device are replaced — the shared_preferences
/// store and the signed-in session. The real [ProgressController] runs on top,
/// so its best-score and attempt-counting rules are what these tests exercise.
ProviderContainer _containerWith(Map<String, LessonProgress> seed) {
  return ProviderContainer(
    overrides: [
      lessonRepoProvider.overrideWithValue(
        _FakeLessonRepo(<Lesson>[_lesson, _second]),
      ),
      progressRepoProvider.overrideWithValue(_MemoryProgressRepo(seed)),
      currentUserProvider.overrideWithValue(_learner),
    ],
  );
}

/// Drives the Q&A the way a learner does, returning the store it writes to.
Future<_MemoryProgressRepo> _pumpQuiz(WidgetTester tester) async {
  final _MemoryProgressRepo repo = _MemoryProgressRepo(
    <String, LessonProgress>{},
  );

  final GoRouter router = GoRouter(
    routes: <RouteBase>[
      GoRoute(path: '/', builder: (_, _) => QuizScreen(lessonId: _lesson.id)),
      GoRoute(
        path: Routes.learn,
        builder: (_, _) => const Scaffold(body: Text('back on the path')),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        lessonRepoProvider.overrideWithValue(_FakeLessonRepo(<Lesson>[_lesson])),
        progressRepoProvider.overrideWithValue(repo),
        currentUserProvider.overrideWithValue(_learner),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

class _FakeLessonRepo implements LessonRepo {
  _FakeLessonRepo(this.lessons);

  final List<Lesson> lessons;

  @override
  Future<List<Lesson>> loadLessons() async => lessons;

  @override
  Future<Lesson?> loadLesson(String lessonId) async {
    for (final Lesson lesson in lessons) {
      if (lesson.id == lessonId) return lesson;
    }
    return null;
  }
}

/// The ProgressRepo contract, backed by a map instead of shared_preferences.
class _MemoryProgressRepo implements ProgressRepo {
  _MemoryProgressRepo(this.store);

  final Map<String, LessonProgress> store;

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
  Future<void> clear(String userId) async => store.clear();
}
