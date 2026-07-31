/// Random numbers for Monte Carlo pricing (Phase 8).
///
/// Pure Dart with NO Flutter imports (CLAUDE.md architecture rule).
///
/// WHY NOT `dart:math`'s Random? Two reasons, both about being able to trust
/// the numbers:
///
/// 1. REPRODUCIBILITY. `Random(seed)` is not contractually stable across Dart
///    versions or platforms, so a price could quietly change between releases
///    with nothing in the app to explain it. The generator here is a named,
///    published algorithm written out in full, so the same seed gives the same
///    price on every device, forever. A learner dragging a slider back to
///    where it was sees the number they saw before.
/// 2. TESTABILITY. A fixed sequence means a Monte Carlo test either passes or
///    fails; it does not pass four times out of five.
///
/// Determinism is NOT a claim of accuracy. A Monte Carlo price is an estimate
/// with a sampling error attached, and `McEstimate` in `monte_carlo.dart`
/// carries that error so the UI can show it.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// xoshiro128** 1.0 — Blackman & Vigna's small-state generator.
///
/// Chosen over a linear congruential generator because LCGs have well-known
/// correlations in their low bits, and Monte Carlo option pricing draws
/// millions of numbers whose *joint* behaviour matters (a barrier is knocked
/// out by a run of correlated draws, not by any single one). xoshiro128**
/// passes the standard statistical batteries and needs only four 32-bit words
/// of state, so a path generator is cheap to copy into an isolate.
///
/// NOT cryptographically secure, and it must never be used for anything that
/// needs to be unguessable. Simulating share prices is not such a thing.
class Xoshiro128 {
  /// Seeds the four state words from a single [seed] via SplitMix32.
  ///
  /// Seeding matters: filling the state with the seed directly would make
  /// seeds 1 and 2 produce near-identical opening draws, and an all-zero
  /// state is a fixed point that emits zeros forever. SplitMix32 avalanches
  /// the seed so neighbouring seeds give unrelated streams.
  Xoshiro128(int seed) {
    int x = seed & _mask32;
    int splitmix32() {
      x = (x + 0x9e3779b9) & _mask32;
      int z = x;
      z = (z ^ (z >>> 16)) & _mask32;
      z = (z * 0x21f0aaad) & _mask32;
      z = (z ^ (z >>> 15)) & _mask32;
      z = (z * 0x735a2d97) & _mask32;
      return (z ^ (z >>> 15)) & _mask32;
    }

    _s0 = splitmix32();
    _s1 = splitmix32();
    _s2 = splitmix32();
    _s3 = splitmix32();

    // Guard the all-zero fixed point, which SplitMix32 makes vanishingly
    // unlikely but does not make impossible.
    if ((_s0 | _s1 | _s2 | _s3) == 0) _s0 = 0x9e3779b9;
  }

  static const int _mask32 = 0xFFFFFFFF;

  late int _s0;
  late int _s1;
  late int _s2;
  late int _s3;

  static int _rotl(int x, int k) =>
      ((x << k) | (x >>> (32 - k))) & _mask32;

  /// The next 32-bit unsigned value.
  int nextUint32() {
    final int result = (_rotl((_s1 * 5) & _mask32, 7) * 9) & _mask32;
    final int t = (_s1 << 9) & _mask32;

    _s2 ^= _s0;
    _s3 ^= _s1;
    _s1 ^= _s2;
    _s0 ^= _s3;
    _s2 ^= t;
    _s3 = _rotl(_s3, 11);

    return result;
  }

  /// A uniform draw in `[0, 1)`, built from 53 bits — the full precision of a
  /// Dart double.
  ///
  /// One 32-bit word would leave only ~4.3 billion distinct values and, more
  /// importantly, would truncate the far tail of the inverse-normal transform
  /// below: the smallest non-zero draw from 32 bits maps to about -6.2
  /// standard deviations, so a crash worse than that could never be sampled.
  double nextDouble() {
    final int hi = nextUint32() >>> 5; // 27 bits
    final int lo = nextUint32() >>> 6; // 26 bits
    return (hi * 67108864.0 + lo) / 9007199254740992.0;
  }
}

/// Draws the block of standard normal N(0,1) shocks one simulated path needs.
///
/// Share-price models need normal shocks, not uniform ones: under geometric
/// Brownian motion the log of the price moves by a normal draw each step.
///
/// WHY A WHOLE PATH AT A TIME rather than a draw at a time. Antithetic
/// sampling only means anything at the level of a path: the mirror of a path
/// is the path built from the NEGATED VECTOR of its shocks, so that where one
/// drifts up the other drifts down by the same amount. Handing out
/// `z, -z, z', -z', ...` one draw at a time would instead mirror each step
/// against the step after it *within a single path*, which is not a variance
/// reduction at all — it forces every path to be its own average and quietly
/// destroys the very dispersion the simulation is trying to measure. Sampling
/// a fixed-length vector makes the correct pairing structural.
class NormalPathSampler {
  NormalPathSampler(int seed, {required this.dimension, this.antithetic = false})
    : assert(dimension >= 1, 'a path needs at least one shock'),
      _rng = Xoshiro128(seed),
      _buffer = Float64List(dimension);

