/// Barrier options: knock-out and knock-in calls and puts (Phase 8).
///
/// Pure Dart with NO Flutter imports (CLAUDE.md architecture rule).
///
/// WHAT A BARRIER OPTION IS. An ordinary option only cares where the
/// underlying finishes. A barrier option also cares where it *went*. A
/// knock-out dies the moment the price touches a agreed level and pays
/// nothing thereafter, however favourably it finishes; a knock-in does not
/// exist until the price touches that level, and pays nothing if it never
/// does. Both are cheaper than the vanilla they are carved from, because both
/// are the vanilla minus something.
///
/// THE HONEST PART (CLAUDE.md rules 2 and 4). "Cheaper" is not "better".
/// A knock-out can be perfectly right about direction and still expire
/// worthless because the price dipped through the barrier on the way — a way
/// to lose 100% of the premium that a vanilla option does not have. The
/// discount is the market charging less for a smaller set of outcomes, not a
/// bargain.
///
/// ASSUMPTIONS (CLAUDE.md rule 5) — the closed form below inherits every
/// Black-Scholes-Merton assumption listed in `black_scholes.dart`, and adds:
/// - CONTINUOUS monitoring: the barrier is watched at every instant. Real
///   contracts are usually monitored at daily closes, which makes them worth
///   MORE than this formula says for a knock-out (fewer chances to die) and
///   LESS for a knock-in. `monte_carlo.dart` models discrete monitoring
///   directly and documents the gap.
/// - No rebate: a knocked-out option pays nothing at all. Contracts that
///   refund part of the premium exist and are not priced here.
///
/// REFERENCE. The closed form is the standard Reiner & Rubinstein (1991)
/// decomposition, also set out in Haug, "The Complete Guide to Option Pricing
/// Formulas", and in Hull. It is written here in the zero-rebate case only,
/// which removes two of the six terms.
library;

import 'dart:math' as math;

import 'black_scholes.dart';

/// Which side of the spot the barrier sits on.
enum BarrierDirection {
  /// Barrier below the current price; it is hit by falling.
  down,

  /// Barrier above the current price; it is hit by rising.
  up,
}

/// Whether touching the barrier kills the option or creates it.
enum BarrierStyle {
  /// Alive now, dead the moment the barrier is touched.
  knockOut,

  /// Worthless unless the barrier is touched, alive from then on.
  knockIn,
}

extension BarrierDirectionLabel on BarrierDirection {
  String get label => switch (this) {
    BarrierDirection.down => 'Down',
    BarrierDirection.up => 'Up',
  };
}

extension BarrierStyleLabel on BarrierStyle {
  String get label => switch (this) {
    BarrierStyle.knockOut => 'Knock-out',
    BarrierStyle.knockIn => 'Knock-in',
  };

  String get shortLabel => switch (this) {
    BarrierStyle.knockOut => 'KO',
    BarrierStyle.knockIn => 'KI',
  };
}

/// A barrier contract: a vanilla option plus a level that switches it on or
/// off.
class BarrierSpec {
  const BarrierSpec({
    required this.type,
    required this.direction,
    required this.style,
    required this.barrier,
  }) : assert(barrier > 0, 'barrier must be positive');

  final OptionType type;
  final BarrierDirection direction;
  final BarrierStyle style;

  /// The trigger level.
  final double barrier;

  /// True when [spot] is already on the far side of the barrier, so the
  /// trigger has effectively been hit before the contract starts.
  ///
  /// Not a hypothetical: the Sandbox lets a learner drag spot straight
  /// through the barrier, and the answer there ("this is already dead") is
  /// one of the more useful things a barrier option can teach.
  bool alreadyTriggered(double spot) => switch (direction) {
    BarrierDirection.down => spot <= barrier,
    BarrierDirection.up => spot >= barrier,
  };

  String get label =>
      '${direction.label}-and-${style == BarrierStyle.knockOut ? 'out' : 'in'} '
      '${type == OptionType.call ? 'call' : 'put'}';
}

