/// The Heston (1993) stochastic volatility model.
///
/// Pure Dart with NO Flutter imports (CLAUDE.md architecture rule).
///
/// WHAT PROBLEM IT SOLVES. Black-Scholes-Merton assumes volatility is a
/// constant you can look up. Markets say otherwise: options on the same
/// underlying, on the same day, at different strikes, imply DIFFERENT
/// volatilities — the "volatility smile". Under Black-Scholes that is a
/// contradiction, because the model has only one volatility to give. Heston
/// resolves it by letting volatility be a second random process with its own
/// motion, correlated with the share price:
///
///     dS = (r - q) S dt + sqrt(v) S dW1
///     dv = kappa (theta - v) dt + xi sqrt(v) dW2,   corr(dW1, dW2) = rho
///
/// Variance v is pulled back towards a long-run level theta at speed kappa,
/// jostled by its own volatility xi, and — crucially — its shocks are
/// correlated with the price's. A negative rho reproduces what equity markets
/// actually show: prices fall and volatility spikes at the same time, which
/// fattens the left tail and makes downside puts dearer than Black-Scholes
/// says. That single parameter is the difference between a model that says
/// crashes are unimaginable and one that prices them.
///
/// HONESTY (CLAUDE.md rules 4 and 5). Heston is still a model, and a more
/// elaborate model is not a more truthful one — it is a model with more
/// parameters to get wrong. It assumes volatility moves diffusively with no
/// jumps, that kappa, theta, xi and rho are constants, and that they can be
/// pinned down from market prices at all (in practice several combinations
/// fit almost equally well). It shares every frictionless-market assumption
/// with Black-Scholes. Fitting a smile is not the same as predicting one.
///
/// TWO WAYS TO PRICE, and both are here because the pair is the lesson:
/// [hestonVanillaPrice] recovers European calls and puts semi-analytically by
/// Fourier inversion — fast and essentially exact. [hestonMonteCarloPrice]
/// simulates, which is slower and only approximate, but is the only route
/// open for the path-dependent payoffs in `monte_carlo.dart`. Agreement
/// between them on the vanillas is what licenses trusting the simulation on
/// everything else.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'black_scholes.dart';
import 'complex.dart';
import 'monte_carlo.dart';
import 'quadrature.dart';
import 'random.dart';

/// The five parameters that define a Heston world.
class HestonParams {
  const HestonParams({
    required this.initialVariance,
    required this.longRunVariance,
    required this.meanReversion,
    required this.volOfVol,
    required this.correlation,
  }) : assert(initialVariance >= 0, 'variance cannot be negative'),
       assert(longRunVariance >= 0, 'variance cannot be negative'),
       assert(meanReversion > 0, 'mean reversion must be positive'),
       assert(volOfVol > 0, 'vol-of-vol must be positive'),
       assert(
         correlation >= -1 && correlation <= 1,
         'correlation must lie in [-1, 1]',
       );

  /// v0 — variance TODAY, not volatility. A 20% volatility is a variance of
  /// 0.04. The distinction matters constantly here and is the easiest thing
  /// in the whole model to get wrong.
  final double initialVariance;

  /// theta — the level variance is pulled towards over time.
  final double longRunVariance;

  /// kappa — how fast that pull acts. A kappa of 2 halves the gap to theta in
  /// roughly four months; a kappa of 0.5 takes well over a year.
  final double meanReversion;

  /// xi — the volatility OF volatility. Larger values fatten both tails and
  /// lift the wings of the smile.
  ///
  /// Sending it towards zero SHOULD collapse the model back to
  /// Black-Scholes, and mathematically it does. Numerically it does not:
  /// [hestonCharacteristicFunction] multiplies a term by `kappa*theta/xi^2`,
  /// which explodes as xi shrinks and amplifies the cancellation in the small
  /// difference it multiplies. Below roughly [minimumUsableVolOfVol] the
  /// semi-analytic price loses accuracy and then becomes nonsense — at
  /// xi = 1e-6 it is out by whole units of currency, which is a rounding
  /// artefact and not a statement about options.
  ///
  /// So the limit is real but must be approached from a sensible distance,
  /// and any UI slider should stop at [minimumUsableVolOfVol] rather than
  /// running to zero. Flagged here rather than silently clamped, because a
  /// pricer that quietly substitutes a different parameter for the one it was
  /// given is worse than one that is honest about its range.
  final double volOfVol;

