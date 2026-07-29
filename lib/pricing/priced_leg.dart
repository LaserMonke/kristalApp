/// Bridges live Black-Scholes-Merton pricing ([black_scholes.dart]) with the
/// expiry payoff engine ([payoff.dart]), so the interactive pricer and the
/// strategy view (Phase 4) can build a [StrategyLeg] whose premium is
/// today's theoretical price rather than a number typed in by hand.
///
/// Pure Dart, no Flutter imports (CLAUDE.md architecture rule).
library;

import 'black_scholes.dart';
import 'payoff.dart';

/// The market conditions shared by every leg in a strategy: one underlying,
/// one volatility, one time to expiry, one risk-free rate.
///
/// Real multi-leg strategies can mix expiries (a calendar spread) or use a
/// different implied volatility per strike (a "volatility smile"); both are
/// out of scope here — CLAUDE.md Phase 4 asks for a single shared spot,
/// strike, volatility, time and rate.
class MarketEnvironment {
  const MarketEnvironment({
    required this.spot,
    required this.volatility,
    required this.timeToExpiry,
    required this.rate,
  }) : assert(spot > 0, 'spot must be positive'),
       assert(volatility > 0, 'volatility must be positive'),
       assert(timeToExpiry > 0, 'timeToExpiry must be positive');

  final double spot;
  final double volatility;
  final double timeToExpiry;
  final double rate;

  MarketEnvironment copyWith({
    double? spot,
    double? volatility,
    double? timeToExpiry,
    double? rate,
  }) => MarketEnvironment(
    spot: spot ?? this.spot,
    volatility: volatility ?? this.volatility,
    timeToExpiry: timeToExpiry ?? this.timeToExpiry,
    rate: rate ?? this.rate,
  );
}

/// Builds a [StrategyLeg] whose premium is the Black-Scholes-Merton price of
/// a call or put under [env], or the spot price itself for an underlying
/// (share) leg — matching how [StrategyLeg.premium] already treats a share
/// position's entry price in `payoff.dart`.
StrategyLeg pricedLeg(
  MarketEnvironment env, {
  required LegKind kind,
  required LegSide side,
  double strike = 0,
  double quantity = 1,
}) {
  if (kind == LegKind.underlying) {
    return StrategyLeg(
      kind: kind,
      side: side,
      premium: env.spot,
      quantity: quantity,
    );
  }

  final BsmInputs inputs = BsmInputs(
    spot: env.spot,
    strike: strike,
    rate: env.rate,
    volatility: env.volatility,
    timeToExpiry: env.timeToExpiry,
  );
  final double premium = bsmQuote(
    kind == LegKind.call ? OptionType.call : OptionType.put,
    inputs,
  ).price;

  return StrategyLeg(
    kind: kind,
    side: side,
    strike: strike,
    premium: premium,
    quantity: quantity,
  );
}
