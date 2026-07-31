import 'package:flutter_test/flutter_test.dart';
import 'package:optionsschool/data/market/symbol_index.dart';

/// The point of the catalogue is that a learner who does not know tickers can
/// still find a company, and that a wrong letter does not send them away empty
/// handed. Both are ranking problems, so the ranking is pinned here.
void main() {
  String? top(String query) {
    final List<ScoredCompany> hits = searchCatalog(query);
    return hits.isEmpty ? null : hits.first.company.symbol;
  }

  List<String> symbols(String query) => <String>[
    for (final ScoredCompany h in searchCatalog(query)) h.company.symbol,
  ];

  group('by company name', () {
    test('a plain name finds its ticker', () {
      expect(top('apple'), 'AAPL');
      expect(top('microsoft'), 'MSFT');
      expect(top('tesla'), 'TSLA');
      expect(top('netflix'), 'NFLX');
    });

    test('multi-word names work, punctuation and all', () {
      expect(top('coca cola'), 'KO');
      expect(top('coca-cola'), 'KO');
      expect(top('johnson & johnson'), 'JNJ');
      expect(top('home depot'), 'HD');
    });

    test('the legal suffix is optional', () {
      expect(top('apple inc'), 'AAPL');
      expect(top('ford motor co'), 'F');
    });

    test('the name people use beats the name on the filing', () {
      expect(top('google'), 'GOOGL');
      expect(top('facebook'), 'META');
      expect(top('disney'), 'DIS');
      expect(top('coke'), 'KO');
    });

    test('a partial name is enough', () {
      expect(symbols('starbu'), contains('SBUX'));
      expect(symbols('lockheed'), contains('LMT'));
    });
  });

  group('by ticker', () {
    test('an exact ticker wins outright', () {
      expect(top('AAPL'), 'AAPL');
      expect(top('KO'), 'KO');
      expect(searchCatalog('AAPL').first.exact, isTrue);
    });

    test('lower case still finds it', () {
      expect(top('aapl'), 'AAPL');
    });

    test('a ticker prefix reaches the company', () {
      expect(symbols('nvd'), contains('NVDA'));
    });
  });

  group('typos', () {
    test('one wrong letter still finds the company', () {
      expect(symbols('aple'), contains('AAPL'));
      expect(symbols('tesla motors'), contains('TSLA'));
      expect(symbols('microsft'), contains('MSFT'));
      expect(symbols('netflx'), contains('NFLX'));
      expect(symbols('amazn'), contains('AMZN'));
    });

    test('a typo in one word of several is forgiven', () {
      expect(symbols('coca cloa'), contains('KO'));
      expect(symbols('home dept'), contains('HD'));
    });

    test('a transposition is forgiven', () {
      expect(symbols('googel'), contains('GOOGL'));
      expect(symbols('teslsa'), contains('TSLA'));
    });

    test('a guess never outranks something typed correctly', () {
      // "visa" is exact; nothing fuzzy should displace it.
      expect(top('visa'), 'V');
    });
  });

  group('restraint', () {
    test('an empty query returns nothing', () {
      expect(searchCatalog(''), isEmpty);
      expect(searchCatalog('    '), isEmpty);
    });

    test('an unrelated word does not drag in the catalogue', () {
      expect(searchCatalog('qwertyuiop'), isEmpty);
      expect(searchCatalog('bicycle repair'), isEmpty);
    });

    test('results are capped', () {
      expect(searchCatalog('a', limit: 5).length, lessThanOrEqualTo(5));
    });

    test('hits come back best first', () {
      final List<ScoredCompany> hits = searchCatalog('app');
      for (int i = 1; i < hits.length; i++) {
        expect(hits[i - 1].score, greaterThanOrEqualTo(hits[i].score));
      }
    });
  });

  group('helpers', () {
    test('normalising strips punctuation and filler', () {
      expect(normalizeName('Coca-Cola Co'), 'coca cola');
      expect(normalizeName('Apple Inc'), 'apple');
      expect(normalizeName('JPMorgan Chase & Co'), 'jpmorgan chase');
    });

    test('a name that is nothing but filler survives normalising', () {
      expect(normalizeName('The Trust Co'), isNotEmpty);
    });

    test('edit distance counts single-character edits', () {
      expect(editDistance('apple', 'apple'), 0);
      expect(editDistance('aple', 'apple'), 1);
      expect(editDistance('', 'abc'), 3);
      expect(editDistance('kitten', 'sitting'), 3);
    });

    test('similarity is 1 for identical strings and falls with distance', () {
      expect(similarity('apple', 'apple'), 1);
      expect(similarity('aple', 'apple'), closeTo(0.8, 0.001));
      expect(similarity('abc', 'xyz'), closeTo(0, 0.001));
    });
  });
}
