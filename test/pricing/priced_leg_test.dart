import 'package:flutter_test/flutter_test.dart';
import 'package:optionsschool/pricing/black_scholes.dart';
import 'package:optionsschool/pricing/payoff.dart';
import 'package:optionsschool/pricing/priced_leg.dart';

void main() {
  const MarketEnvironment env = MarketEnvironment(
    spot: 42,
    volatility: 0.20,
    timeToExpiry: 0.5,
    rate: 0.10,
  );

  test('a priced call leg carries the Black-Scholes-Merton premium', () {
    final StrategyLeg leg = pricedLeg(
      env,
      kind: LegKind.call,
      side: LegSide.long,
      strike: 40,
    );
    final double expected = bsmQuote(
      OptionType.call,
      const BsmInputs(spot: 42, strike: 40, rate: 0.10, volatility: 0.20, timeToExpiry: 0.5),
    ).price;

    expect(leg.premium, expected);
    expect(leg.strike, 40);
    expect(leg.kind, LegKind.call);
  });

  test('a priced put leg carries the Black-Scholes-Merton premium', () {
    final StrategyLeg leg = pricedLeg(
      env,
      kind: LegKind.put,
      side: LegSide.short,
      strike: 45,
    );
    final double expected = bsmQuote(
      OptionType.put,
      const BsmInputs(spot: 42, strike: 45, rate: 0.10, volatility: 0.20, timeToExpiry: 0.5),
    ).price;

    expect(leg.premium, expected);
  });

  test('an underlying leg is entered at the current spot, not model priced', () {
    final StrategyLeg leg = pricedLeg(
      env,
      kind: LegKind.underlying,
      side: LegSide.long,
    );
    expect(leg.premium, env.spot);
  });

  test('a covered call combines cleanly through strategyProfit', () {
    final List<StrategyLeg> legs = <StrategyLeg>[
      pricedLeg(env, kind: LegKind.underlying, side: LegSide.long),
      pricedLeg(env, kind: LegKind.call, side: LegSide.short, strike: 45),
    ];
    // Below the strike the position just tracks the shares, offset by the
    // premium collected for the call — a basic sanity check that legs
    // compose rather than a fresh reference-value derivation.
    final double callPremium = legs[1].premium;
    expect(strategyProfit(legs, 42), closeTo(callPremium, 1e-9));
  });
}
