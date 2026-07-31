import 'package:flutter_test/flutter_test.dart';
import 'package:optionsschool/data/local/local_market_repo.dart';
import 'package:optionsschool/data/models/market.dart';

/// Search is what turns the watchlist from a fixed list of five into "any
/// stock", so the pieces that decide what a learner may look up and price are
/// pinned here.
void main() {
  group('symbol shape', () {
    test('ordinary tickers pass', () {
      for (final String s in <String>['AAPL', 'KO', 'F', 'VOO', 'MSFT']) {
        expect(isPlausibleSymbol(s), isTrue, reason: s);
      }
    });

    test('exchange punctuation passes — real symbols use it', () {
      expect(isPlausibleSymbol('BRK.B'), isTrue);
      expect(isPlausibleSymbol('RDS-A'), isTrue);
    });

    test('lower case is accepted and treated as the same symbol', () {
      expect(isPlausibleSymbol('aapl'), isTrue);
    });

    test('nonsense is rejected before it costs a round trip', () {
      for (final String s in <String>[
        '',
        '   ',
        '1AAPL',
        'WAY.TOO.LONG.X',
        r'AA$PL',
        'A B',
      ]) {
        expect(isPlausibleSymbol(s), isFalse, reason: '"$s"');
      }
    });
  });

  group('offline search', () {
    final LocalMarketRepo repo = LocalMarketRepo();

    test('matches on ticker prefix', () async {
      final List<SymbolMatch> hits = await repo.search('AAP');
      expect(hits.any((SymbolMatch m) => m.symbol == 'AAPL'), isTrue);
    });

    test('matches on company name too', () async {
      final List<SymbolMatch> hits = await repo.search('vanguard');
      expect(hits.any((SymbolMatch m) => m.symbol == 'VOO'), isTrue);
    });

    test('an unknown but plausible ticker is still offered, and says so',
        () async {
      final List<SymbolMatch> hits = await repo.search('ZZZZ');
      expect(hits.first.symbol, 'ZZZZ');
      expect(hits.first.description, contains('not looked up'));
    });

    test('an empty query returns nothing rather than everything', () async {
      expect(await repo.search('   '), isEmpty);
    });
  });

  group('offline pricing of any symbol', () {
    final LocalMarketRepo repo = LocalMarketRepo();

    test('a symbol with no anchor still gets a price', () async {
      final List<Quote> quotes = await repo.quotes(<String>['ZZZZ']);
      expect(quotes, hasLength(1));
      expect(quotes.single.price, greaterThan(0));
      // Never passed off as real.
      expect(quotes.single.synthetic, isTrue);
    });

    test('the made-up anchor is stable across calls', () async {
      final List<Quote> a = await repo.quotes(<String>['WXYZ']);
      final List<Quote> b = await repo.quotes(<String>['WXYZ']);
      // Same tick, same walk — a searched symbol must not jump around.
      expect(a.single.price, b.single.price);
    });

    test('made-up prices stay in a range that keeps strikes readable',
        () async {
      final List<Quote> quotes = await repo.quotes(<String>[
        'ABCD',
        'QRST',
        'HJKL',
        'MNOP',
      ]);
      for (final Quote q in quotes) {
        expect(q.price, greaterThan(10));
        expect(q.price, lessThan(500));
      }
    });

    test('junk is dropped rather than priced', () async {
      expect(await repo.quotes(<String>['', '1BAD', r'X$X']), isEmpty);
    });

    test('case does not create a second, different symbol', () async {
      final List<Quote> upper = await repo.quotes(<String>['WXYZ']);
      final List<Quote> lower = await repo.quotes(<String>['wxyz']);
      expect(lower.single.symbol, 'WXYZ');
      expect(lower.single.price, upper.single.price);
    });
  });
}
