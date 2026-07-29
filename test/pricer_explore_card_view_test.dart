import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:optionsschool/data/models/lesson.dart';
import 'package:optionsschool/features/learn/widgets/pricer_explore_card_view.dart';
import 'package:optionsschool/pricing/black_scholes.dart';

/// The card that ties the Black-Scholes and Greeks lessons to the live
/// pricer (`lib/pricing/black_scholes.dart`) rather than the at-expiry
/// payoff engine — this checks it actually renders a live price and Greeks,
/// and that dragging its sliders recomputes them.
void main() {
  const PricerExploreCard card = PricerExploreCard(
    heading: 'Watch the price form',
    prompt: 'Drag the underlying price.',
    optionType: OptionType.call,
    strike: 100,
    volatility: 0.25,
    timeToExpiry: 0.5,
    rate: 0.04,
    spotMin: 60,
    spotMax: 140,
    spotStart: 100,
    focus: PricerGreek.delta,
    adjustVolatility: true,
  );

  Future<void> pump(WidgetTester tester, PricerExploreCard card) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PricerExploreCardView(card: card)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the heading, a theoretical price and all five Greeks', (
    WidgetTester tester,
  ) async {
    await pump(tester, card);

    expect(find.text('Watch the price form'), findsOneWidget);
    expect(find.text('Theoretical price'), findsOneWidget);
    expect(find.text('Delta'), findsOneWidget);
    expect(find.text('Gamma'), findsOneWidget);
    expect(find.text('Vega/1%'), findsOneWidget);
    expect(find.text('Theta/day'), findsOneWidget);
    expect(find.text('Rho/1%'), findsOneWidget);
  });

  testWidgets('the price shown matches the pure Dart pricer for the same inputs', (
    WidgetTester tester,
  ) async {
    await pump(tester, card);

    final BsmQuote expected = bsmQuote(
      OptionType.call,
      const BsmInputs(spot: 100, strike: 100, rate: 0.04, volatility: 0.25, timeToExpiry: 0.5),
    );
    expect(find.text(r'$' '${expected.price.toStringAsFixed(2)}'), findsOneWidget);
  });

  testWidgets('an adjust_volatility card shows a volatility slider; others do not', (
    WidgetTester tester,
  ) async {
    await pump(tester, card);
    expect(find.text('Volatility'), findsOneWidget);
    expect(find.text('Time to expiry'), findsNothing);

    const PricerExploreCard priceOnly = PricerExploreCard(
      heading: 'Price only',
      prompt: 'Drag spot.',
      optionType: OptionType.call,
      strike: 100,
      volatility: 0.25,
      timeToExpiry: 0.5,
      rate: 0.04,
      spotMin: 60,
      spotMax: 140,
      spotStart: 100,
    );
    await pump(tester, priceOnly);
    expect(find.text('Volatility'), findsNothing);
    expect(find.text('Time to expiry'), findsNothing);
  });

  testWidgets('dragging the spot slider changes the displayed price', (
    WidgetTester tester,
  ) async {
    await pump(tester, card);

    Finder priceReadout() => find.descendant(
      of: find.byWidgetPredicate(
        (Widget w) =>
            w is Row &&
            w.children.any((Widget c) => c is Text && c.data == 'Theoretical price'),
      ),
      matching: find.byType(Text),
    );

    final String before = tester.widgetList<Text>(priceReadout()).last.data!;

    // The first slider on this card is the always-present spot slider.
    await tester.drag(find.byType(Slider).first, const Offset(200, 0));
    await tester.pumpAndSettle();

    final String after = tester.widgetList<Text>(priceReadout()).last.data!;

    expect(after, isNot(before));
  });
}
