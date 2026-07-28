import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:optionsschool/core/router/app_router.dart';
import 'package:optionsschool/data/local/asset_lesson_repo.dart';
import 'package:optionsschool/data/models/lesson.dart';
import 'package:optionsschool/data/models/lesson_progress.dart';
import 'package:optionsschool/data/repositories/lesson_repo.dart';
import 'package:optionsschool/features/learn/lesson_player_screen.dart';
import 'package:optionsschool/features/learn/widgets/lesson_card_view.dart';
import 'package:optionsschool/features/learn/widgets/lesson_icons.dart';
import 'package:optionsschool/pricing/payoff.dart';
import 'package:optionsschool/providers/lesson_providers.dart';
import 'package:optionsschool/providers/progress_controller.dart';
import 'package:optionsschool/providers/repository_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('bundled lesson content', () {
    late List<Lesson> lessons;

    setUpAll(() async {
      lessons = await AssetLessonRepo().loadLessons();
    });

    test('parses and comes back in path order', () {
      expect(lessons, hasLength(3));
      expect(
        lessons.map((Lesson l) => l.id),
        <String>['what-is-an-option', 'payoff-at-expiry', 'why-use-options'],
      );
      for (int i = 1; i < lessons.length; i++) {
        expect(lessons[i].order, greaterThan(lessons[i - 1].order));
      }
    });

    test('every lesson has cards, opens on a title and ends on a summary', () {
      for (final Lesson lesson in lessons) {
        expect(lesson.cards, isNotEmpty, reason: lesson.id);
        expect(lesson.cards.first, isA<TitleCard>(), reason: lesson.id);
        expect(lesson.cards.last, isA<SummaryCard>(), reason: lesson.id);
      }
    });

    /// CLAUDE.md rule 2: every options lesson must state the downside.
    test('every lesson carries at least one risk card', () {
      for (final Lesson lesson in lessons) {
        expect(
          lesson.cards.whereType<WarningCard>(),
          isNotEmpty,
          reason: '${lesson.id} has no WarningCard',
        );
      }
    });

    /// CLAUDE.md rule 3: no profit-promise framing anywhere in the content.
    test('no lesson uses get-rich or guaranteed-return language', () {
      const List<String> banned = <String>[
        'make money',
        'get rich',
        'guaranteed',
        'risk-free',
        'easy money',
        'sure thing',
        'you should buy',
      ];

      for (final Lesson lesson in lessons) {
        final String text = <String>[
          lesson.title,
          lesson.summary,
          for (final LessonCard card in lesson.cards) card.semanticLabel,
        ].join(' ').toLowerCase();

        for (final String phrase in banned) {
          expect(
            text.contains(phrase),
            isFalse,
            reason: '${lesson.id} contains "$phrase"',
          );
        }
      }
    });

    test('total loss of premium is stated explicitly, not implied', () {
      final String all = lessons
          .expand((Lesson l) => l.cards)
          .map((LessonCard c) => c.semanticLabel)
          .join(' ')
          .toLowerCase();

      expect(all, contains('expire'));
      expect(all, contains('100% of the premium'));
      expect(all, contains('no fixed maximum loss'));
    });

    test('lessons are flagged as awaiting expert review', () {
      // Placeholder until a practitioner signs off (CLAUDE.md content rules).
      // When review happens, fill in reviewed_by and this expectation flips.
      for (final Lesson lesson in lessons) {
        expect(lesson.reviewedBy, isNull, reason: lesson.id);
      }
    });

    test('payoff cards describe legs the pricer can actually evaluate', () {
      final Iterable<PayoffCard> payoffs = lessons
          .expand((Lesson l) => l.cards)
          .whereType<PayoffCard>();
      expect(payoffs, isNotEmpty);

      for (final PayoffCard card in payoffs) {
        expect(card.spotMax, greaterThan(card.spotMin));
        expect(card.legs, isNotEmpty);
        expect(
          strategyProfit(card.legs, card.spotMin).isFinite,
          isTrue,
          reason: card.heading,
        );
      }
    });

    test('explore cards start inside their own price range', () {
      final Iterable<ExploreCard> explores = lessons
          .expand((Lesson l) => l.cards)
          .whereType<ExploreCard>();
      expect(explores, isNotEmpty);

      for (final ExploreCard card in explores) {
        expect(card.spotMax, greaterThan(card.spotMin), reason: card.heading);
        expect(card.spotStart, inInclusiveRange(card.spotMin, card.spotMax));
        expect(
          strategyProfit(card.legs, card.spotStart).isFinite,
          isTrue,
          reason: card.heading,
        );
      }
    });

    test(
      'choice cards have exactly one right answer and explain every option',
      () {
        final Iterable<ChoiceCard> choices = lessons
            .expand((Lesson l) => l.cards)
            .whereType<ChoiceCard>();
        expect(choices, isNotEmpty);

        for (final ChoiceCard card in choices) {
          expect(
            card.options.where((ChoiceOption o) => o.isCorrect),
            hasLength(1),
            reason: card.question,
          );
          for (final ChoiceOption option in card.options) {
            // Wrong answers teach too — an unexplained option is a content bug.
            expect(option.explanation, isNotEmpty, reason: option.text);
          }
        }
      },
    );

    test('every icon named in content exists in the icon set', () {
      // Icon fonts are tree-shaken, so an unknown name would silently render
      // the fallback glyph. Catch the typo here instead of on a device.
      final Set<String> known = knownLessonIconNames.toSet();
      final List<String?> used = <String?>[
        for (final Lesson lesson in lessons)
          for (final LessonCard card in lesson.cards) ...switch (card) {
            final TitleCard c => <String?>[c.icon],
            final TextCard c => <String?>[c.icon],
            final TermCard c => <String?>[c.icon],
            final CompareCard c => <String?>[c.left.icon, c.right.icon],
            _ => const <String?>[],
          },
      ];

      for (final String? name in used.whereType<String>()) {
        expect(known, contains(name));
      }
    });
  });

  group('unlock gating', () {
    final Lesson first = Lesson(
      id: 'one',
      order: 1,
      title: 'One',
      summary: 'First',
      cards: const <LessonCard>[
        TitleCard(title: 'One', subtitle: 'First'),
        SummaryCard(heading: 'Recap', takeaways: <String>['A']),
      ],
    );
    final Lesson second = Lesson(
      id: 'two',
      order: 2,
      title: 'Two',
      summary: 'Second',
      cards: const <LessonCard>[TitleCard(title: 'Two', subtitle: 'Second')],
    );

    ProviderContainer containerWith(Map<String, LessonProgress> seed) {
      return ProviderContainer(
        overrides: [
          lessonRepoProvider.overrideWithValue(
            _FakeLessonRepo(<Lesson>[first, second]),
          ),
          progressControllerProvider.overrideWith(() => _SeededProgress(seed)),
        ],
      );
    }

    test('only the first lesson is open to a new learner', () async {
      final ProviderContainer container = containerWith(
        <String, LessonProgress>{},
      );
      addTearDown(container.dispose);

      final List<LessonNode> path = await container.read(
        lessonPathProvider.future,
      );
      expect(path.map((LessonNode n) => n.isUnlocked), <bool>[true, false]);
    });

    test('finishing the cards opens the next lesson while there is no Q&A',
        () async {
      final ProviderContainer container = containerWith(<String, LessonProgress>{
        'one': const LessonProgress(
          lessonId: 'one',
          cardsViewed: 2,
          lessonCompleted: true,
        ),
      });
      addTearDown(container.dispose);

      final List<LessonNode> path = await container.read(
        lessonPathProvider.future,
      );
      expect(path.first.isFinished, isTrue);
      expect(path[1].isUnlocked, isTrue);
    });

    test('once a lesson has questions, reading the cards is not enough',
        () async {
      // Phase 2 adds questions to the JSON; the gate must move by itself.
      final Lesson quizzed = Lesson(
        id: 'one',
        order: 1,
        title: 'One',
        summary: 'First',
        quizQuestionCount: 3,
        cards: first.cards,
      );

      final ProviderContainer container = ProviderContainer(
        overrides: [
          lessonRepoProvider.overrideWithValue(
            _FakeLessonRepo(<Lesson>[quizzed, second]),
          ),
          progressControllerProvider.overrideWith(
            () => _SeededProgress(<String, LessonProgress>{
              'one': const LessonProgress(
                lessonId: 'one',
                cardsViewed: 2,
                lessonCompleted: true,
              ),
            }),
          ),
        ],
      );
      addTearDown(container.dispose);

      final List<LessonNode> path = await container.read(
        lessonPathProvider.future,
      );
      expect(path.first.isFinished, isFalse);
      expect(path[1].isUnlocked, isFalse);
    });

    test('resume lands on the first unread card', () {
      const LessonProgress progress = LessonProgress(
        lessonId: 'one',
        cardsViewed: 1,
      );
      final LessonNode node = LessonNode(
        lesson: first,
        progress: progress,
        isUnlocked: true,
      );

      expect(node.isStarted, isTrue);
      expect(node.resumeCardIndex, 1);
      expect(node.fractionRead, 0.5);
    });
  });

  testWidgets('a payoff card renders its diagram and its model caveat', (
    WidgetTester tester,
  ) async {
    const PayoffCard card = PayoffCard(
      heading: 'Long call',
      caption: 'Loss is capped at the premium.',
      spotMin: 60,
      spotMax: 140,
      legs: <StrategyLeg>[
        StrategyLeg(
          kind: LegKind.call,
          side: LegSide.long,
          strike: 100,
          premium: 5,
        ),
      ],
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: LessonCardView(card: card)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Long call'), findsOneWidget);
    expect(find.textContaining('Idealised'), findsOneWidget);
    expect(find.text('Profit'), findsOneWidget);
    expect(find.text('Loss'), findsOneWidget);
  });

  testWidgets('a short call warns that the loss has no fixed limit', (
    WidgetTester tester,
  ) async {
    const PayoffCard card = PayoffCard(
      heading: 'Short call',
      caption: 'Premium received up front.',
      spotMin: 60,
      spotMax: 160,
      legs: <StrategyLeg>[
        StrategyLeg(
          kind: LegKind.call,
          side: LegSide.short,
          strike: 100,
          premium: 5,
        ),
      ],
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: LessonCardView(card: card)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('no fixed maximum loss'), findsOneWidget);
  });

  testWidgets('a choice card reveals nothing until the learner answers', (
    WidgetTester tester,
  ) async {
    const ChoiceCard card = ChoiceCard(
      question: 'What is a buyer\'s worst case?',
      options: <ChoiceOption>[
        ChoiceOption(
          text: 'Losing the whole premium',
          isCorrect: true,
          explanation: 'The premium is the entire downside for a buyer.',
        ),
        ChoiceOption(
          text: 'Unlimited losses',
          isCorrect: false,
          explanation: 'Open-ended losses belong to the seller.',
        ),
      ],
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: LessonCardView(card: card))),
    );
    await tester.pumpAndSettle();

    // Committing to an answer comes before any explanation.
    expect(find.textContaining('Pick one'), findsOneWidget);
    expect(find.textContaining('entire downside'), findsNothing);

    await tester.tap(find.text('Unlimited losses'));
    await tester.pumpAndSettle();

    expect(find.text('Not that one'), findsOneWidget);
    expect(find.textContaining('belong to the seller'), findsOneWidget);

    await tester.tap(find.text('Losing the whole premium'));
    await tester.pumpAndSettle();

    expect(find.text('That one is right'), findsOneWidget);
    expect(find.textContaining('entire downside'), findsOneWidget);
  });

  testWidgets('the explorer recomputes the readout as the price moves', (
    WidgetTester tester,
  ) async {
    const ExploreCard card = ExploreCard(
      heading: 'Drive the long call',
      prompt: 'Find break-even.',
      spotMin: 60,
      spotMax: 140,
      spotStart: 80,
      legs: <StrategyLeg>[
        StrategyLeg(
          kind: LegKind.call,
          side: LegSide.long,
          strike: 100,
          premium: 5,
        ),
      ],
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: LessonCardView(card: card))),
    );
    await tester.pumpAndSettle();

    // At $80 the call expires worthless: the loss is the whole $5 premium.
    expect(find.text('−\$5  loss'), findsOneWidget);

    // Drag the underlying slider to its maximum, $140: profit 140-100-5 = 35.
    await tester.drag(find.byType(Slider).first, const Offset(400, 0));
    await tester.pumpAndSettle();

    expect(find.text('+\$35  profit'), findsOneWidget);

    // The simulation label stays put whatever the sliders say (CLAUDE.md rule 4).
    expect(find.textContaining('Simulation for learning'), findsOneWidget);
  });

  group('the card/reel player', () {
    final Lesson lesson = Lesson(
      id: 'one',
      order: 1,
      title: 'Lesson one',
      summary: 'First',
      cards: const <LessonCard>[
        TitleCard(title: 'Opening card', subtitle: 'Sets things up'),
        SummaryCard(heading: 'Recap', takeaways: <String>['Remember this']),
      ],
    );

    testWidgets('advances through the deck and reports where the learner is', (
      WidgetTester tester,
    ) async {
      await _pumpPlayer(tester, lesson, <String>[]);

      expect(find.text('Opening card'), findsOneWidget);
      expect(find.text('1/2'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(find.text('Recap'), findsOneWidget);
      expect(find.text('2/2'), findsOneWidget);
      expect(find.text('Finish lesson'), findsOneWidget);
    });

    testWidgets('says the lesson is not yet expert-reviewed on the last card', (
      WidgetTester tester,
    ) async {
      await _pumpPlayer(tester, lesson, <String>[]);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(find.textContaining('not yet been reviewed'), findsOneWidget);
    });

    testWidgets('finishing records completion and returns to the path', (
      WidgetTester tester,
    ) async {
      final List<String> completed = <String>[];
      await _pumpPlayer(tester, lesson, completed);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Finish lesson'));
      await tester.pumpAndSettle();

      expect(completed, <String>['one']);
      expect(find.text('back on the path'), findsOneWidget);
    });
  });
}

/// Drives the reel the way a learner does: open, advance, finish.
Future<void> _pumpPlayer(
  WidgetTester tester,
  Lesson lesson,
  List<String> completed,
) async {
  final GoRouter router = GoRouter(
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (_, _) => LessonPlayerScreen(lessonId: lesson.id),
      ),
      GoRoute(
        path: Routes.learn,
        builder: (_, _) => const Scaffold(body: Text('back on the path')),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        lessonRepoProvider.overrideWithValue(_FakeLessonRepo(<Lesson>[lesson])),
        progressControllerProvider.overrideWith(
          () => _RecordingProgress(completed),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
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

/// Progress fixed at construction, so the path can be tested without an
/// authenticated user or shared_preferences.
class _SeededProgress extends ProgressController {
  _SeededProgress(this.seed);

  final Map<String, LessonProgress> seed;

  @override
  Future<Map<String, LessonProgress>> build() async => seed;
}

/// Captures what the player writes, instead of persisting it.
class _RecordingProgress extends ProgressController {
  _RecordingProgress(this.completed);

  final List<String> completed;

  @override
  Future<Map<String, LessonProgress>> build() async =>
      <String, LessonProgress>{};

  @override
  Future<void> recordCardViewed({
    required String lessonId,
    required int cardIndex,
  }) async {}

  @override
  Future<void> markLessonCompleted({
    required String lessonId,
    required int totalCards,
  }) async {
    completed.add(lessonId);
  }
}
