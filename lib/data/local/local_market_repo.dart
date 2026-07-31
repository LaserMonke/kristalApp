import 'dart:math' as math;

import '../models/market.dart';
import '../repositories/market_repo.dart';

/// A stand-in market for offline use: a seeded random walk per symbol, so the
/// practice market is fully usable on the simulator with no server and no API
/// key. Every quote it returns is flagged `synthetic` so the UI never presents
/// these made-up prices as real (CLAUDE.md rule 4 & 8).
class LocalMarketRepo implements MarketRepo {
  LocalMarketRepo();

  // Plausible anchor prices; the walk drifts around these.
  static const Map<String, double> _anchors = <String, double>{
    'AAPL': 230,
    'MSFT': 430,
    'SPY': 560,
    'TSLA': 250,
    'NVDA': 120,
  };

  @override
  Future<List<Quote>> quotes(List<String> symbols) async {
    // A slowly-moving clock so successive polls drift rather than jump wildly,
    // but still change visibly. One "tick" per 15s.
    final int tick = DateTime.now().millisecondsSinceEpoch ~/ 15000;

    return <Quote>[
      for (final String symbol in symbols)
        if (_anchors.containsKey(symbol)) _walk(symbol, tick),
    ];
  }

  Quote _walk(String symbol, int tick) {
    final double anchor = _anchors[symbol]!;
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
}