  /// The smallest vol-of-vol at which [hestonVanillaPrice] stays accurate.
  ///
  /// Determined empirically: the error against Black-Scholes in the
  /// degenerate case bottoms out near 3e-4 around here, rises to ~0.1 at
  /// xi = 1e-3, and reaches ~10 at xi = 1e-6.
  static const double minimumUsableVolOfVol = 0.01;

  /// rho — correlation between the price's shocks and variance's shocks.
  /// Typically NEGATIVE for equities (around -0.5 to -0.8): prices fall as
  /// volatility rises. This is what tilts the smile into the downward "skew"
  /// equity markets actually display, making crash protection expensive.
  final double correlation;

  /// Today's volatility, as a percentage-style figure people can reason about.
  double get initialVolatility => math.sqrt(initialVariance);

  /// The long-run volatility variance is pulled towards.
  double get longRunVolatility => math.sqrt(longRunVariance);

  /// The Feller condition: `2 * kappa * theta > xi^2`.
  ///
  /// When it holds, variance is pulled up hard enough that it never reaches
  /// zero. When it fails, variance can touch zero — which is not a modelling
  /// error (the model is still well defined and market fits routinely violate
  /// it) but IS a warning that simulation will need care, since a scheme that
  /// takes the square root of a negative variance produces nonsense. The UI
  /// should say when a chosen parameter set is on the wrong side of it.
  bool get satisfiesFeller =>
      2 * meanReversion * longRunVariance > volOfVol * volOfVol;

  HestonParams copyWith({
    double? initialVariance,
    double? longRunVariance,
    double? meanReversion,
    double? volOfVol,
    double? correlation,
  }) => HestonParams(
    initialVariance: initialVariance ?? this.initialVariance,
    longRunVariance: longRunVariance ?? this.longRunVariance,
    meanReversion: meanReversion ?? this.meanReversion,
    volOfVol: volOfVol ?? this.volOfVol,
    correlation: correlation ?? this.correlation,
  );

  /// A starting point with the shape equity markets tend to show: variance
  /// near a 25% volatility, moderate mean reversion, and a pronounced
  /// negative correlation.
  static const HestonParams equityLike = HestonParams(
    initialVariance: 0.0625,
    longRunVariance: 0.0625,
    meanReversion: 2.0,
    volOfVol: 0.5,
    correlation: -0.7,
  );
}

/// The characteristic function of `ln(S_T)` under the risk-neutral measure.
///
/// This is the whole model in one expression: everything Heston knows about
/// where the price might end up is encoded here, and the price of any
/// European payoff can be integrated back out of it.
///
/// Written in the ALBRECHER ET AL. (2007) form — the so-called "Little Heston
/// Trap". Heston's original 1993 paper writes the same function with the
/// reciprocal of `g` below, which is algebraically identical but numerically
/// treacherous: the complex logarithm inside it crosses its branch cut for
/// longer maturities, and the price jumps discontinuously as a result. Prices
/// that are correct at six months and visibly wrong at two years are the
/// classic symptom. This formulation stays on the principal branch, so the
/// plain principal logarithm in `complex.dart` is safe.
Complex hestonCharacteristicFunction(
  Complex u, {
  required HestonParams params,
  required double spot,
  required double rate,
  required double dividendYield,
  required double timeToExpiry,
}) {
  final double kappa = params.meanReversion;
  final double theta = params.longRunVariance;
  final double xi = params.volOfVol;
  final double rho = params.correlation;
  final double v0 = params.initialVariance;
  final double t = timeToExpiry;
  final double xi2 = xi * xi;

  final Complex iu = Complex.i * u;

  // d = sqrt( (rho*xi*i*u - kappa)^2 + xi^2 * (i*u + u^2) )
  final Complex rhoXiIu = iu.scale(rho * xi);
  final Complex base = rhoXiIu - Complex.real(kappa);
  final Complex d = (base * base + (iu + u * u).scale(xi2)).sqrt;

  // g = (kappa - rho*xi*i*u - d) / (kappa - rho*xi*i*u + d)
  final Complex kappaMinus = Complex.real(kappa) - rhoXiIu;
  final Complex g = (kappaMinus - d) / (kappaMinus + d);

  final Complex expMinusDt = (-d).scale(t).exp;

  // C: the deterministic part, driven by the long-run variance level.
  final Complex logTerm =
      ((Complex.one - g * expMinusDt) / (Complex.one - g)).log;
  final Complex c =
      iu.scale((rate - dividendYield) * t) +
      ((kappaMinus - d).scale(t) - logTerm.scale(2)).scale(
        kappa * theta / xi2,
      );

  // D: the part that today's variance multiplies.
  final Complex dTerm =
      ((kappaMinus - d) / Complex.real(xi2)) *
      ((Complex.one - expMinusDt) / (Complex.one - g * expMinusDt));

  return (c + dTerm.scale(v0) + iu.scale(math.log(spot))).exp;
}

