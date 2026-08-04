import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:optionsschool/data/models/market.dart';
import 'package:optionsschool/data/repositories/market_repo.dart';
import 'package:optionsschool/features/stockle/stockle_screen.dart';
import 'package:optionsschool/games/stockle/stockle_engine.dart';
import 'package:optionsschool/providers/repository_providers.dart';
import 'package:optionsschool/providers/stockle_providers.dart';
import 'package:riverpod/misc.dart' show Override;
import 'package:shared_preferences/shared_preferences.dart';

/// Drives the real screen the way a player does — tapping the on-screen
/// keyboard — so the wiring between engine, persistence and UI is covered, not
/// just the scoring rules.
class _FakeMarketRepo implements MarketRepo {
  @override
  Future<List<Quote>> quotes(List<String> symbols) async => <Quote>[
    Quote(symbol: symbols.first, price: 123.45, change: 1.5, percentChange: 1.2),
  ];

  @override
  Future<List<SymbolMatch>> search(String query) async => <SymbolMatch>[];
}

void main() {
  late StockleDictionary dictionary;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    dictionary = StockleDictionary(
      asOf: '2026-08-04',
      tickers: const <StockleTicker>[
        StockleTicker(symbol: 'AAPL', name: 'Apple', sector: 'Technology'),
        StockleTicker(symbol: 'MSFT', name: 'Microsoft', sector: 'Technology'),
        StockleTicker(symbol: 'TSLA', name: 'Tesla', sector: 'Consumer'),
      ],
    );
  });

  Future<ProviderContainer> pump(WidgetTester tester) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(prefs),
        stockleDictionaryProvider.overrideWith((_) async => dictionary),
        marketRepoProvider.overrideWithValue(_FakeMarketRepo()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: StockleScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> type(WidgetTester tester, String word) async {
    for (final String letter in word.split('')) {
      await tester.tap(find.widgetWithText(InkWell, letter).first);
      await tester.pump();
    }
  }

  testWidgets('the board and keyboard are on screen', (tester) async {
    await pump(tester);

    expect(find.text('Stockle'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Guess'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Delete'), findsOneWidget);
  });

  testWidgets('a guess that is not in the list is refused with a reason', (
    tester,
  ) async {
    final container = await pump(tester);
    // Force a known answer so the assertions do not depend on today's date.
    expect(container.read(stockleProvider), isNotNull);

    await type(tester, 'ZZZZ');
    await tester.tap(find.widgetWithText(FilledButton, 'Guess'));
    await tester.pump();

    expect(find.text('Not a NASDAQ-100 ticker in today’s list.'), findsOneWidget);
  });

  testWidgets('Guess stays disabled until four letters are typed', (
    tester,
  ) async {
    await pump(tester);

    final Finder guess = find.widgetWithText(FilledButton, 'Guess');
    expect(tester.widget<FilledButton>(guess).onPressed, isNull);

    await type(tester, 'AAP');
    expect(tester.widget<FilledButton>(guess).onPressed, isNull);

    await type(tester, 'L');
    expect(tester.widget<FilledButton>(guess).onPressed, isNotNull);
  });

  testWidgets('Delete removes the last letter', (tester) async {
    await pump(tester);

    await type(tester, 'AAPL');
    await tester.tap(find.widgetWithText(OutlinedButton, 'Delete'));
    await tester.pump();

    expect(
      tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Guess'),
      ).onPressed,
      isNull,
    );
  });

  testWidgets('solving shows the overview of the company behind the ticker', (
    tester,
  ) async {
    final container = await pump(tester);
    final String answer = container.read(stockleProvider)!.answer.symbol;

    await type(tester, answer);
    await tester.tap(find.widgetWithText(FilledButton, 'Guess'));
    await tester.pumpAndSettle();

    // The reward: the company, not just a win message.
    expect(find.textContaining('Solved in 1'), findsOneWidget);
    expect(
      find.text(container.read(stockleProvider)!.answer.name),
      findsOneWidget,
    );
    // And the price carries its honesty label.
    expect(find.text('Delayed price, not real time.'), findsOneWidget);
  });

  testWidgets('a finished game is restored after leaving the screen', (
    tester,
  ) async {
    final container = await pump(tester);
    final String answer = container.read(stockleProvider)!.answer.symbol;

    await type(tester, answer);
    await tester.tap(find.widgetWithText(FilledButton, 'Guess'));
    await tester.pumpAndSettle();

    // Rebuilding the controller must not hand out a fresh board — that would
    // let a lost day be replayed for another go at the points.
    container.invalidate(stockleProvider);
    expect(container.read(stockleProvider)!.isOver, isTrue);
  });

  testWidgets('the keyboard disappears once the day is done', (tester) async {
    final container = await pump(tester);
    final String answer = container.read(stockleProvider)!.answer.symbol;

    await type(tester, answer);
    await tester.tap(find.widgetWithText(FilledButton, 'Guess'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Guess'), findsNothing);
  });
}
