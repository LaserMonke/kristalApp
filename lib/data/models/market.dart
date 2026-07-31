import 'package:flutter/foundation.dart';

import '../../pricing/black_scholes.dart';

/// The symbols the practice market follows. Must stay within the Edge
/// Function's allow-list (`supabase/functions/market-data-proxy`).
const List<String> kWatchlist = <String>[
  'AAPL',
  'MSFT',
  'SPY',
  'TSLA',
  'NVDA',
];

/// A single price snapshot.
///
/// [delayed] and [synthetic] together decide the label the UI must show
/// (CLAUDE.md rules 4 & 8): real-but-delayed data, or made-up prices for the
/// offline simulation. Neither is ever presented as a live tradable quote.
@immutable
class Quote {
  const Quote({
    required this.symbol,
    required this.price,
    required this.change,
    required this.percentChange,
    this.delayed = true,
    this.synthetic = false,
  });

  final String symbol;
  final double price;
  final double change;
  final double percentChange;

  /// Real data, but not real-time.
  final bool delayed;

  /// Not real data at all — the offline random-walk stand-in.
  final bool synthetic;
}

/// One fake-money position: [shares] of [symbol] bought at an average
/// [avgCost]. Shares only for now; option contracts are a later increment.
@immutable
class Holding {
  const Holding({
    required this.symbol,
    required this.shares,
    required this.avgCost,
  });

  final String symbol;
  final int shares;
  final double avgCost;

  double costBasis() => shares * avgCost;
  double marketValue(double price) => shares * price;
  double unrealised(double price) => (price - avgCost) * shares;

  Holding copyWith({int? shares, double? avgCost}) => Holding(
    symbol: symbol,
    shares: shares ?? this.shares,
    avgCost: avgCost ?? this.avgCost,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'symbol': symbol,
    'shares': shares,
    'avg_cost': avgCost,
  };

  factory Holding.fromJson(Map<String, dynamic> json) => Holding(
    symbol: json['symbol'] as String,
    shares: (json['shares'] as num).toInt(),
    avgCost: (json['avg_cost'] as num).toDouble(),
  );
}

/// Fixed model assumptions for marking option positions. Crude on purpose —
/// one flat volatility and rate, no smile — and labelled as such in the UI
/// (CLAUDE.md rules 4 & 5). Real option marks would fit a surface.
const double kPracticeVolatility = 0.30;
const double kPracticeRate = 0.04;

/// One option contract controls this many shares.
const int kContractMultiplier = 100;

/// One fake-money option position: [contracts] of a call or put on [symbol].
/// [premiumPaid] is the average premium PER SHARE; a contract costs that times
/// [kContractMultiplier].
@immutable
class OptionHolding {
  const OptionHolding({
    required this.symbol,
    required this.isCall,
    required this.strike,
    required this.expiry,
    required this.contracts,
    required this.premiumPaid,
  });

  final String symbol;
  final bool isCall;
  final double strike;
  final DateTime expiry;
  final int contracts;
  final double premiumPaid;

  /// Stable identity, so buying the same contract twice merges rather than
  /// stacking two rows.
  String get key =>
      '$symbol|${isCall ? 'C' : 'P'}|${strike.toStringAsFixed(2)}|'
      '${expiry.toIso8601String()}';

  String get label =>
      '$symbol ${strike.toStringAsFixed(0)} ${isCall ? 'Call' : 'Put'}';

  double costBasis() => premiumPaid * contracts * kContractMultiplier;
  double marketValue(double markPerShare) =>
      markPerShare * contracts * kContractMultiplier;
  double unrealised(double markPerShare) =>
      (markPerShare - premiumPaid) * contracts * kContractMultiplier;

  OptionHolding copyWith({int? contracts, double? premiumPaid}) =>
      OptionHolding(
        symbol: symbol,
        isCall: isCall,
        strike: strike,
        expiry: expiry,
        contracts: contracts ?? this.contracts,
        premiumPaid: premiumPaid ?? this.premiumPaid,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'symbol': symbol,
    'is_call': isCall,
    'strike': strike,
    'expiry': expiry.toIso8601String(),
    'contracts': contracts,
    'premium_paid': premiumPaid,
  };

