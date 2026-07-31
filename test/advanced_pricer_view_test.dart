import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:optionsschool/data/models/lesson.dart';
import 'package:optionsschool/data/repositories/lesson_repo.dart';
import 'package:optionsschool/features/sandbox/sandbox_screen.dart';
import 'package:optionsschool/pricing/barrier.dart';
import 'package:optionsschool/pricing/black_scholes.dart';
import 'package:optionsschool/pricing/pricing_job.dart';
import 'package:optionsschool/providers/advanced_pricer_providers.dart';
import 'package:optionsschool/providers/pricer_providers.dart';
import 'package:optionsschool/providers/repository_providers.dart';
import 'package:riverpod/misc.dart' show Override;
import 'package:shared_preferences/shared_preferences.dart';

/// Drives the Phase 8 "Advanced" tab the way a learner does: pick an
/// instrument, set the contract up, run it, read the answer.
///
/// The assertions lean hard on the honesty requirements, because on this tab
/// they are the substance rather than decoration: a simulated price must never
/// appear without its error bar, a structured product must never appear
/// without its worst case, and a bundle sold at 100 must show what it is
/// actually worth (CLAUDE.md rules 2, 4 and 5).
///
/// `lessonRepoProvider` is faked for the same reason as in
/// `sandbox_screen_test.dart`: real asset loading never resolves inside
/// `testWidgets` here.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    List<Override> overrides = const <Override>[],
  }) async {
    tester.view.physicalSize = const Size(1200, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues(<String, Object>{
      'sandbox.tutorial_seen': true,
    });
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    late final ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(prefs),
          lessonRepoProvider.overrideWithValue(_FakeLessonRepo()),
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

  Future<ProviderContainer> openAdvanced(
    WidgetTester tester, {
    List<Override> overrides = const <Override>[],
  }) async {
    final ProviderContainer container = await pump(
      tester,
      overrides: overrides,
    );
    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();
    return container;
  }

  /// Keeps every simulation in these tests small enough to finish inline.
  void makeFast(ProviderContainer container) {
    container
        .read(advancedSettingsProvider.notifier)
        .update((AdvancedSettings s) => s.copyWith(paths: 2000, steps: 10));
  }

  testWidgets('the Advanced tab exists alongside the other two', (
    WidgetTester tester,
  ) async {
    await pump(tester);
    expect(find.text('Single option'), findsOneWidget);
    expect(find.text('Strategy'), findsOneWidget);
    expect(find.text('Advanced'), findsOneWidget);
  });

  testWidgets('it opens on barrier options and explains what one is', (
    WidgetTester tester,
  ) async {
    await openAdvanced(tester);

    expect(find.text('Barrier'), findsOneWidget);
    expect(find.textContaining('dies — or only comes alive'), findsOneWidget);
    // Every instrument is named before any number appears.
    for (final String name in <String>[
      'Asian',
      'Basket',
      'Heston',
      'Structured',
    ]) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
  });

  testWidgets('nothing is priced until Run is pressed', (
    WidgetTester tester,
  ) async {
    await openAdvanced(tester);

    expect(find.text('Run simulation'), findsOneWidget);
    expect(find.textContaining('press Run'), findsNothing);
    expect(find.textContaining('Press Run'), findsOneWidget);
    expect(find.text('SIMULATED PRICE'), findsNothing);
  });

  testWidgets('running shows a price WITH its error bar and interval', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = await openAdvanced(tester);
    makeFast(container);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Run simulation'));
    await tester.pumpAndSettle();

    expect(find.text('SIMULATED PRICE'), findsOneWidget);
    // The error bar is not optional, and not a footnote.
    expect(find.textContaining('±'), findsOneWidget);
    expect(find.textContaining('19 answers in 20'), findsOneWidget);
    expect(find.textContaining('independent paths'), findsOneWidget);
  });

  testWidgets('a barrier run shows the exact formula beside the estimate', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = await openAdvanced(tester);
    makeFast(container);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Run simulation'));
    await tester.pumpAndSettle();

    expect(find.text('Exact formula'), findsOneWidget);
    expect(find.textContaining('standard errors from the exact answer'),
        findsOneWidget);
  });

  testWidgets('the result says where the work happened', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = await openAdvanced(tester);
    makeFast(container);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Run simulation'));
    await tester.pumpAndSettle();

    // A learner is entitled to know whether their inputs left the phone.
    expect(find.textContaining('Ran on this device'), findsOneWidget);
  });

  testWidgets('changing the contract clears a stale result', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = await openAdvanced(tester);
    makeFast(container);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Run simulation'));
    await tester.pumpAndSettle();
    expect(find.text('SIMULATED PRICE'), findsOneWidget);

    // A price computed for a call must not sit on screen looking like the
    // answer for a put.
    await tester.tap(find.text('Put'));
    await tester.pumpAndSettle();
    expect(find.text('SIMULATED PRICE'), findsNothing);
  });

  testWidgets('switching instrument clears the result too', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = await openAdvanced(tester);
    makeFast(container);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Run simulation'));
    await tester.pumpAndSettle();
    expect(find.text('SIMULATED PRICE'), findsOneWidget);

    await tester.tap(find.text('Asian'));
    await tester.pumpAndSettle();
    expect(find.text('SIMULATED PRICE'), findsNothing);
  });

  testWidgets('an already-breached barrier is called out before running', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = await openAdvanced(tester);
    // Spot is 100 by default; put the down barrier above it.
    container
        .read(advancedSettingsProvider.notifier)
        .update((AdvancedSettings s) => s.copyWith(barrierRatio: 1.2));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('already dead and worth nothing'),
      findsOneWidget,
    );
  });

  testWidgets('the basket tab shows its correlation controls', (
    WidgetTester tester,
  ) async {
    await openAdvanced(tester);
    await tester.tap(find.text('Basket'));
    await tester.pumpAndSettle();

    expect(find.text('Assets in the basket'), findsOneWidget);
    expect(find.text('Correlation between them'), findsOneWidget);
  });

  testWidgets('the Heston tab shows its parameters', (
    WidgetTester tester,
  ) async {
    await openAdvanced(tester);
    await tester.tap(find.text('Heston'));
    await tester.pumpAndSettle();

    expect(find.text('Price / volatility correlation'), findsOneWidget);
  });

  testWidgets('the Heston vol-of-vol slider stops at the documented floor', (
    WidgetTester tester,
  ) async {
    await openAdvanced(tester);
    await tester.tap(find.text('Heston'));
    await tester.pumpAndSettle();

    final Slider volOfVol = tester
        .widgetList<Slider>(find.byType(Slider))
        .firstWhere((Slider s) => s.min == 0.01);
    // Below this the semi-analytic price degrades, so the UI does not go
    // there — see HestonParams.minimumUsableVolOfVol.
    expect(volOfVol.min, 0.01);
  });

  group('structured products', () {
    testWidgets('show the decomposition, sold legs marked as sold', (
      WidgetTester tester,
    ) async {
      await openAdvanced(tester);
      await tester.tap(find.text('Structured'));
      await tester.pumpAndSettle();

      expect(find.text('WHAT IS INSIDE THE WRAPPER'), findsOneWidget);
      expect(find.text('Zero-coupon bond'), findsOneWidget);
      expect(find.text('Model value of the bundle'), findsOneWidget);
    });

    testWidgets('always show the worst case', (WidgetTester tester) async {
      await openAdvanced(tester);
      await tester.tap(find.text('Structured'));
      await tester.pumpAndSettle();

      expect(find.text('Worst case'), findsOneWidget);
      expect(find.textContaining('issuer'), findsWidgets);
    });

    testWidgets('show what the buyer pays over the model value', (
      WidgetTester tester,
    ) async {
      await openAdvanced(tester);
      await tester.tap(find.text('Structured'));
      await tester.pumpAndSettle();

      expect(find.text('Paid on day one'), findsOneWidget);
      expect(find.textContaining('issuer\'s costs and profit'), findsOneWidget);
      // The credit assumption is named, not buried.
      expect(find.textContaining('Lehman Brothers'), findsOneWidget);
    });

    testWidgets('a reverse convertible marks its sold put as SOLD', (
      WidgetTester tester,
    ) async {
      final ProviderContainer container = await openAdvanced(tester);
      await tester.tap(find.text('Structured'));
      await tester.pumpAndSettle();

      container.read(advancedSettingsProvider.notifier).update(
            (AdvancedSettings s) =>
                s.copyWith(product: StructuredProductKind.reverseConvertible),
          );
      await tester.pumpAndSettle();

      expect(find.textContaining('SOLD.'), findsOneWidget);
      expect(find.textContaining('Short put at'), findsOneWidget);
    });

    testWidgets('there is no Run button, because none is needed', (
      WidgetTester tester,
    ) async {
      await openAdvanced(tester);
      await tester.tap(find.text('Structured'));
      await tester.pumpAndSettle();

      // These are compositions of closed forms; simulating them would be
      // theatre.
      expect(find.text('Run simulation'), findsNothing);
    });
  });

  testWidgets('the simulation disclaimers are always on screen', (
    WidgetTester tester,
  ) async {
    await openAdvanced(tester);
    expect(find.textContaining('Simulation for learning'), findsOneWidget);
    expect(find.textContaining('simplifying assumptions'), findsOneWidget);
  });

  group('the job the tab builds', () {
    test('matches the controls, and is serialisable', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(advancedSettingsProvider.notifier).update(
            (AdvancedSettings s) => s.copyWith(
              strike: 110,
              barrierRatio: 0.7,
              barrierStyle: BarrierStyle.knockIn,
              optionType: OptionType.put,
            ),
          );

      final PricingJob? job = container.read(advancedJobProvider);
      expect(job, isA<BarrierPricingJob>());

      final BarrierPricingJob barrier = job! as BarrierPricingJob;
      expect(barrier.inputs.strike, 110);
      expect(barrier.spec.style, BarrierStyle.knockIn);
      expect(barrier.spec.type, OptionType.put);
      // The barrier is a ratio of spot, so it stays sensible as spot moves.
      expect(
        barrier.spec.barrier,
        container.read(marketEnvironmentProvider).spot * 0.7,
      );

      // And it survives the trip an isolate or the server would put it
      // through.
      expect(
        () => PricingJob.fromJson(job.toJson()),
        returnsNormally,
      );
    });

    test('a basket job uses one step, since only the endpoint matters', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      container
          .read(advancedInstrumentProvider.notifier)
          .select(AdvancedInstrument.basket);
      container
          .read(advancedSettingsProvider.notifier)
          .update((AdvancedSettings s) => s.copyWith(steps: 250));

      final PricingJob job = container.read(advancedJobProvider)!;
      expect(job.settings.steps, 1);
    });

    test('a structured product needs no job at all', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      container
          .read(advancedInstrumentProvider.notifier)
          .select(AdvancedInstrument.structured);
      expect(container.read(advancedJobProvider), isNull);
    });

    test('the seed is fixed, so re-running is not a dice roll', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      final int first = container.read(advancedJobProvider)!.settings.seed;
      final int second = container.read(advancedJobProvider)!.settings.seed;
      expect(first, second);
    });

    test('basket assets are generic, never named companies', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      container
          .read(advancedInstrumentProvider.notifier)
          .select(AdvancedInstrument.basket);
      final BasketPricingJob job =
          container.read(advancedJobProvider)! as BasketPricingJob;

      for (final String name in job.spec.assets.map((dynamic a) => a.name)) {
        expect(name, startsWith('Asset '));
      }
    });
  });
}

class _FakeLessonRepo implements LessonRepo {
  @override
  Future<List<Lesson>> loadLessons() async => const <Lesson>[];

  @override
  Future<Lesson?> loadLesson(String lessonId) async => null;
}
