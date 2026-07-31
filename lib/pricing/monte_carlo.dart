/// Monte Carlo pricing for path-dependent options (Phase 8).
///
/// Pure Dart with NO Flutter imports (CLAUDE.md architecture rule), so it runs
/// unchanged inside a Dart isolate (`compute()`) or a server-side function.
///
/// WHY SIMULATE AT ALL. Black-Scholes-Merton gives an exact formula because a
/// European option's value depends on one number: the price at expiry. As soon
/// as the payoff depends on the *route* — did it ever touch 90? what was the
/// average? — there is usually no formula, so the price is estimated by
/// generating many possible routes and averaging what the contract would have
/// paid on each.
///
/// WHAT A MONTE CARLO PRICE IS, HONESTLY (CLAUDE.md rules 4 and 5). It is an
/// ESTIMATE, not a value. Run it again with a different seed and you get a
/// slightly different number. [McEstimate] therefore carries a standard error
/// and a confidence interval, and the UI is expected to show them: quoting a
/// simulated price to the cent without saying how uncertain it is would be the
/// kind of false precision this app exists to argue against.
///
/// ASSUMPTIONS. Everything from `black_scholes.dart` (geometric Brownian
/// motion, constant volatility and rate, no arbitrage, no fees or spreads),
/// plus:
/// - The barrier and any average are monitored at the [McSettings.steps]
///   simulation dates, NOT continuously — see [barrierMonteCarloPrice].
/// - Sampling error shrinks as 1/sqrt(paths): four times the work buys half
///   the error. That is the whole reason heavy runs need an isolate.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'barrier.dart';
import 'black_scholes.dart';
import 'random.dart';

/// How hard to run a simulation.
class McSettings {
  const McSettings({
    this.paths = 20000,
    this.steps = 100,
    this.seed = 20260731,
    this.antithetic = true,
  }) : assert(paths > 1, 'need at least two paths to estimate an error'),
       assert(steps >= 1, 'need at least one step');

  /// How many simulated futures to average over. Error falls with the square
  /// root of this, so it is the dial that trades time for precision.
  final int paths;

  /// How many observation dates each path is broken into. Only matters for
  /// payoffs that watch the route; a European payoff uses one step because
  /// only the endpoint counts, and simulating the middle would cost time
  /// while changing nothing.
  final int steps;

  /// Fixes the random stream. Same seed, same price — so nudging a slider
  /// back to where it was gives the number the learner saw before, and the
  /// visible wobble is the model's, not the dice's.
  final int seed;

  /// Pair every path with its mirror image to cut sampling error. See
  /// [NormalSampler.antithetic].
  final bool antithetic;

  /// Roughly how many normal draws a run will consume — used by the UI to
  /// decide whether a run belongs on an isolate or on a server.
  int get workload => paths * steps;

  McSettings copyWith({int? paths, int? steps, int? seed, bool? antithetic}) =>
      McSettings(
        paths: paths ?? this.paths,
        steps: steps ?? this.steps,
        seed: seed ?? this.seed,
        antithetic: antithetic ?? this.antithetic,
      );
}

/// A simulated price and how much to trust it.
class McEstimate {
  const McEstimate({
    required this.price,
    required this.standardError,
    required this.paths,
  });

  /// Mean discounted payoff across the simulated paths.
  final double price;

  /// Standard error of that mean: the typical distance between this estimate
  /// and the price an infinitely long run would converge to.
  final double standardError;

  /// Paths actually averaged. With antithetic sampling, mirrored pairs are
  /// averaged into one observation first, so this is the number of
  /// INDEPENDENT observations — the number the error is computed from.
  final int paths;

  /// 95% confidence interval, +/- 1.96 standard errors.
  ///
  /// Read it as: run this simulation many times and about 19 intervals in 20
  /// would contain the model's true price. It says nothing about whether the
  /// MODEL is right about the market — that is a separate and much larger
  /// question the lessons take up.
  (double, double) get confidenceInterval95 => (
    price - 1.96 * standardError,
    price + 1.96 * standardError,
  );

  /// Standard error as a fraction of the price, or null when the price is
  /// effectively zero and a percentage would be meaningless.
  double? get relativeError =>
      price.abs() < 1e-9 ? null : standardError / price.abs();
}

/// Running mean and variance of the simulated payoffs.
///
/// Kept as a running total rather than a list so a ten-million-path run does
/// not need ten million doubles in memory.
class McAccumulator {
  McAccumulator({required this.paired});

  /// True when paths arrive in antithetic pairs. Each pair is averaged into a
  /// single observation before the spread is measured — the two halves of a
  /// pair are deliberately negatively correlated, so treating them as
  /// independent would understate the error, which is the one direction an
  /// honest error bar must never be wrong in.
  final bool paired;

