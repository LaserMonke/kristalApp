import 'dart:math' as math;

import '../models/market.dart';
import '../repositories/market_repo.dart';

/// A stand-in market for offline use: a seeded random walk per symbol, so the
/// practice market is fully usable on the simulator with no server and no API
/// key. Every quote it returns is flagged `synthetic` so the UI never presents
/// these made-up prices as real (CLAUDE.md rule 4 & 8).
class LocalMarketRepo implements MarketRepo {
  LocalMarketRepo();

  // Plausible anchor prices for the familiar names; anything else gets a
  // made-up anchor derived from its own letters (see [_anchorFor]).
  static const Map<String, double> _anchors = <String, double>{
    'AAPL': 230,
    'MSFT': 430,
    'SPY': 560,
    'TSLA': 250,
    'NVDA': 120,
  };

  /// A handful of well-known tickers so offline search returns something
  /// recognisable. Not a market listing — the real lookup is the provider's.
  static const Map<String, String> _known = <String, String>{
    'AAPL': 'Apple Inc',
    'MSFT': 'Microsoft Corp',
    'SPY': 'SPDR S&P 500 ETF Trust',
    'TSLA': 'Tesla Inc',
    'NVDA': 'NVIDIA Corp',
    'AMZN': 'Amazon.com Inc',
    'GOOGL': 'Alphabet Inc Class A',
    'META': 'Meta Platforms Inc',
    'NFLX': 'Netflix Inc',
    'AMD': 'Advanced Micro Devices Inc',
    'INTC': 'Intel Corp',
    'JPM': 'JPMorgan Chase & Co',
    'DIS': 'Walt Disney Co',
    'KO': 'Coca-Cola Co',
    'QQQ': 'Invesco QQQ Trust',
    'VOO': 'Vanguard S&P 500 ETF',
  };

  @override
  Future<List<Quote>> quotes(List<String> symbols) async {
    // A slowly-moving clock so successive polls drift rather than jump wildly,
    // but still change visibly. One "tick" per 15s.
    final int tick = DateTime.now().millisecondsSinceEpoch ~/ 15000;

    return <Quote>[
      for (final String symbol in symbols)
        if (isPlausibleSymbol(symbol)) _walk(symbol.toUpperCase(), tick),
    ];
  }

  @override
  Future<List<SymbolMatch>> search(String query) async {
    final String q = query.trim().toUpperCase();
    if (q.isEmpty) return const <SymbolMatch>[];

    final List<SymbolMatch> hits = <SymbolMatch>[
      for (final MapEntry<String, String> e in _known.entries)
        if (e.key.startsWith(q) || e.value.toUpperCase().contains(q))
          SymbolMatch(symbol: e.key, description: e.value),
    ];

    // Offline there is no listing to check against, so a plausible ticker the
    // list has never heard of is still offered — with the description saying
    // plainly that it was not looked up.
    if (hits.every((SymbolMatch m) => m.symbol != q) &&
        isPlausibleSymbol(q)) {
      hits.insert(
        0,
        SymbolMatch(symbol: q, description: 'Simulated — not looked up'),
      );
    }
    return hits;
  }

  Quote _walk(String symbol, int tick) {
    final double anchor = _anchorFor(symbol);
    // Deterministic per (symbol, tick): a smooth-ish oscillation plus jitter.
    final int seed = symbol.hashCode ^ tick;
    final math.Random rng = math.Random(seed);
    final double wobble =
        math.sin(tick / 6 + symbol.hashCode % 7) * anchor * 0.015;
    final double jitter = (rng.nextDouble() - 0.5) * anchor * 0.01;
    final double price = anchor + wobble + jitter;
    final double prevClose = anchor;
    final double change = price - prevClose;

    return Quote(
      symbol: symbol,
      price: double.parse(price.toStringAsFixed(2)),
      change: double.parse(change.toStringAsFixed(2)),
      percentChange: double.parse(
        (change / prevClose * 100).toStringAsFixed(2),
      ),
      delayed: true,
      synthetic: true,
    );
  }

  /// A stable made-up price for a symbol we have no anchor for, so a searched
  /// ticker behaves consistently across polls and restarts. Spread over a range
  /// that keeps option premiums and strikes readable ($20–$420).
  double _anchorFor(String symbol) {
    final double? known = _anchors[symbol];
    if (known != null) return known;
    return 20 + (symbol.hashCode.abs() % 4001) / 10;
  }
}
