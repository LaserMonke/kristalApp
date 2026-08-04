import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:optionsschool/data/models/lesson.dart';
import 'package:optionsschool/data/models/lesson_progress.dart';
import 'package:optionsschool/data/models/quiz.dart';
import 'package:optionsschool/features/quiz/widgets/quiz_results_view.dart';
import 'package:optionsschool/providers/lesson_providers.dart';

/// Finishing a Q&A is the moment a learner is most likely to keep going, so
/// the results screen offers the next lesson by name. What matters is that it
/// never offers a button that goes nowhere.
void main() {
  LessonNode node(String id, String title, {bool finished = false}) =>
      LessonNode(
        lesson: Lesson(
          id: id,
          order: 1,
          title: title,
          summary: 's',
          cards: const <LessonCard>[
            SummaryCard(heading: 'h', takeaways: <String>[]),
          ],
        ),
        progress: LessonProgress(lessonId: id, lessonCompleted: finished),
        isUnlocked: true,
      );

  final QuizSession session = const QuizSession(
    questions: <QuizQuestion>[
      MultipleChoiceQuestion(
        id: 'q1',
        prompt: 'p',
        choices: <QuizChoice>[
          QuizChoice(text: 'a', isCorrect: true, explanation: 'e'),
          QuizChoice(text: 'b', isCorrect: false, explanation: 'e'),
        ],
      ),
    ],
  ).answer('q1', correct: true);

  Future<void> pump(
    WidgetTester tester, {
    LessonNode? next,
    void Function(LessonNode)? onStartNext,
    VoidCallback? onDone,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuizResultsView(
            lessonTitle: 'Payoff at expiry',
            session: session,
            attempts: 1,
            pointsGained: 10,
            streakDays: 1,
            nextLesson: next,
            onStartNext: onStartNext,
            onRetry: () {},
            onReviewLesson: () {},
            onDone: onDone ?? () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the next lesson is offered by name', (
    WidgetTester tester,
  ) async {
    LessonNode? started;
    await pump(
      tester,
      next: node('two', 'The Greeks'),
      onStartNext: (LessonNode n) => started = n,
    );

    final Finder button = find.widgetWithText(
      FilledButton,
      'Next: The Greeks',
    );
    expect(button, findsOneWidget);

    await tester.tap(button);
    expect(started?.lesson.id, 'two');
  });

  testWidgets('going back to the path is still offered, just not first', (
    WidgetTester tester,
  ) async {
    bool done = false;
    await pump(
      tester,
      next: node('two', 'The Greeks'),
      onStartNext: (_) {},
      onDone: () => done = true,
    );

    // Present, but as the quieter option beneath the primary one.
    final Finder back = find.widgetWithText(TextButton, 'Back to the path');
    expect(back, findsOneWidget);
    await tester.tap(back);
    expect(done, isTrue);
  });

  testWidgets('the last lesson falls back to the path', (
    WidgetTester tester,
  ) async {
    bool done = false;
    await pump(tester, onDone: () => done = true);

    expect(find.textContaining('Next:'), findsNothing);
    final Finder back = find.widgetWithText(
      FilledButton,
      'Back to the path',
    );
    expect(back, findsOneWidget);

    await tester.tap(back);
    expect(done, isTrue);
  });

  testWidgets('a next lesson with no handler is not offered', (
    WidgetTester tester,
  ) async {
    // Guards the half-wired case: a button that cannot act must not appear.
    await pump(tester, next: node('two', 'The Greeks'));
    expect(find.textContaining('Next:'), findsNothing);
    expect(
      find.widgetWithText(FilledButton, 'Back to the path'),
      findsOneWidget,
    );
  });
}