  int _count = 0;
  double _sum = 0;
  double _sumSquares = 0;
  double? _pending;

  void add(double payoff) {
    if (!paired) {
      _record(payoff);
      return;
    }
    if (_pending == null) {
      _pending = payoff;
      return;
    }
    _record(0.5 * (_pending! + payoff));
    _pending = null;
  }

  void _record(double value) {
    _count++;
    _sum += value;
    _sumSquares += value * value;
  }

  /// Discounts the mean payoff back to today and attaches its error.
  McEstimate finish({required double discountFactor}) {
    if (_count == 0) {
      return const McEstimate(price: 0, standardError: 0, paths: 0);
    }
    final double mean = _sum / _count;
    // Sample variance. Clamped at zero because catastrophic cancellation can
    // make this a tiny negative when every payoff is identical (a knock-out
    // that always dies, say), and sqrt of a negative is NaN.
    final double variance = _count < 2
        ? 0.0
        : math.max((_sumSquares - _count * mean * mean) / (_count - 1), 0);

    return McEstimate(
      price: discountFactor * mean,
      standardError: discountFactor * math.sqrt(variance / _count),
      paths: _count,
    );
  }
}

/// One step of geometric Brownian motion, exactly.
///
/// GBM has a closed-form solution, so each step is drawn from the exact
/// distribution rather than approximated by an Euler step. There is no
/// discretisation bias in the price *path* itself; the only discretisation
/// error left is in what the payoff observes between steps (a barrier touched
/// and untouched inside one step goes unseen).
double _gbmStep(double s, double drift, double diffusion, double z) =>
    s * math.exp(drift + diffusion * z);

/// Prices a European call or put by simulation.
///
/// Deliberately redundant — `bsmQuote` already answers this exactly and much
/// faster. It exists because it is the calibration test: a Monte Carlo engine
/// that cannot reproduce Black-Scholes to within its own error bars is
/// broken, and that check is the reason the barrier and basket numbers below
/// can be trusted.
///
/// [McSettings.steps] defaults to 1 because only the endpoint matters, and
/// simulating the middle would cost time while changing nothing. Higher
/// values are still honoured, and give the same answer in distribution
/// because geometric Brownian motion composes exactly: walking to expiry in
/// n steps and jumping there in one draw from the same total variance are the
/// same process. The reason to pay for the walk is comparability — with a
/// shared seed and step count this consumes exactly the shocks the barrier
/// engine does, which is what makes "knock-in plus knock-out equals vanilla"
/// checkable path by path rather than merely within sampling error.
McEstimate europeanMonteCarloPrice(
  OptionType type,
  BsmInputs inputs, {
  McSettings settings = const McSettings(steps: 1),
}) {
  final double t = inputs.timeToExpiry;
  final double dt = t / settings.steps;
  final double drift =
      (inputs.rate -
          inputs.dividendYield -
          0.5 * inputs.volatility * inputs.volatility) *
      dt;
  final double diffusion = inputs.volatility * math.sqrt(dt);

  final NormalPathSampler sampler = NormalPathSampler(
    settings.seed,
    dimension: settings.steps,
    antithetic: settings.antithetic,
  );
  final McAccumulator acc = McAccumulator(paired: settings.antithetic);

  for (int i = 0; i < settings.paths; i++) {
    final Float64List shocks = sampler.nextPath();
    double s = inputs.spot;
    for (int step = 0; step < settings.steps; step++) {
      s = _gbmStep(s, drift, diffusion, shocks[step]);
    }
    acc.add(_vanillaPayoff(type, s, inputs.strike));
  }

  return acc.finish(discountFactor: math.exp(-inputs.rate * t));
}

