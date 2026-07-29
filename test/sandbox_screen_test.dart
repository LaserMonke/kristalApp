import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:optionsschool/features/practice/practice_screen.dart';
import 'package:optionsschool/providers/pricer_providers.dart';
import 'package:optionsschool/providers/repository_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Drives the Phase 4 Practice tab the way a learner does: reads the price,
/// flips call to put, drags a slider, switches to the Strategy tab and swaps
/// presets — the same interactions attempted on the iOS simulator, run here
/// so they're checked on every future change rather than by eye once.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pump(WidgetTester tester) async {
    // Tall enough that every panel on both tabs — including the payoff
    // diagram and the trailing disclaimer — is on-screen without needing to
    // scroll mid-test, matching how a real phone renders this content just
    // fine but a bit more of it.
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const MaterialApp(home: PracticeScreen()),
      ),
    );
    await tester.pumpAndSettle();
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
    await pump(tester);

    final BuildContext context = tester.element(find.byType(PracticeScreen));
    final ProviderContainer container = ProviderScope.containerOf(context);
    final double before = container.read(singleOptionQuoteProvider).price;

    // Two sliders are visible on the "Single option" tab before scrolling
    // (market volatility is the first, strike the second) — drag the
    // second one, which belongs to the option card.
    await tester.drag(find.byType(Slider).at(1), const Offset(200, 0));
    await tester.pumpAndSettle();

    final double after = container.read(singleOptionQuoteProvider).price;
    expect(after, isNot(before));
  });

  testWidgets('Strategy tab opens on the bull call spread with two legs', (
    WidgetTester tester,
  ) async {
    await pump(tester);

    await tester.tap(find.text('Strategy'));
    await tester.pumpAndSettle();

    expect(find.text('Bull call spread'), findsWidgets);
    expect(find.text('Long call'), findsOneWidget);
    expect(find.text('Short call'), findsOneWidget);
    expect(find.text('Combined payoff at expiry'), findsOneWidget);
  });

  testWidgets('selecting a different preset rebuilds the legs shown', (
    WidgetTester tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Strategy'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, 'Covered call'));
    await tester.pumpAndSettle();

    expect(find.text('Long shares'), findsOneWidget);
    expect(find.text('Short call'), findsOneWidget);
    expect(find.text('Long call'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Straddle'));
    await tester.pumpAndSettle();

    expect(find.text('Long call'), findsOneWidget);
    expect(find.text('Long put'), findsOneWidget);
  });

  testWidgets('the shared market inputs panel appears on both tabs', (
    WidgetTester tester,
  ) async {
    await pump(tester);
    expect(find.text('MARKET INPUTS'), findsOneWidget);

    await tester.tap(find.text('Strategy'));
    await tester.pumpAndSettle();
    expect(find.text('MARKET INPUTS'), findsOneWidget);
  });

  testWidgets('the idealised-simulation disclaimer is always visible', (
    WidgetTester tester,
  ) async {
    await pump(tester);
    expect(find.textContaining('Simulation for learning'), findsOneWidget);

    await tester.tap(find.text('Strategy'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Simulation for learning'), findsOneWidget);
  });
}
