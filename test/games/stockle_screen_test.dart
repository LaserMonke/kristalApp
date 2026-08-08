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
    Quote(
      symbol: symbols.first,
      price: 123.45,
      change: 1.5,
      percentChange: 1.2,
    ),
  ];

  @override
  Future<List<SymbolMatch>> search(String query) async => <SymbolMatch>[];
}

void main() {
  late StockleDictionary dictionary;

  setUp(() {
    // Default to a returning player: the rules sheet opens itself only on a
    // first visit, and the play-flow tests below need the board reachable.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'stockle.how_to_play_seen': true,
    });
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

  testWidgets('the rules open themselves on a first visit, once', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await pump(tester);
    expect(find.text('How to play'), findsOneWidget);

    // Dismissing it records the visit, so it does not greet the player again.
    Navigator.of(tester.element(find.text('How to play'))).pop();
    await tester.pumpAndSettle();

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('stockle.how_to_play_seen'), isTrue);
  });

  testWidgets('a returning player is not shown the rules unasked', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('How to play'), findsNothing);
  });

  testWidgets('the ticker list button shows the whole playable set', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.text('View the ticker list'));
    await tester.pumpAndSettle();

    expect(find.text('Ticker list'), findsOneWidget);
    for (final StockleTicker ticker in dictionary.tickers) {
      expect(find.text(ticker.symbol), findsWidgets);
      expect(find.text(ticker.name), findsOneWidget);
    }

    // Searching narrows it to what the player typed.
    await tester.enterText(find.byType(TextField), 'micro');
    await tester.pumpAndSettle();
    expect(find.text('Microsoft'), findsOneWidget);
    expect(find.text('Tesla'), findsNothing);
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

    expect(
      find.text('Not a NASDAQ-100 ticker in today’s list.'),
      findsOneWidget,
    );
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
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Guess'))
          .onPressed,
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

    // A correct solve pops a little celebration naming the company.
    expect(find.text('Correct!'), findsOneWidget);
    expect(
      find.text(container.read(stockleProvider)!.answer.name),
      findsWidgets,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Nice'));
    await tester.pumpAndSettle();

    // The reward underneath: the company overview, not just a win message.
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

  testWidgets('a hint waits for the third guess, then waits to be asked', (
    tester,
  ) async {
    // Six tickers so there are always three wrong ones to spend, whichever is
    // today's answer.
    dictionary = StockleDictionary(
      asOf: '2026-08-04',
      tickers: const <StockleTicker>[
        StockleTicker(symbol: 'AAPL', name: 'Apple', sector: 'Technology'),
        StockleTicker(symbol: 'MSFT', name: 'Microsoft', sector: 'Technology'),
        StockleTicker(symbol: 'TSLA', name: 'Tesla', sector: 'Consumer'),
        StockleTicker(symbol: 'NFLX', name: 'Netflix', sector: 'Media'),
        StockleTicker(symbol: 'GILD', name: 'Gilead', sector: 'Health Care'),
        StockleTicker(symbol: 'COST', name: 'Costco', sector: 'Staples'),
      ],
    );

    final container = await pump(tester);
    final StockleTicker answer = container.read(stockleProvider)!.answer;

    expect(find.textContaining('A hint unlocks'), findsOneWidget);

    final List<String> wrong = dictionary.tickers
        .where((StockleTicker t) => t.symbol != answer.symbol)
        .map((StockleTicker t) => t.symbol)
        .take(guessesBeforeHint)
        .toList();

    for (final String symbol in wrong) {
      await type(tester, symbol);
      await tester.tap(find.widgetWithText(FilledButton, 'Guess'));
      await tester.pumpAndSettle();
    }

    // Unlocked — but silent until the player asks, so a puzzle nobody wanted
    // narrowed stays unspoiled.
    expect(find.textContaining(answer.sector), findsNothing);

    final Finder reveal = find.widgetWithText(TextButton, 'Show a hint');
    await tester.ensureVisible(reveal);
    await tester.pumpAndSettle();
    await tester.tap(reveal);
    await tester.pumpAndSettle();

    expect(find.textContaining(answer.sector), findsOneWidget);
    expect(
      find.textContaining('starts with ${answer.name[0]}'),
      findsOneWidget,
    );
    // Never a letter of the ticker itself.
    expect(find.textContaining(answer.symbol), findsNothing);
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
