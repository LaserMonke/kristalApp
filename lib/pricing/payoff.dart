/// Expiry payoff and profit maths for options and multi-leg strategies.
///
/// Pure Dart with NO Flutter imports (CLAUDE.md architecture rule), so it is
/// directly unit-testable and reusable by the lesson diagrams, the interactive
/// pricer (Phase 4) and the practice market (Phase 9).
///
/// SCOPE: value **at expiry** only. At expiry there is no time left, so an
/// option is worth exactly its intrinsic value — which is why payoff diagrams
/// can be taught honestly before Black–Scholes appears in Phase 3. Everything
/// here is deterministic arithmetic; nothing in this file models the price of
/// an option *before* expiry.
///
/// Simplifications (state these wherever output is shown):
/// European exercise, no dividends, no fees or bid/ask spread, no early
/// assignment, and a contract size of 1 unit per leg.
library;

/// How a leg is exposed to the underlying.
enum LegKind {
  /// Right to buy the underlying at [StrategyLeg.strike].
  call,

  /// Right to sell the underlying at [StrategyLeg.strike].
  put,

  /// The underlying itself (e.g. a share position), used to build covered
  /// calls and protective puts.
  underlying,
}

/// Which side of the contract this leg is on.
///
/// A long leg pays the premium and holds the choice; a short leg receives the
/// premium and carries the obligation.
enum LegSide { long, short }

/// One position in a strategy.
class StrategyLeg {
  const StrategyLeg({
    required this.kind,
    required this.side,
    this.strike = 0,
    this.premium = 0,
    this.quantity = 1,
  }) : assert(quantity > 0, 'quantity is a size — use side for direction'),
       assert(
         kind == LegKind.underlying || strike > 0,
         'options need a positive strike',
       );

  final LegKind kind;
  final LegSide side;

  /// Exercise price. Unused when [kind] is [LegKind.underlying].
  final double strike;

  /// Price paid (long) or received (short) per unit. For an underlying leg
  /// this is the entry price of the share.
  final double premium;

  final double quantity;

  bool get isLong => side == LegSide.long;

  /// A leg with one or more terms changed — used by the interactive lesson
  /// cards, where a learner drags a strike or premium and the curve redraws.
  StrategyLeg copyWith({
    LegKind? kind,
    LegSide? side,
    double? strike,
    double? premium,
    double? quantity,
  }) => StrategyLeg(
    kind: kind ?? this.kind,
    side: side ?? this.side,
    strike: strike ?? this.strike,
    premium: premium ?? this.premium,
    quantity: quantity ?? this.quantity,
  );

  /// What the contract is worth at expiry, before considering what it cost.
  ///
  /// A call is worth the amount the underlying finished above the strike; a
  /// put, the amount it finished below. Neither can be negative — the holder
  /// simply walks away, which is the whole point of an option.
  double valueAtExpiry(double spot) => switch (kind) {
    LegKind.call => spot > strike ? spot - strike : 0,
    LegKind.put => strike > spot ? strike - spot : 0,
    LegKind.underlying => spot,
  };

  /// Profit or loss at expiry, net of the premium paid or received.
  double profitAtExpiry(double spot) {
    final double value = valueAtExpiry(spot);
    final double net = isLong ? value - premium : premium - value;
    return net * quantity;
  }
}

/// A sampled point on a payoff curve.
class PayoffPoint {
  const PayoffPoint(this.spot, this.profit);

  final double spot;
  final double profit;
}

/// Combined profit of every leg at one underlying price.
double strategyProfit(List<StrategyLeg> legs, double spot) =>
    legs.fold<double>(0, (double sum, StrategyLeg leg) {
      return sum + leg.profitAtExpiry(spot);
    });

/// The net cost of opening the position: positive means cash paid out.
double netPremium(List<StrategyLeg> legs) =>
    legs.fold<double>(0, (double sum, StrategyLeg leg) {
      final double cash = leg.premium * leg.quantity;
      return sum + (leg.isLong ? cash : -cash);
    });