/// Prices a European call or put under Heston, semi-analytically.
///
/// Uses Heston's original two-probability decomposition,
///
///     call = S e^(-qT) P1 - K e^(-rT) P2
///
/// where P2 is the risk-neutral probability of finishing in the money and P1
/// is the same probability under the measure that uses the share itself as
/// numeraire. Both are recovered by integrating the characteristic function,
/// which is what [points] and [upperLimit] control.
///
/// The put comes from put-call parity rather than a second integration: the
/// parity relation is exact, so deriving it that way makes call and put
/// consistent to the last decimal instead of merely to quadrature accuracy.
double hestonVanillaPrice(
  OptionType type, {
  required HestonParams params,
  required double spot,
  required double strike,
  required double rate,
  required double timeToExpiry,
  double dividendYield = 0,
  int points = 128,
  double upperLimit = 200,
}) {
  assert(spot > 0, 'spot must be positive');
  assert(strike > 0, 'strike must be positive');
  assert(timeToExpiry > 0, 'timeToExpiry must be positive');

  final double logStrike = math.log(strike);

  Complex cf(Complex u) => hestonCharacteristicFunction(
    u,
    params: params,
    spot: spot,
    rate: rate,
    dividendYield: dividendYield,
    timeToExpiry: timeToExpiry,
  );

  // phi(-i) = E[S_T] = the forward price. Dividing by it re-weights the
  // characteristic function into the share-numeraire measure that gives P1.
  final Complex forward = cf(Complex(0, -1));

  double integrand(double u, {required bool shareMeasure}) {
    final Complex z = Complex.real(u);
    final Complex numerator = shareMeasure
        ? cf(z - Complex.i) / forward
        : cf(z);
    final Complex value =
        (Complex.imaginary(-u * logStrike).exp * numerator) / (Complex.i * z);
    // Rounding can push the tail of the integrand to a non-finite value long
    // after it has stopped contributing anything; treating that as zero is
    // safer than letting one NaN destroy the whole integral.
    return value.re.isFinite ? value.re : 0.0;
  }

  final double p1 =
      0.5 +
      integrate(
            (double u) => integrand(u, shareMeasure: true),
            lower: 1e-10,
            upper: upperLimit,
            points: points,
          ) /
          math.pi;
  final double p2 =
      0.5 +
      integrate(
            (double u) => integrand(u, shareMeasure: false),
            lower: 1e-10,
            upper: upperLimit,
            points: points,
          ) /
          math.pi;

  final double discountQ = math.exp(-dividendYield * timeToExpiry);
  final double discountR = math.exp(-rate * timeToExpiry);
  final double call = spot * discountQ * p1 - strike * discountR * p2;

  // Quadrature error can leave a deep out-of-the-money price a hair below
  // zero. A negative option price is impossible, and showing one would
  // undermine the point of the whole exercise.
  final double flooredCall = call < 0 ? 0.0 : call;

  return switch (type) {
    OptionType.call => flooredCall,
    // Put-call parity: holding a call and selling a put replicates the
    // forward exactly, whatever the model.
    OptionType.put => math.max(
      flooredCall - spot * discountQ + strike * discountR,
      0,
    ),
  };
}