  factory OptionHolding.fromJson(Map<String, dynamic> json) => OptionHolding(
    symbol: json['symbol'] as String,
    isCall: json['is_call'] as bool,
    strike: (json['strike'] as num).toDouble(),
    expiry: DateTime.parse(json['expiry'] as String),
    contracts: (json['contracts'] as num).toInt(),
    premiumPaid: (json['premium_paid'] as num).toDouble(),
  );
}

/// The model price PER SHARE of [h], marked at [spot] as of [now]. After expiry
/// it is worth only its intrinsic value — the model no longer applies.
double optionMarkPrice(OptionHolding h, double spot, DateTime now) {
  final double years =
      h.expiry.difference(now).inSeconds / (365.25 * 24 * 3600);
  if (years <= 0) {
    final double intrinsic = h.isCall ? spot - h.strike : h.strike - spot;
    return intrinsic > 0 ? intrinsic : 0;
  }
  return bsmQuote(
    h.isCall ? OptionType.call : OptionType.put,
    BsmInputs(
      spot: spot,
      strike: h.strike,
      rate: kPracticeRate,
      volatility: kPracticeVolatility,
      timeToExpiry: years,
    ),
  ).price;
}

/// The fake-money account: simulated [cash] plus [holdings] (shares) and
/// [options]. [startingCash] is kept so total return can be shown honestly
/// against where the learner began.
@immutable
class Portfolio {
  const Portfolio({
    required this.cash,
    required this.holdings,
    required this.options,
    required this.startingCash,
  });

  static const double defaultStartingCash = 100000;

  const Portfolio.fresh()
    : cash = defaultStartingCash,
      holdings = const <Holding>[],
      options = const <OptionHolding>[],
      startingCash = defaultStartingCash;

  final double cash;
  final List<Holding> holdings;
  final List<OptionHolding> options;
  final double startingCash;

  Holding? holdingFor(String symbol) {
    for (final Holding h in holdings) {
      if (h.symbol == symbol) return h;
    }
    return null;
  }

  OptionHolding? optionFor(String key) {
    for (final OptionHolding o in options) {
      if (o.key == key) return o;
    }
    return null;
  }

  /// Cash plus every position marked at the latest price we have; [now] decays
  /// option time value.
  double equity(Map<String, double> prices, DateTime now) {
    double total = cash;
    for (final Holding h in holdings) {
      total += h.marketValue(prices[h.symbol] ?? h.avgCost);
    }
    for (final OptionHolding o in options) {
      final double? spot = prices[o.symbol];
      total += spot == null
          ? o.costBasis()
          : o.marketValue(optionMarkPrice(o, spot, now));
    }
    return total;
  }

  double totalReturn(Map<String, double> prices, DateTime now) =>
      equity(prices, now) - startingCash;

  Portfolio copyWith({
    double? cash,
    List<Holding>? holdings,
    List<OptionHolding>? options,
  }) => Portfolio(
    cash: cash ?? this.cash,
    holdings: holdings ?? this.holdings,
    options: options ?? this.options,
    startingCash: startingCash,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'cash': cash,
    'starting_cash': startingCash,
    'holdings': <Map<String, dynamic>>[
      for (final Holding h in holdings) h.toJson(),
    ],
    'options': <Map<String, dynamic>>[
      for (final OptionHolding o in options) o.toJson(),
    ],
  };

  factory Portfolio.fromJson(Map<String, dynamic> json) => Portfolio(
    cash: (json['cash'] as num).toDouble(),
    startingCash: (json['starting_cash'] as num?)?.toDouble() ??
        defaultStartingCash,
    holdings: <Holding>[
      for (final Object? h in (json['holdings'] as List<Object?>? ?? <Object?>[]))
        Holding.fromJson((h as Map).cast<String, dynamic>()),
    ],
    options: <OptionHolding>[
      for (final Object? o in (json['options'] as List<Object?>? ?? <Object?>[]))
        OptionHolding.fromJson((o as Map).cast<String, dynamic>()),
    ],
  );
}
