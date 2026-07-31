/// Basket options: one contract written on several correlated underlyings
/// (Phase 8).
///
/// Pure Dart with NO Flutter imports (CLAUDE.md architecture rule).
///
/// WHAT A BASKET OPTION IS. Instead of a call on one share, a call on a
/// weighted mixture of several — an index-like blend. Its price is NOT the sum
/// of the prices of the individual options, and the gap between the two is the
/// whole point of the instrument.
///
/// CORRELATION IS THE PRICE DRIVER. A basket of shares that move together is
/// almost as volatile as one share, so an option on it is expensive. A basket
/// of shares that move independently is far steadier, because one falling
/// while another rises leaves the blend nearly unchanged — so the option is
/// cheap. Diversification shows up in an option price as lower volatility, and
/// therefore as a smaller premium. A basket option is always worth AT MOST the
/// weighted sum of the single-name options, and the shortfall is exactly what
/// correlation below 1 buys.
///
/// THE HONEST PART (CLAUDE.md rules 4 and 5). Correlation is the least stable
/// input in this file. It is estimated from history, it is not constant, and
/// it has a documented habit of rising towards 1 in a crash — precisely when a
/// diversified basket is being relied on to hold up. A basket price that looks
/// cheap because of a low correlation estimate is cheap only if that estimate
/// holds, and it is the input most likely not to. The UI must say so.
///
/// ASSUMPTIONS. Every asset follows geometric Brownian motion with its own
/// constant volatility and dividend yield; the shocks driving them are jointly
/// normal with a constant correlation matrix; and every Black-Scholes-Merton
/// assumption from `black_scholes.dart` applies to each one.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'black_scholes.dart';
import 'monte_carlo.dart';
import 'random.dart';

/// One underlying inside a basket.
class BasketAsset {
  const BasketAsset({
    required this.spot,
    required this.volatility,
    required this.weight,
    this.dividendYield = 0,
    this.name = '',
  }) : assert(spot > 0, 'spot must be positive'),
       assert(volatility > 0, 'volatility must be positive');

  final double spot;
  final double volatility;

  /// Share of the basket. Weights are normalised to sum to 1 by
  /// [BasketSpec.normalisedWeights], so they can be entered as percentages,
  /// units, or anything else proportional.
  final double weight;

  final double dividendYield;

  /// Display label. Deliberately generic ("Asset A") by default — this is a
  /// teaching model, and naming a real company would imply a view about it.
  final String name;

  BasketAsset copyWith({
    double? spot,
    double? volatility,
    double? weight,
    double? dividendYield,
    String? name,
  }) => BasketAsset(
    spot: spot ?? this.spot,
    volatility: volatility ?? this.volatility,
    weight: weight ?? this.weight,
    dividendYield: dividendYield ?? this.dividendYield,
    name: name ?? this.name,
  );
}

/// How the basket blends its members.
enum BasketAverage {
  /// Ordinary weighted sum — what a real basket or index option uses. The
  /// weighted sum of lognormals is not itself lognormal, which is exactly why
  /// there is no formula for it and why simulation is needed.
  arithmetic,

  /// Weighted geometric mean. Rarely traded, but a weighted product of
  /// lognormals IS lognormal, so it has an exact closed form
  /// ([geometricBasketPrice]) — which makes it the reference the simulation
  /// is checked against.
  geometric,
}

/// A basket contract and the market it lives in.
///
/// Everything the pricer needs is bundled into one object so the whole job can
/// be handed to an isolate (Phase 8) or serialised to an Edge Function without
/// a second argument list going out of sync with the first.
class BasketSpec {
  const BasketSpec({
    required this.assets,
    required this.correlation,
    required this.strike,
    required this.type,
    required this.rate,
    required this.timeToExpiry,
    this.average = BasketAverage.arithmetic,
  }) : assert(assets.length >= 1, 'a basket needs at least one asset'),
       assert(strike > 0, 'strike must be positive'),
       assert(timeToExpiry > 0, 'timeToExpiry must be positive');

  final List<BasketAsset> assets;

  /// Square correlation matrix, `correlation[i][j]` between assets i and j.
  /// Must be symmetric with 1s on the diagonal.
  final List<List<double>> correlation;

  final double strike;
  final OptionType type;
  final double rate;
  final double timeToExpiry;
  final BasketAverage average;

  int get size => assets.length;

