import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../pricing/black_scholes.dart';

/// The symbols a learner starts with. They can search for and add any other
/// ticker; this is only the opening list, not a limit.
const List<String> kDefaultWatchlist = <String>[
  'AAPL',
  'MSFT',
  'SPY',
  'TSLA',
  'NVDA',
];

/// How many symbols one learner may follow at once. A ceiling, not a
/// curation: each one is a quote fetched every poll, so an unbounded list
/// would hammer the data provider for no teaching benefit.
const int kMaxWatchlist = 20;

/// A ticker as typed or as returned by symbol search.
///
/// [description] is the company or fund name where the provider gives one, so
/// the learner can tell VOO from VOOG before trading it.
@immutable
class SymbolMatch {
  const SymbolMatch({required this.symbol, this.description = ''});

  final String symbol;
  final String description;

  @override
  bool operator ==(Object other) =>
      other is SymbolMatch &&
      other.symbol == symbol &&
      other.description == description;

  @override
  int get hashCode => Object.hash(symbol, description);
}

/// Whether [raw] could plausibly be a ticker, so obvious nonsense is rejected
/// before it costs a network round trip. Deliberately loose — exchanges use
/// dots and hyphens (BRK.B, RDS-A) — and never a judgement about whether the
/// symbol actually exists, which only the provider can answer.
bool isPlausibleSymbol(String raw) {
  final String s = raw.trim().toUpperCase();
  if (s.isEmpty || s.length > 10) return false;
  return RegExp(r'^[A-Z][A-Z0-9.\-]*$').hasMatch(s);
}

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
///
/// [contracts] is SIGNED. Positive means long (you bought and hold the right);
/// negative means short (you WROTE the option and carry the obligation). The
/// two are not mirror images of each other in risk terms: a long option can
/// lose at most the premium, while a written option's loss is bounded only by
/// how far the underlying moves — unbounded for a naked call (CLAUDE.md rule
/// 2). Every formula below works off the sign, so a short position marks to a
/// NEGATIVE value: it is a liability you would have to buy back.
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

  /// True when this position was written rather than bought.
  bool get isShort => contracts < 0;

  /// Contracts without the sign, for counting and for labels that state the
  /// direction in words instead.
  int get size => contracts.abs();

  /// A written call has no ceiling on what it can cost to buy back, because the
  /// underlying has no ceiling. Everything else has a worst case you can name.
  bool get hasUnboundedLoss => isShort && isCall;

  /// The worst case in cash terms, or null when there isn't one (naked call).
  /// A written put is worst at a spot of zero: you are obliged to buy at the
  /// strike something now worthless, less the premium you kept.
  double? worstCaseLoss() {
    if (!isShort) return costBasis().abs();
    if (isCall) return null;
    return (strike - premiumPaid) * size * kContractMultiplier;
  }

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

/// Simulated collateral one written contract ties up, in cash.
///
/// A simplified Reg-T-style naked requirement: 20% of the underlying less the
/// amount the option is out of the money, floored at 10% (of spot for a call,
/// of strike for a put), plus the premium taken in. Real brokers differ, charge
/// more for volatile names, and recompute it daily; this exists so writing
/// options costs something and cannot be done without limit, which is the
/// lesson. It is NOT a model of any particular broker's margin.
double shortMarginPerContract({
  required bool isCall,
  required double spot,
  required double strike,
  required double premium,
}) {
  final double outOfTheMoney = isCall
      ? math.max(strike - spot, 0.0)
      : math.max(spot - strike, 0.0);
  final double standard = 0.20 * spot - outOfTheMoney + premium;
  final double floor = (isCall ? 0.10 * spot : 0.10 * strike) + premium;
  return math.max(math.max(standard, floor), 0.0) * kContractMultiplier;
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

  /// Cash locked up as collateral against written options. It is not spendable
  /// while the position is open, which is the point: writing options is not
  /// free money, however much the premium landing in cash looks like it.
  double marginHeld(Map<String, double> prices, DateTime now) {
    double held = 0;
    for (final OptionHolding o in options) {
      if (!o.isShort) continue;
      final double? spot = prices[o.symbol];
      if (spot == null) continue;
      held +=
          shortMarginPerContract(
            isCall: o.isCall,
            spot: spot,
            strike: o.strike,
            premium: optionMarkPrice(o, spot, now),
          ) *
          o.size;
    }
    return held;
  }

  /// What is actually available to spend or to post against a new short.
  double buyingPower(Map<String, double> prices, DateTime now) =>
      cash - marginHeld(prices, now);

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