/// The Black-Scholes volatility that reproduces a Heston price.
///
/// This is how Heston's smile is made visible: price the same option at a
/// range of strikes under Heston, ask what single constant volatility
/// Black-Scholes would have needed to arrive at each price, and plot the
/// answers. Under Black-Scholes the line would be flat. Under Heston it
/// curves, and with a negative [HestonParams.correlation] it slopes — which
/// is the shape real option markets show.
///
/// Solved by bisection on volatility. Bisection rather than Newton because it
/// cannot diverge: the option price rises monotonically with volatility, so a
/// bracketed search always converges, where Newton can shoot off into
/// nonsense on a nearly worthless option whose vega is almost zero. A pricer
/// used behind a slider must never return a wild number.
///
/// Returns null when no volatility reproduces the price — which happens when
/// the price sits at or beyond its arbitrage bounds, and where any number
/// returned would be an invention.
double? impliedVolatility(
  OptionType type, {
  required double price,
  required double spot,
  required double strike,
  required double rate,
  required double timeToExpiry,
  double dividendYield = 0,
  double tolerance = 1e-8,
  int maxIterations = 100,
}) {
  if (price <= 0 || timeToExpiry <= 0) return null;

  double priceAt(double volatility) => bsmQuote(
    type,
    BsmInputs(
      spot: spot,
      strike: strike,
      rate: rate,
      volatility: volatility,
      timeToExpiry: timeToExpiry,
      dividendYield: dividendYield,
    ),
  ).price;

  double low = 1e-6;
  double high = 5.0;
  if (price <= priceAt(low) || price >= priceAt(high)) return null;

  for (int i = 0; i < maxIterations; i++) {
    final double mid = 0.5 * (low + high);
    final double value = priceAt(mid);
    if ((value - price).abs() < tolerance) return mid;
    if (value < price) {
      low = mid;
    } else {
      high = mid;
    }
  }
  return 0.5 * (low + high);
}

/// One point on a volatility smile.
class SmilePoint {
  const SmilePoint({
    required this.strike,
    required this.price,
    required this.impliedVolatility,
  });

  final double strike;
  final double price;

  /// Null where no Black-Scholes volatility reproduces the Heston price —
  /// far enough out of the money that the price is effectively zero.
  final double? impliedVolatility;
}

/// Prices a strip of Heston calls and backs out their implied volatilities,
/// producing the smile for a chart.
List<SmilePoint> hestonSmile({
  required HestonParams params,
  required double spot,
  required double rate,
  required double timeToExpiry,
  double dividendYield = 0,
  double minStrikeRatio = 0.7,
  double maxStrikeRatio = 1.3,
  int strikes = 25,
}) {
  assert(strikes >= 2, 'need at least two strikes to draw a line');

  return <SmilePoint>[
    for (int i = 0; i < strikes; i++)
      () {
        final double ratio =
            minStrikeRatio +
            (maxStrikeRatio - minStrikeRatio) * i / (strikes - 1);
        final double strike = spot * ratio;
        final double price = hestonVanillaPrice(
          OptionType.call,
          params: params,
          spot: spot,
          strike: strike,
          rate: rate,
          timeToExpiry: timeToExpiry,
          dividendYield: dividendYield,
        );
        return SmilePoint(
          strike: strike,
          price: price,
          impliedVolatility: impliedVolatility(
            OptionType.call,
            price: price,
            spot: spot,
            strike: strike,
            rate: rate,
            timeToExpiry: timeToExpiry,
            dividendYield: dividendYield,
          ),
        );
      }(),
  ];
}

/// What a simulated Heston path should pay.
///
/// Kept as an enum rather than a callback so the whole job stays a plain
/// value that can be posted to an isolate or serialised to an Edge Function
/// (Phase 8) — a closure cannot cross either boundary.
enum HestonPayoff {
  /// Ordinary European call or put on the final price.
  european,