  /// Weights rescaled to sum to 1.
  ///
  /// Normalising means the basket level starts near the individual spots
  /// rather than at their raw sum, so a strike "at the money" means what a
  /// learner expects it to mean.
  List<double> get normalisedWeights {
    final double total = assets.fold<double>(
      0,
      (double sum, BasketAsset a) => sum + a.weight,
    );
    assert(total > 0, 'weights must sum to something positive');
    return <double>[
      for (final BasketAsset a in assets) a.weight / total,
    ];
  }

  /// The basket's level today, under the blend this contract uses.
  double get spotLevel {
    final List<double> w = normalisedWeights;
    if (average == BasketAverage.arithmetic) {
      double level = 0;
      for (int i = 0; i < size; i++) {
        level += w[i] * assets[i].spot;
      }
      return level;
    }
    double logLevel = 0;
    for (int i = 0; i < size; i++) {
      logLevel += w[i] * math.log(assets[i].spot);
    }
    return math.exp(logLevel);
  }

  /// Variance of the basket's log-return over the life of the contract, using
  /// the standard `w' Σ w` quadratic form.
  ///
  /// Exact for a geometric basket. For an arithmetic one it is an
  /// approximation, and is used here only to describe the basket's effective
  /// volatility in the UI, never to price it.
  double get logVariance {
    final List<double> w = normalisedWeights;
    double v = 0;
    for (int i = 0; i < size; i++) {
      for (int j = 0; j < size; j++) {
        v +=
            w[i] *
            w[j] *
            assets[i].volatility *
            assets[j].volatility *
            correlation[i][j];
      }
    }
    return v * timeToExpiry;
  }

  /// Annualised volatility of the blended basket.
  ///
  /// Compare it with the individual volatilities to see diversification as a
  /// single number: it sits below the weighted average of its members unless
  /// every correlation is 1.
  double get effectiveVolatility =>
      math.sqrt(math.max(logVariance, 0) / timeToExpiry);

  BasketSpec copyWith({
    List<BasketAsset>? assets,
    List<List<double>>? correlation,
    double? strike,
    OptionType? type,
    double? rate,
    double? timeToExpiry,
    BasketAverage? average,
  }) => BasketSpec(
    assets: assets ?? this.assets,
    correlation: correlation ?? this.correlation,
    strike: strike ?? this.strike,
    type: type ?? this.type,
    rate: rate ?? this.rate,
    timeToExpiry: timeToExpiry ?? this.timeToExpiry,
    average: average ?? this.average,
  );
}

/// Builds a correlation matrix where every distinct pair shares one [rho].
///
/// The Sandbox exposes a single correlation slider rather than an n-by-n grid:
/// one number a learner can drag from 0 to 1 and watch the price move teaches
/// the idea, where twenty boxes would teach data entry.
List<List<double>> uniformCorrelation(int size, double rho) => <List<double>>[
  for (int i = 0; i < size; i++)
    <double>[for (int j = 0; j < size; j++) i == j ? 1.0 : rho],
];

/// Lower-triangular Cholesky factor L with `L * L' = matrix`.
///
/// This is how correlation gets into the simulation. Independent normal
/// shocks z are turned into correlated ones by multiplying with L, so
/// simulated assets move together in exactly the pattern the matrix
/// describes.
///
/// Throws [ArgumentError] when the matrix is not positive semi-definite —
/// which is not a pedantic technicality. A matrix like "A and B correlate
/// 0.9, B and C correlate 0.9, A and C correlate -0.9" describes a world that
/// cannot exist, and a pricer that silently produced a number for it would be
/// lying. With a shared [uniformCorrelation] rho the condition is simply
/// rho > -1/(n-1).
List<List<double>> choleskyDecompose(List<List<double>> matrix) {
  final int n = matrix.length;
  final List<List<double>> l = <List<double>>[
    for (int i = 0; i < n; i++) List<double>.filled(n, 0),
  ];

  for (int i = 0; i < n; i++) {
    for (int j = 0; j <= i; j++) {
      double sum = 0;
      for (int k = 0; k < j; k++) {
        sum += l[i][k] * l[j][k];
      }
      if (i == j) {
        final double diagonal = matrix[i][i] - sum;
        // A tiny negative here is rounding on a genuinely valid matrix; a
        // meaningfully negative one means the correlations contradict.
        if (diagonal < -1e-10) {
          throw ArgumentError(
            'These correlations are impossible: no set of assets can move '
            'this way at once. Try bringing the extreme pairs closer to zero.',
          );
        }
        l[i][j] = math.sqrt(math.max(diagonal, 0));
      } else {
        // A zero pivot means the assets are perfectly dependent — one is
        // redundant. Not an error; the remaining entries in that column are
        // simply zero.
        l[i][j] = l[j][j] == 0 ? 0 : (matrix[i][j] - sum) / l[j][j];
      }
    }
  }
  return l;
}

