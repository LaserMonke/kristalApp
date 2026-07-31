import '../models/market.dart';

/// Reads delayed quotes for the practice market. The real implementation goes
/// through the `market-data-proxy` Edge Function so the paid Finnhub key never
/// ships in the app (CLAUDE.md rule 8); the local implementation makes up
/// prices for offline use and flags them as synthetic.
abstract interface class MarketRepo {
  /// Latest quote per requested symbol. Order is not guaranteed; match on
  /// [Quote.symbol].
  Future<List<Quote>> quotes(List<String> symbols);
}

class MarketException implements Exception {
  const MarketException(this.message);
  final String message;

  @override
  String toString() => 'MarketException: $message';
}