  /// How many shocks one path consumes: steps for a single asset, assets for
  /// a one-step basket, steps x assets for a path-dependent basket. Fixed for
  /// the life of the sampler, because antithetic pairing depends on both
  /// halves of a pair being the same shape.
  final int dimension;

  /// ANTITHETIC VARIATES, a standard variance-reduction trick (Glasserman,
  /// "Monte Carlo Methods in Financial Engineering", ch. 4): every path is
  /// followed by its mirror image. Since -z is exactly as likely as z the
  /// estimator stays unbiased, but the two paths lean in opposite directions
  /// and their errors partly cancel, so a given number of paths buys a
  /// tighter answer.
  ///
  /// The pairing must be respected when the standard error is computed, or
  /// the reported error comes out too small — the one direction an honest
  /// error bar must never be wrong in. [McAccumulator] averages each pair
  /// into a single observation before measuring spread.
  final bool antithetic;

  final Xoshiro128 _rng;
  final Float64List _buffer;
  bool _mirrorNext = false;

  /// Fills and returns this path's shocks.
  ///
  /// The returned list is REUSED on the next call, so a caller that needs to
  /// keep it must copy it. Reuse is deliberate: a ten-million-path run would
  /// otherwise allocate ten million short-lived lists.
  Float64List nextPath() {
    if (antithetic && _mirrorNext) {
      _mirrorNext = false;
      for (int i = 0; i < dimension; i++) {
        _buffer[i] = -_buffer[i];
      }
      return _buffer;
    }

    for (int i = 0; i < dimension; i++) {
      // Clamped away from 0 and 1: the inverse normal CDF is infinite at both
      // ends, and one infinite draw would poison a whole batch of paths.
      final double u = _rng.nextDouble().clamp(_tiny, 1 - _tiny);
      _buffer[i] = inverseNormalCdf(u);
    }
    _mirrorNext = antithetic;
    return _buffer;
  }

  static const double _tiny = 1e-15;
}

/// Inverse of the standard normal CDF: the z with Phi(z) = [p].
///
/// Peter Acklam's rational approximation (2000), relative error below 1.15e-9
/// across the whole range — far finer than any Monte Carlo sampling error it
/// will sit inside.
///
/// The inverse-CDF route is preferred over Box-Muller here because it turns
/// exactly one uniform draw into exactly one normal draw. That one-to-one map
/// is what lets antithetic sampling above work, and it is what would let
/// low-discrepancy (quasi-random) sequences be dropped in later; Box-Muller
/// consumes two uniforms per pair of normals and scrambles both properties.
double inverseNormalCdf(double p) {
  assert(p > 0 && p < 1, 'p must be strictly inside (0, 1)');

  const List<double> a = <double>[
    -3.969683028665376e+01,
    2.209460984245205e+02,
    -2.759285104469687e+02,
    1.383577518672690e+02,
    -3.066479806614716e+01,
    2.506628277459239e+00,
  ];
  const List<double> b = <double>[
    -5.447609879822406e+01,
    1.615858368580409e+02,
    -1.556989798598866e+02,
    6.680131188771972e+01,
    -1.328068155288572e+01,
  ];
  const List<double> c = <double>[
    -7.784894002430293e-03,
    -3.223964580411365e-01,
    -2.400758277161838e+00,
    -2.549732539343734e+00,
    4.374664141464968e+00,
    2.938163982698783e+00,
  ];
  const List<double> d = <double>[
    7.784695709041462e-03,
    3.224671290700398e-01,
    2.445134137142996e+00,
    3.754408661907416e+00,
  ];

  // The central and tail regions need different expansions; 0.02425 is where
  // Acklam splits them.
  const double pLow = 0.02425;
  const double pHigh = 1 - pLow;

  if (p < pLow) {
    final double q = math.sqrt(-2 * math.log(p));
    return (((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q +
            c[5]) /
        ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1);
  }
  if (p > pHigh) {
    final double q = math.sqrt(-2 * math.log(1 - p));
    return -(((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q +
            c[5]) /
        ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1);
  }

  final double q = p - 0.5;
  final double r = q * q;
  return (((((a[0] * r + a[1]) * r + a[2]) * r + a[3]) * r + a[4]) * r + a[5]) *
      q /
      (((((b[0] * r + b[1]) * r + b[2]) * r + b[3]) * r + b[4]) * r + 1);
}