/// Prices a basket option by simulation.
///
/// Only the terminal level matters, so each path is a single jump to expiry
/// rather than a walk through it — the correlated shocks are what make this
/// interesting, not the passage of time.
McEstimate basketMonteCarloPrice(
  BasketSpec spec, {
  McSettings settings = const McSettings(steps: 1),
}) {
  final int n = spec.size;
  final double t = spec.timeToExpiry;
  final List<double> weights = spec.normalisedWeights;
  final List<List<double>> chol = choleskyDecompose(spec.correlation);

  // Per-asset drift and diffusion over the whole life of the contract.
  final Float64List drift = Float64List(n);
  final Float64List diffusion = Float64List(n);
  for (int i = 0; i < n; i++) {
    final BasketAsset a = spec.assets[i];
    drift[i] =
        (spec.rate - a.dividendYield - 0.5 * a.volatility * a.volatility) * t;
    diffusion[i] = a.volatility * math.sqrt(t);
  }

  final NormalPathSampler sampler = NormalPathSampler(
    settings.seed,
    dimension: n,
    antithetic: settings.antithetic,
  );
  final McAccumulator acc = McAccumulator(paired: settings.antithetic);
  final Float64List correlated = Float64List(n);

  for (int p = 0; p < settings.paths; p++) {
    final Float64List z = sampler.nextPath();

    // Correlate the independent shocks: correlated = L * z.
    for (int i = 0; i < n; i++) {
      double sum = 0;
      for (int k = 0; k <= i; k++) {
        sum += chol[i][k] * z[k];
      }
      correlated[i] = sum;
    }

    double level = 0;
    double logLevel = 0;
    for (int i = 0; i < n; i++) {
      final double terminal =
          spec.assets[i].spot *
          math.exp(drift[i] + diffusion[i] * correlated[i]);
      if (spec.average == BasketAverage.arithmetic) {
        level += weights[i] * terminal;
      } else {
        logLevel += weights[i] * math.log(terminal);
      }
    }
    if (spec.average == BasketAverage.geometric) {
      level = math.exp(logLevel);
    }

    acc.add(
      switch (spec.type) {
        OptionType.call => level > spec.strike ? level - spec.strike : 0.0,
        OptionType.put => spec.strike > level ? spec.strike - level : 0.0,
      },
    );
  }

  return acc.finish(discountFactor: math.exp(-spec.rate * t));
}

/// Exact price of a GEOMETRIC basket option.
///
/// A weighted product of lognormal prices is itself lognormal, so this one
/// case collapses back to a Black-Scholes-style formula with an effective
/// forward and an effective volatility. Two uses:
///
/// 1. It is the reference the simulation is unit-tested against — a closed
///    form and a simulation agreeing on the one payoff where both apply is
///    what justifies trusting the simulation on the payoffs where only it
///    applies.
/// 2. It is a fast lower bound for the arithmetic basket, which is always
///    worth at least as much (the arithmetic mean of positive numbers is
///    never below their geometric mean).
///
/// [BasketSpec.average] is ignored: this always prices the geometric contract.
double geometricBasketPrice(BasketSpec spec) {
  final int n = spec.size;
  final double t = spec.timeToExpiry;
  final List<double> w = spec.normalisedWeights;

  // Mean and variance of log(basket at expiry) under the risk-neutral measure.
  double mean = 0;
  for (int i = 0; i < n; i++) {
    final BasketAsset a = spec.assets[i];
    mean +=
        w[i] *
        (math.log(a.spot) +
            (spec.rate - a.dividendYield - 0.5 * a.volatility * a.volatility) *
                t);
  }
  final double variance = spec.logVariance;
  final double sd = math.sqrt(math.max(variance, 0));

  // The basket's forward price: E[basket at expiry] for a lognormal.
  final double forward = math.exp(mean + 0.5 * variance);
  final double discount = math.exp(-spec.rate * t);

  if (sd < 1e-12) {
    // Zero variance: the basket's level at expiry is already known.
    final double payoff = spec.type == OptionType.call
        ? math.max(forward - spec.strike, 0)
        : math.max(spec.strike - forward, 0);
    return discount * payoff;
  }

  final double d1 = (math.log(forward / spec.strike) + 0.5 * variance) / sd;
  final double d2 = d1 - sd;

  return switch (spec.type) {
    OptionType.call =>
      discount * (forward * normalCdf(d1) - spec.strike * normalCdf(d2)),
    OptionType.put =>
      discount * (spec.strike * normalCdf(-d2) - forward * normalCdf(-d1)),
  };
}
