import 'package:flutter_test/flutter_test.dart';
import 'package:optionsschool/pricing/payoff.dart';

/// Reference values are worked out by hand from the definition of intrinsic
/// value at expiry — max(S - K, 0) for a call, max(K - S, 0) for a put — net of
/// the premium. No model is involved, so these are exact, not approximations.
void main() {
  group('long call, strike 100, premium 5', () {
    const StrategyLeg leg = StrategyLeg(
      kind: LegKind.call,
      side: LegSide.long,
      strike: 100,
      premium: 5,
    );
    const List<StrategyLeg> legs = <StrategyLeg>[leg];

    test('is not exercised below the strike, losing only the premium', () {
      expect(leg.valueAtExpiry(90), 0);
      expect(strategyProfit(legs, 90), -5);
      expect(strategyProfit(legs, 100), -5);
    });

    test('tracks the underlying one-for-one above the strike', () {
      expect(leg.valueAtExpiry(120), 20);
      expect(strategyProfit(legs, 120), 15);
    });

    test('breaks even at strike plus premium, not at the strike', () {
      expect(breakEvens(legs, spotMin: 60, spotMax: 140), <double>[105]);
      expect(strategyProfit(legs, 102), -3);
    });

    test('cost of the position is the premium paid', () {
      expect(netPremium(legs), 5);
    });
  });

  group('long put, strike 100, premium 6', () {
    const List<StrategyLeg> legs = <StrategyLeg>[
      StrategyLeg(
        kind: LegKind.put,
        side: LegSide.long,
        strike: 100,
        premium: 6,
      ),
    ];

    test('mirrors the call: gains as the underlying falls', () {
      expect(strategyProfit(legs, 120), -6);
      expect(strategyProfit(legs, 60), 34);
    });

    test('breaks even at strike minus premium', () {
      expect(breakEvens(legs, spotMin: 40, spotMax: 140), <double>[94]);
    });

    test('gain is bounded because the underlying cannot go below zero', () {
      expect(strategyProfit(legs, 0), 94);
    });
  });

  group('short call — the unbounded case CLAUDE.md requires us to state', () {
    const List<StrategyLeg> legs = <StrategyLeg>[
      StrategyLeg(
        kind: LegKind.call,
        side: LegSide.short,
        strike: 100,
        premium: 5,
      ),
    ];

    test('profit is capped at the premium received', () {
      expect(strategyProfit(legs, 80), 5);
      expect(strategyProfit(legs, 100), 5);
    });

    test('loss keeps growing with no upper bound', () {
      expect(strategyProfit(legs, 130), -25);
      expect(strategyProfit(legs, 1000), -895);
      expect(upperSlope(legs), -1);
      expect(hasUnboundedUpsideLoss(legs), isTrue);
    });

    test('the premium received is a cash inflow', () {
      expect(netPremium(legs), -5);
    });
  });

  group('protective put — shares at 100, put struck at 95 for 4', () {
    const List<StrategyLeg> legs = <StrategyLeg>[
      StrategyLeg(
        kind: LegKind.underlying,
        side: LegSide.long,
        premium: 100,
      ),
      StrategyLeg(
        kind: LegKind.put,
        side: LegSide.long,
        strike: 95,
        premium: 4,
      ),
    ];

    test('loss stops at the strike, floored at 9 per share', () {
      expect(strategyProfit(legs, 95), -9);
      expect(strategyProfit(legs, 60), -9);
      expect(strategyProfit(legs, 0), -9);
    });

    test('upside is the share gain less the premium paid for protection', () {
      expect(strategyProfit(legs, 140), 36);
      expect(breakEvens(legs, spotMin: 60, spotMax: 140), <double>[104]);
    });

    test('the downside is capped, so nothing is unbounded here', () {
      expect(hasUnboundedUpsideLoss(legs), isFalse);
      expect(worstProfitInRange(legs, spotMin: 60, spotMax: 140), -9);
    });
  });

  group('curve sampling', () {
    const List<StrategyLeg> legs = <StrategyLeg>[
      StrategyLeg(
        kind: LegKind.put,
        side: LegSide.long,
        strike: 95,
        premium: 4,
      ),
    ];

    test('samples the strike exactly so the kink stays sharp', () {
      final List<PayoffPoint> curve = profitCurve(
        legs,
        spotMin: 60,
        spotMax: 140,
        samples: 5,
      );
      expect(curve.any((PayoffPoint p) => p.spot == 95), isTrue);
    });

    test('is sorted and spans the requested range', () {
      final List<PayoffPoint> curve = profitCurve(
        legs,
        spotMin: 60,
        spotMax: 140,
      );
      expect(curve.first.spot, 60);
      expect(curve.last.spot, 140);
      for (int i = 1; i < curve.length; i++) {
        expect(curve[i].spot, greaterThan(curve[i - 1].spot));
      }
    });
  });
}