/// Samples the profit curve across `[spotMin, spotMax]`.
///
/// Strikes inside the range are always sampled exactly so the kinks stay sharp
/// instead of being rounded off by an unlucky grid.
List<PayoffPoint> profitCurve(
  List<StrategyLeg> legs, {
  required double spotMin,
  required double spotMax,
  int samples = 160,
}) {
  assert(spotMax > spotMin, 'spotMax must exceed spotMin');
  assert(samples >= 2, 'need at least the two endpoints');

  final Set<double> xs = <double>{};
  final double step = (spotMax - spotMin) / (samples - 1);
  for (int i = 0; i < samples; i++) {
    xs.add(spotMin + step * i);
  }
  for (final double strike in _strikesWithin(legs, spotMin, spotMax)) {
    xs.add(strike);
  }

  final List<double> sorted = xs.toList()..sort();
  return <PayoffPoint>[
    for (final double spot in sorted) PayoffPoint(spot, strategyProfit(legs, spot)),
  ];
}

/// Underlying prices where the position breaks even.
///
/// Profit at expiry is piecewise linear with kinks only at strikes, so each
/// segment between consecutive strikes can be solved exactly rather than
/// searched numerically.
List<double> breakEvens(
  List<StrategyLeg> legs, {
  required double spotMin,
  required double spotMax,
}) {
  final List<double> knots = <double>{
    spotMin,
    ..._strikesWithin(legs, spotMin, spotMax),
    spotMax,
  }.toList()..sort();

  final List<double> found = <double>[];
  for (int i = 0; i < knots.length - 1; i++) {
    final double a = knots[i];
    final double b = knots[i + 1];
    final double fa = strategyProfit(legs, a);
    final double fb = strategyProfit(legs, b);

    if (fa.abs() < _epsilon) {
      _addUnique(found, a);
    }
    // A sign change inside the segment: the line crosses zero exactly once.
    if (fa.abs() >= _epsilon && fb.abs() >= _epsilon && fa.sign != fb.sign) {
      _addUnique(found, a + (b - a) * (fa.abs() / (fa.abs() + fb.abs())));
    }
  }
  if (strategyProfit(legs, spotMax).abs() < _epsilon) {
    _addUnique(found, spotMax);
  }
  return found;
}

/// Slope of the profit line above every strike.
///
/// Negative means losses keep growing as the underlying rises with no upper
/// bound — the defining risk of a naked short call, and something the UI must
/// say out loud (CLAUDE.md rule 2).
double upperSlope(List<StrategyLeg> legs) {
  final double far = _highestStrike(legs) + 10;
  return strategyProfit(legs, far + 1) - strategyProfit(legs, far);
}

/// Slope of the profit line below every strike, walking left.
///
/// The underlying cannot fall below zero, so downside loss is always bounded,
/// but it can still be many multiples of the premium received.
double lowerSlope(List<StrategyLeg> legs) {
  final double near = _lowestStrike(legs) / 2;
  return strategyProfit(legs, near) - strategyProfit(legs, near + 1);
}

/// True when a rising underlying produces losses without a fixed limit.
bool hasUnboundedUpsideLoss(List<StrategyLeg> legs) => upperSlope(legs) < -_epsilon;

/// Worst profit (i.e. largest loss) observed across the sampled range.
///
/// This is a range-bound figure for labelling a chart — it is NOT the worst
/// case of the position, which for some strategies has no finite bound.
double worstProfitInRange(
  List<StrategyLeg> legs, {
  required double spotMin,
  required double spotMax,
}) {
  return profitCurve(legs, spotMin: spotMin, spotMax: spotMax)
      .map((PayoffPoint p) => p.profit)
      .reduce((double a, double b) => a < b ? a : b);
}

const double _epsilon = 1e-9;

Iterable<double> _strikesWithin(
  List<StrategyLeg> legs,
  double spotMin,
  double spotMax,
) => legs
    .where((StrategyLeg leg) => leg.kind != LegKind.underlying)
    .map((StrategyLeg leg) => leg.strike)
    .where((double strike) => strike > spotMin && strike < spotMax);

double _highestStrike(List<StrategyLeg> legs) {
  final Iterable<double> strikes = legs
      .where((StrategyLeg leg) => leg.kind != LegKind.underlying)
      .map((StrategyLeg leg) => leg.strike);
  return strikes.isEmpty ? 100 : strikes.reduce((double a, double b) => a > b ? a : b);
}

double _lowestStrike(List<StrategyLeg> legs) {
  final Iterable<double> strikes = legs
      .where((StrategyLeg leg) => leg.kind != LegKind.underlying)
      .map((StrategyLeg leg) => leg.strike);
  return strikes.isEmpty ? 100 : strikes.reduce((double a, double b) => a < b ? a : b);
}

void _addUnique(List<double> into, double value) {
  final bool seen = into.any((double x) => (x - value).abs() < 1e-6);
  if (!seen) into.add(value);
}
