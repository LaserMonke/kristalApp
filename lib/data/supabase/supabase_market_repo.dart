import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../local/local_market_repo.dart';
import '../market/symbol_index.dart';
import '../models/market.dart';
import '../repositories/market_repo.dart';

/// The real feed: delayed quotes fetched through the `market-data-proxy` Edge
/// Function. The paid Finnhub key lives only in that function's secret, never
/// here (CLAUDE.md rule 8).
///
/// If the function cannot be reached the repo falls back to [offline] — the
/// synthetic walk — so the practice market keeps working. Those quotes come
/// back flagged `synthetic`, and the UI relabels itself accordingly rather
/// than passing made-up numbers off as market data.
class SupabaseMarketRepo implements MarketRepo {
  const SupabaseMarketRepo({required this.client, required this.offline});

  final sb.SupabaseClient client;
  final LocalMarketRepo offline;

  static const String functionName = 'market-data-proxy';

  @override
  Future<List<Quote>> quotes(List<String> symbols) async {
    try {
      final sb.FunctionResponse response = await client.functions.invoke(
        functionName,
        body: <String, dynamic>{'symbols': symbols},
      );

      final Object? data = response.data;
      if (response.status != 200 || data is! Map) {
        return offline.quotes(symbols);
      }

      final Object? rows = data['quotes'];
      if (rows is! List) return offline.quotes(symbols);

      final List<Quote> quotes = <Quote>[
        for (final Object? row in rows)
          if (row is Map) _fromRow(row.cast<String, dynamic>()),
      ];
      // An empty answer (e.g. market closed and the provider returned nothing
      // usable) is better replaced by the visible-but-labelled walk than by a
      // blank screen.
      return quotes.isEmpty ? offline.quotes(symbols) : quotes;
    } catch (_) {
      return offline.quotes(symbols);
    }
  }

  /// Provider results merged with the bundled catalogue.
  ///
  /// The provider knows every listing but matches literally, so a misspelled
  /// name returns nothing at all. The catalogue is small but forgiving. Taking
  /// both means "coca cola" and "coca cloa" and "KO" all land on the same
  /// company, and an obscure ticker the catalogue has never heard of still
  /// resolves.
  ///
  /// Order: confident catalogue hits (the learner typed a name or ticker we
  /// recognise), then everything the provider returned, then the fuzzier
  /// catalogue guesses. A guess never sits above a literal match.
  @override
  Future<List<SymbolMatch>> search(String query) async {
    if (query.trim().isEmpty) return const <SymbolMatch>[];

    final List<ScoredCompany> catalog = searchCatalog(query);
    final List<SymbolMatch> confident = <SymbolMatch>[
      for (final ScoredCompany hit in catalog)
        if (hit.score >= 0.86)
          SymbolMatch(symbol: hit.company.symbol, description: hit.company.name),
    ];
    final List<SymbolMatch> guesses = <SymbolMatch>[
      for (final ScoredCompany hit in catalog)
        if (hit.score < 0.86)
          SymbolMatch(symbol: hit.company.symbol, description: hit.company.name),
    ];

    List<SymbolMatch> provider;
    try {
      provider = await _providerSearch(query);
    } catch (_) {
      provider = const <SymbolMatch>[];
    }

    final Set<String> seen = <String>{};
    final List<SymbolMatch> merged = <SymbolMatch>[
      for (final SymbolMatch m in <SymbolMatch>[
        ...confident,
        ...provider,
        ...guesses,
      ])
        if (seen.add(m.symbol)) m,
    ];

    // Nothing anywhere: fall back to the offline repo, which will still offer
    // a plausible ticker typed directly, labelled as not looked up.
    return merged.isEmpty ? offline.search(query) : merged;
  }

  Future<List<SymbolMatch>> _providerSearch(String query) async {
    final sb.FunctionResponse response = await client.functions.invoke(
      functionName,
      body: <String, dynamic>{'query': query.trim()},
    );

    final Object? data = response.data;
    if (response.status != 200 || data is! Map) return const <SymbolMatch>[];

    final Object? rows = data['matches'];
    if (rows is! List) return const <SymbolMatch>[];

    return <SymbolMatch>[
      for (final Object? row in rows)
        if (row is Map)
          SymbolMatch(
            symbol: (row['symbol'] as String).toUpperCase(),
            description: row['description'] as String? ?? '',
          ),
    ];
  }

  Quote _fromRow(Map<String, dynamic> row) => Quote(
    symbol: row['symbol'] as String,
    price: (row['price'] as num).toDouble(),
    change: (row['change'] as num?)?.toDouble() ?? 0,
    percentChange: (row['percentChange'] as num?)?.toDouble() ?? 0,
    delayed: row['delayed'] as bool? ?? true,
    synthetic: false,
  );
}
