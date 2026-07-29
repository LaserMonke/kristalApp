import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:optionsschool/data/models/lesson.dart';
import 'package:optionsschool/data/models/lesson_progress.dart';
import 'package:optionsschool/data/models/quiz.dart';
import 'package:optionsschool/data/repositories/lesson_repo.dart';
import 'package:optionsschool/features/sandbox/sandbox_screen.dart';
import 'package:optionsschool/providers/pricer_providers.dart';
import 'package:optionsschool/providers/progress_controller.dart';
import 'package:optionsschool/providers/repository_providers.dart';
import 'package:optionsschool/providers/sandbox_tutorial_controller.dart';
import 'package:riverpod/misc.dart' show Override;
import 'package:shared_preferences/shared_preferences.dart';

/// Drives the Sandbox tab the way a learner does: reads the price, flips
/// call to put, drags a slider, switches to the Strategy tab and swaps
/// presets — the same interactions attempted on the iOS simulator, run here
/// so they're checked on every future change rather than by eye once.
///
/// `lessonRepoProvider` is always overridden with a fake here: real asset
/// loading via `rootBundle` never resolves inside `testWidgets` in this
/// project's test setup (every other widget test touching lessons does the
/// same — see `lesson_engine_test.dart`), so relying on it would leave the
/// Strategy gate stuck in `AsyncLoading` for the whole test.
///
/// Most tests pre-seed the tutorial as already-seen so the one-time modal
/// (covered separately below) doesn't sit over the screen intercepting taps.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    Map<String, Object> prefsSeed = const <String, Object>{'sandbox.tutorial_seen': true},
    List<Override> overrides = const <Override>[],
  }) async {
    // Tall enough that every panel on both tabs — including the payoff
    // diagram and the trailing disclaimer — is on-screen without needing to
    // scroll mid-test, matching how a real phone renders this content just
    // fine but a bit more of it.
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues(prefsSeed);
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    late final ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(prefs),
          lessonRepoProvider.overrideWithValue(_FakeLessonRepo(<Lesson>[_strategiesLesson])),
          ...overrides,
        ],
        child: Consumer(
          builder: (BuildContext context, WidgetRef ref, _) {
            container = ProviderScope.containerOf(context);
            return const MaterialApp(home: SandboxScreen());
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('Single option tab opens on a call and shows a live price', (
    WidgetTester tester,
  ) async {
    await pump(tester);

    expect(find.text('Single option'), findsOneWidget);
    expect(find.text('Theoretical price'), findsOneWidget);
    expect(find.text('Delta'), findsOneWidget);
    expect(find.text('Gamma'), findsOneWidget);
    expect(find.text('Vega'), findsOneWidget);
    expect(find.textContaining(r'$'), findsWidgets);
  });

  testWidgets('switching call to put changes the displayed price', (
    WidgetTester tester,
  ) async {
    await pump(tester);

    final Finder priceReadout = find.descendant(
      of: find.byWidgetPredicate(
        (Widget w) =>
            w is Row &&
            w.children.any((Widget c) => c is Text && (c).data == 'Theoretical price'),
      ),
      matching: find.byType(Text),
    );
    final String callPrice = tester.widgetList<Text>(priceReadout).last.data!;

    await tester.tap(find.text('Put'));
    await tester.pumpAndSettle();

    final String putPrice = tester.widgetList<Text>(priceReadout).last.data!;
    expect(putPrice, isNot(callPrice));
  });

  testWidgets('dragging the strike slider changes the price', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = await pump(tester);
    final double before = container.read(singleOptionQuoteProvider).price;

    // Two sliders are visible on the "Single option" tab before scrolling
    // (market volatility is the first, strike the second) — drag the
    // second one, which belongs to the option card.
    await tester.drag(find.byType(Slider).at(1), const Offset(200, 0));
    await tester.pumpAndSettle();

    final double after = container.read(singleOptionQuoteProvider).price;
    expect(after, isNot(before));
  });

  testWidgets('the shared market inputs panel appears on both tabs', (
    WidgetTester tester,
  ) async {
    await pump(tester);
    expect(find.text('MARKET INPUTS'), findsOneWidget);

    await tester.tap(find.text('Single option'));
    await tester.pumpAndSettle();
    expect(find.text('MARKET INPUTS'), findsOneWidget);
  });

  group('the Strategy tab is gated on the strategies lesson', () {
    testWidgets('shows a locked panel, not the preset picker, by default', (
      WidgetTester tester,
    ) async {
      await pump(tester);

      await tester.tap(find.text('Strategy'));
      await tester.pumpAndSettle();

      expect(find.text('Strategy tab locked'), findsOneWidget);
      expect(find.text('Go to Learn'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Bull call spread'), findsNothing);
    });

    testWidgets('the tab label carries a lock icon while locked', (
      WidgetTester tester,
    ) async {
      await pump(tester);
      expect(
        find.descendant(
          of: find.widgetWithText(Tab, 'Strategy'),
          matching: find.byIcon(Icons.lock_outline),
        ),
        findsOneWidget,
      );
    });

    testWidgets('unlocks once the options-strategies lesson is finished', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        overrides: <Override>[
          progressControllerProvider.overrideWith(
            () => _SeededProgress(<String, LessonProgress>{
              'options-strategies': const LessonProgress(
                lessonId: 'options-strategies',
                lessonCompleted: true,
                quizCompleted: true,
              ),
            }),
          ),
        ],
      );

      await tester.tap(find.text('Strategy'));
      await tester.pumpAndSettle();

      expect(find.text('Strategy tab locked'), findsNothing);
      expect(find.widgetWithText(ChoiceChip, 'Bull call spread'), findsOneWidget);
      expect(
        find.descendant(
          of: find.widgetWithText(Tab, 'Strategy'),
          matching: find.byIcon(Icons.lock_outline),
        ),
        findsNothing,
      );
    });
  });

  group('the one-time tutorial', () {
    testWidgets('shows automatically the first time the Sandbox opens', (
      WidgetTester tester,
    ) async {
      await pump(tester, prefsSeed: const <String, Object>{});

      expect(find.text('Welcome to the Sandbox'), findsOneWidget);
    });

    testWidgets('does not reappear once already seen', (WidgetTester tester) async {
      await pump(tester);
      expect(find.text('Welcome to the Sandbox'), findsNothing);
    });

    testWidgets('dismissing it records that it has been seen', (WidgetTester tester) async {
      final ProviderContainer container = await pump(
        tester,
        prefsSeed: const <String, Object>{},
      );

      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();

      expect(find.text('Welcome to the Sandbox'), findsNothing);
      expect(container.read(sandboxTutorialSeenProvider), isTrue);
    });

    testWidgets('the help icon reopens it even after it has been seen', (
      WidgetTester tester,
    ) async {
      await pump(tester);
      expect(find.text('Welcome to the Sandbox'), findsNothing);

      await tester.tap(find.byTooltip('How the Sandbox works'));
      await tester.pumpAndSettle();

      expect(find.text('Welcome to the Sandbox'), findsOneWidget);
    });
  });

  testWidgets('the idealised-simulation disclaimer is always visible', (
    WidgetTester tester,
  ) async {
    await pump(tester);
    expect(find.textContaining('Simulation for learning'), findsOneWidget);
  });
}