/// Closed-form price of a barrier option under continuous monitoring.
///
/// Exact within the model, so it is both the fast path for the UI and the
/// reference the Monte Carlo engine is tested against.
double barrierPrice(BarrierSpec spec, BsmInputs inputs) {
  final double s = inputs.spot;
  final double k = inputs.strike;
  final double h = spec.barrier;
  final double r = inputs.rate;
  final double q = inputs.dividendYield;
  final double sigma = inputs.volatility;
  final double t = inputs.timeToExpiry;

  final double vanilla = bsmQuote(spec.type, inputs).price;

  // Already through the barrier at inception: no simulation or formula
  // needed, and the answer is the whole lesson. A knocked-out option is
  // simply gone; a knocked-in one has already become the vanilla.
  if (spec.alreadyTriggered(s)) {
    return spec.style == BarrierStyle.knockOut ? 0 : vanilla;
  }

  // Cost of carry: the drift of the underlying under the risk-neutral
  // measure, net of any dividend yield being paid away.
  final double b = r - q;
  final double sqrtT = math.sqrt(t);
  final double vol = sigma * sqrtT;
  final double sigma2 = sigma * sigma;

  // The Reiner-Rubinstein decomposition also carries a `lambda` term, but it
  // appears only in the two rebate blocks. This contract pays no rebate, so
  // both drop out and lambda is never needed.
  final double mu = (b - 0.5 * sigma2) / sigma2;

  final double x1 = math.log(s / k) / vol + (1 + mu) * vol;
  final double x2 = math.log(s / h) / vol + (1 + mu) * vol;
  final double y1 = math.log(h * h / (s * k)) / vol + (1 + mu) * vol;
  final double y2 = math.log(h / s) / vol + (1 + mu) * vol;

  // phi: +1 for a call, -1 for a put. eta: +1 for a down barrier, -1 for up.
  final double phi = spec.type == OptionType.call ? 1 : -1;
  final double eta = spec.direction == BarrierDirection.down ? 1 : -1;

  final double carry = math.exp((b - r) * t);
  final double discount = math.exp(-r * t);
  final double hOverS = h / s;
  final double powPlus = math.pow(hOverS, 2 * (mu + 1)).toDouble();
  final double powMu = math.pow(hOverS, 2 * mu).toDouble();

  // The four building blocks. A is the plain vanilla; the rest subtract or
  // reflect the paths that touch the barrier. Every knock-in / knock-out pair
  // below is built so that in + out adds back up to A, which is the identity
  // the tests lean on.
  final double termA =
      phi * s * carry * normalCdf(phi * x1) -
      phi * k * discount * normalCdf(phi * (x1 - vol));
  final double termB =
      phi * s * carry * normalCdf(phi * x2) -
      phi * k * discount * normalCdf(phi * (x2 - vol));
  final double termC =
      phi * s * carry * powPlus * normalCdf(eta * y1) -
      phi * k * discount * powMu * normalCdf(eta * (y1 - vol));
  final double termD =
      phi * s * carry * powPlus * normalCdf(eta * y2) -
      phi * k * discount * powMu * normalCdf(eta * (y2 - vol));

  final bool strikeAboveBarrier = k > h;
  final double knockIn = switch ((spec.type, spec.direction)) {
    (OptionType.call, BarrierDirection.down) =>
      strikeAboveBarrier ? termC : termA - termB + termD,
    (OptionType.call, BarrierDirection.up) =>
      strikeAboveBarrier ? termA : termB - termC + termD,
    (OptionType.put, BarrierDirection.down) =>
      strikeAboveBarrier ? termB - termC + termD : termA,
    (OptionType.put, BarrierDirection.up) =>
      strikeAboveBarrier ? termA - termB + termD : termC,
  };

  // IN-OUT PARITY. Owning both the knock-in and the knock-out of the same
  // contract leaves you owning the vanilla, whatever the price does: exactly
  // one of the two is alive at expiry. So the knock-out is worth the vanilla
  // minus the knock-in, and deriving it that way makes the identity exact in
  // arithmetic rather than merely true in theory.
  final double price = spec.style == BarrierStyle.knockIn
      ? knockIn
      : vanilla - knockIn;

  // Rounding in the normal CDF can leave a price a hair below zero when the
  // true value is a fraction of a cent. Showing "-0.00" would suggest the
  // model had produced a negative price, which it cannot.
  return price < 0 ? 0 : price;
}

/// The Broadie-Glasserman-Kou continuity correction (1997).
///
/// A barrier watched only at [monitoringDates] discrete times is easier to
/// survive than one watched continuously: the price can dip through the level
/// between two observations and be back on the safe side by the next one, and
/// nobody notices. Broadie, Glasserman & Kou showed that the two contracts
/// can be reconciled by shifting the barrier by a factor
///
///     exp(0.5826 * sigma * sqrt(T / m))
///
/// where 0.5826 is -zeta(1/2)/sqrt(2*pi) and m is the number of observations.
/// The magnitude is [_barrierShiftFactor]; WHICH WAY to shift depends on which
/// of the two questions is being asked, and getting that backwards doubles the
/// error instead of removing it — hence two separate, explicitly named
/// functions rather than one with a sign to remember.
double _barrierShiftFactor({
  required double volatility,
  required double timeToExpiry,
  required int monitoringDates,
}) {
  assert(monitoringDates > 0, 'need at least one observation');
  const double beta = 0.5826;
  return math.exp(
    beta * volatility * math.sqrt(timeToExpiry / monitoringDates),
  );
}

/// "I have a CONTINUOUS barrier at [barrier]; what discretely monitored
/// barrier behaves like it?"
///
/// The answer is FURTHER FROM the spot — a discrete barrier has to be set
/// harder to hit to be as dangerous as one watched every instant. Use this to
/// show a learner what "monitored daily" is really worth relative to the
/// idealised contract the textbook formula prices.
double discreteEquivalentBarrier(
  double barrier, {
  required BarrierDirection direction,
  required double volatility,
  required double timeToExpiry,
  required int monitoringDates,
}) {
  final double shift = _barrierShiftFactor(
    volatility: volatility,
    timeToExpiry: timeToExpiry,
    monitoringDates: monitoringDates,
  );
  return direction == BarrierDirection.down ? barrier / shift : barrier * shift;
}

/// "I can only simulate [monitoringDates] observations, but I want the price
/// of the CONTINUOUS contract; what barrier should I simulate against?"
///
/// The exact inverse of [discreteEquivalentBarrier]: the simulated barrier
/// moves TOWARDS the spot, so that being watched rarely at a nearer level is
/// as dangerous as being watched always at the real one. This is the
/// direction the Monte Carlo engine needs, and it is the one that is easy to
/// get backwards — shifting the wrong way makes the discretisation error
/// bigger, not smaller, while still looking like a correction.
double continuousEquivalentBarrier(
  double barrier, {
  required BarrierDirection direction,
  required double volatility,
  required double timeToExpiry,
  required int monitoringDates,
}) {
  final double shift = _barrierShiftFactor(
    volatility: volatility,
    timeToExpiry: timeToExpiry,
    monitoringDates: monitoringDates,
  );
  return direction == BarrierDirection.down ? barrier * shift : barrier / shift;
}