  /// Average-price (Asian) option over the simulated observation dates.
  asianArithmetic,
}

/// Prices an option under Heston by simulation.
///
/// SCHEME: full-truncation Euler (Lord, Koekkoek & van Dijk, 2010). Variance
/// is evolved with an ordinary Euler step, and wherever the process needs a
/// variance it uses `max(v, 0)` instead — so a step that overshoots into
/// negative territory is floored rather than producing the square root of a
/// negative number. Of the simple fixes for that problem this one is the
/// least biased, and it degrades gracefully when the Feller condition
/// ([HestonParams.satisfiesFeller]) fails and variance genuinely visits zero.
///
/// THE BIAS THIS LEAVES, stated plainly. Unlike the geometric Brownian motion
/// in `monte_carlo.dart`, which is stepped EXACTLY, this scheme is an
/// approximation of the true process: it carries a discretisation bias on top
/// of its sampling error, and that bias is NOT described by the standard
/// error in the result. The bias shrinks as [McSettings.steps] rises; the
/// sampling error shrinks as paths rise; both are needed. Andersen's QE
/// scheme (2008) converges faster and would be the upgrade if this ever
/// needed to be production-grade rather than teaching-grade.
///
/// For European payoffs, prefer [hestonVanillaPrice] — it is faster and has
/// neither kind of error. This exists for the payoffs that have no formula,
/// and as the check that the simulation and the formula agree.
McEstimate hestonMonteCarloPrice(
  OptionType type, {
  required HestonParams params,
  required double spot,
  required double strike,
  required double rate,
  required double timeToExpiry,
  double dividendYield = 0,
  HestonPayoff payoff = HestonPayoff.european,
  McSettings settings = const McSettings(),
}) {
  final double dt = timeToExpiry / settings.steps;
  final double sqrtDt = math.sqrt(dt);
  final double kappa = params.meanReversion;
  final double theta = params.longRunVariance;
  final double xi = params.volOfVol;
  final double rho = params.correlation;
  final double rhoComplement = math.sqrt(math.max(1 - rho * rho, 0));

  // Two correlated shocks per step: one for the price, one for its variance.
  final NormalPathSampler sampler = NormalPathSampler(
    settings.seed,
    dimension: 2 * settings.steps,
    antithetic: settings.antithetic,
  );
  final McAccumulator acc = McAccumulator(paired: settings.antithetic);

  for (int p = 0; p < settings.paths; p++) {
    final Float64List shocks = sampler.nextPath();
    double logSpot = math.log(spot);
    double variance = params.initialVariance;
    double runningTotal = 0;

    for (int step = 0; step < settings.steps; step++) {
      // Build the correlated pair from two independent draws. zPrice carries
      // the correlation, so a negative rho means a downward price shock
      // arrives together with an upward variance shock — the leverage effect
      // that gives equity markets their skew.
      final double zVariance = shocks[2 * step];
      final double zIndependent = shocks[2 * step + 1];
      final double zPrice = rho * zVariance + rhoComplement * zIndependent;

      // Full truncation: the variance CARRIED FORWARD may go negative, but
      // every use of it is floored at zero. Truncating the state itself
      // instead (the naive fix) biases variance upward and prices with it.
      final double usable = variance > 0 ? variance : 0.0;
      final double volatility = math.sqrt(usable);

      logSpot +=
          (rate - dividendYield - 0.5 * usable) * dt +
          volatility * sqrtDt * zPrice;
      variance +=
          kappa * (theta - usable) * dt + xi * volatility * sqrtDt * zVariance;

      if (payoff == HestonPayoff.asianArithmetic) {
        runningTotal += math.exp(logSpot);
      }
    }

    final double observed = payoff == HestonPayoff.asianArithmetic
        ? runningTotal / settings.steps
        : math.exp(logSpot);

    acc.add(
      switch (type) {
        OptionType.call => observed > strike ? observed - strike : 0.0,
        OptionType.put => strike > observed ? strike - observed : 0.0,
      },
    );
  }

  return acc.finish(discountFactor: math.exp(-rate * timeToExpiry));
}