/// Bypasses the repository layer entirely and hands back a fixed progress
/// map — mirrors the same helper in `lesson_engine_test.dart`.
class _SeededProgress extends ProgressController {
  _SeededProgress(this.seed);

  final Map<String, LessonProgress> seed;

  @override
  Future<Map<String, LessonProgress>> build() async => seed;
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

/// Just enough of a lesson for the gate to have something real to check:
/// an id of "options-strategies" (what the gate looks for) with a quiz
/// question attached, so `LessonNode.hasQuiz` — and therefore the gate's
/// notion of "finished" — behaves the same way the real lesson does.
final Lesson _strategiesLesson = Lesson(
  id: 'options-strategies',
  order: 1,
  title: 'Options strategies',
  summary: 'Combining legs to fit a view of the market.',
  cards: const <LessonCard>[
    TitleCard(title: 'Options strategies', subtitle: 'Test fixture.'),
    SummaryCard(heading: 'Recap', takeaways: <String>['A']),
  ],
  questions: const <QuizQuestion>[
    MultipleChoiceQuestion(
      id: 'q1',
      prompt: 'Test question?',
      choices: <QuizChoice>[
        QuizChoice(text: 'Right', isCorrect: true, explanation: 'Because.'),
        QuizChoice(text: 'Wrong', isCorrect: false, explanation: 'Because not.'),
      ],
    ),
  ],
);