/// Prices a barrier option by simulation, with the barrier watched at each of
/// [McSettings.steps] dates.
///
/// DISCRETE VS CONTINUOUS, which is the whole subtlety of barrier pricing.
/// `barrierPrice` in `barrier.dart` assumes the barrier is watched at every
/// instant. A simulation can only look at finitely many dates, so it misses
/// excursions that dip through and recover between two observations. That
/// makes a simulated knock-out look MORE valuable than the continuous formula
/// says, and a knock-in less — and the gap shrinks only as 1/sqrt(steps),
/// which is slow.
///
/// Set [continuityCorrection] to price the CONTINUOUS contract from discrete
/// steps by nudging the barrier away from the spot (Broadie-Glasserman-Kou);
/// leave it off to price a contract that genuinely is only monitored at those
/// dates, which is what most real barrier contracts are.
McEstimate barrierMonteCarloPrice(
  BarrierSpec spec,
  BsmInputs inputs, {
  McSettings settings = const McSettings(),
  bool continuityCorrection = false,
}) {
  final double t = inputs.timeToExpiry;
  final double discount = math.exp(-inputs.rate * t);

  // Already through the barrier before the first step: no path can change
  // that, so answer directly instead of simulating a foregone conclusion.
  if (spec.alreadyTriggered(inputs.spot)) {
    final double settled = spec.style == BarrierStyle.knockOut
        ? 0.0
        : bsmQuote(spec.type, inputs).price;
    return McEstimate(
      price: settled,
      standardError: 0,
      paths: settings.paths,
    );
  }

  final double level = continuityCorrection
      ? continuousEquivalentBarrier(
          spec.barrier,
          direction: spec.direction,
          volatility: inputs.volatility,
          timeToExpiry: t,
          monitoringDates: settings.steps,
        )
      : spec.barrier;

  final double dt = t / settings.steps;
  final double drift =
      (inputs.rate -
          inputs.dividendYield -
          0.5 * inputs.volatility * inputs.volatility) *
      dt;
  final double diffusion = inputs.volatility * math.sqrt(dt);
  final bool down = spec.direction == BarrierDirection.down;

  final NormalPathSampler sampler = NormalPathSampler(
    settings.seed,
    dimension: settings.steps,
    antithetic: settings.antithetic,
  );
  final McAccumulator acc = McAccumulator(paired: settings.antithetic);

  for (int i = 0; i < settings.paths; i++) {
    final Float64List shocks = sampler.nextPath();
    double s = inputs.spot;
    bool touched = false;

    // The whole path is walked even once the barrier has been touched,
    // because a knock-IN still needs the price it finishes at. A knock-out
    // could stop early, but the saving is not worth two code paths through
    // the part of the engine most likely to hide a bug.
    for (int step = 0; step < settings.steps; step++) {
      s = _gbmStep(s, drift, diffusion, shocks[step]);
      if (!touched && (down ? s <= level : s >= level)) {
        touched = true;
      }
    }

    final bool alive = spec.style == BarrierStyle.knockOut ? !touched : touched;
    acc.add(alive ? _vanillaPayoff(spec.type, s, inputs.strike) : 0.0);
  }

  return acc.finish(discountFactor: discount);
}

/// How an Asian option averages the underlying.
enum AsianAverage {
  /// Ordinary (arithmetic) mean of the observed prices. What contracts
  /// actually use, and what has no closed-form price — hence simulation.
  arithmetic,

  /// Geometric mean. Rarely traded, but it DOES have a closed form under
  /// GBM, which makes it a useful reference for checking the engine.
  geometric,
}

/// Prices an Asian (average-price) option by simulation.
///
/// The payoff uses the average of the underlying over the life of the
/// contract instead of its final price. Averaging damps the extremes, so an
/// Asian option is worth less than the equivalent vanilla — and is much
/// harder to manipulate on a single expiry date, which is why they are common
/// in commodity and currency contracts rather than in equity markets.
///
/// The average is taken over the [McSettings.steps] simulation dates,
/// excluding today's price.
McEstimate asianMonteCarloPrice(
  OptionType type,
  BsmInputs inputs, {
  McSettings settings = const McSettings(),
  AsianAverage average = AsianAverage.arithmetic,
}) {
  final double t = inputs.timeToExpiry;
  final double dt = t / settings.steps;
  final double drift =
      (inputs.rate -
          inputs.dividendYield -
          0.5 * inputs.volatility * inputs.volatility) *
      dt;
  final double diffusion = inputs.volatility * math.sqrt(dt);

  final NormalPathSampler sampler = NormalPathSampler(
    settings.seed,
    dimension: settings.steps,
    antithetic: settings.antithetic,
  );
  final McAccumulator acc = McAccumulator(paired: settings.antithetic);

  for (int i = 0; i < settings.paths; i++) {
    final Float64List shocks = sampler.nextPath();
    double s = inputs.spot;
    double total = 0;
    double logTotal = 0;

    for (int step = 0; step < settings.steps; step++) {
      s = _gbmStep(s, drift, diffusion, shocks[step]);
      if (average == AsianAverage.arithmetic) {
        total += s;
      } else {
        logTotal += math.log(s);
      }
    }

    final double mean = average == AsianAverage.arithmetic
        ? total / settings.steps
        : math.exp(logTotal / settings.steps);
    acc.add(_vanillaPayoff(type, mean, inputs.strike));
  }

  return acc.finish(discountFactor: math.exp(-inputs.rate * t));
}

/// Value of a vanilla payoff at one underlying price: what the contract pays
/// if the underlying finishes there. Never negative — the holder walks away.
double _vanillaPayoff(OptionType type, double underlying, double strike) =>
    switch (type) {
      OptionType.call => underlying > strike ? underlying - strike : 0,
      OptionType.put => strike > underlying ? strike - underlying : 0,
    };
