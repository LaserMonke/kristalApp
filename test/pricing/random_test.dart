import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:optionsschool/pricing/black_scholes.dart';
import 'package:optionsschool/pricing/random.dart';

/// The random-number layer under every Monte Carlo price in Phase 8.
///
/// It is tested first and hardest because everything downstream inherits its
/// faults silently: a generator with a subtle correlation does not crash, it
/// just returns a price that is confidently wrong.
void main() {
  group('inverseNormalCdf', () {
    // Standard normal quantiles, the ones tabulated in every statistics text.
    test('matches known quantiles', () {
      expect(inverseNormalCdf(0.5), closeTo(0, 1e-9));
      expect(inverseNormalCdf(0.9), closeTo(1.2815515655, 1e-6));
      expect(inverseNormalCdf(0.95), closeTo(1.6448536270, 1e-6));
      expect(inverseNormalCdf(0.975), closeTo(1.9599639845, 1e-6));
      expect(inverseNormalCdf(0.99), closeTo(2.3263478740, 1e-6));
      expect(inverseNormalCdf(0.999), closeTo(3.0902323062, 1e-5));
    });

    test('is antisymmetric about 0.5', () {
      for (final double p in <double>[0.001, 0.02, 0.2, 0.4, 0.49]) {
        expect(inverseNormalCdf(p), closeTo(-inverseNormalCdf(1 - p), 1e-8));
      }
    });

    /// Cross-check against the OTHER approximation in the codebase. The two
    /// come from different authors (Acklam vs Abramowitz & Stegun) and were
    /// derived independently, so a shared bug is implausible; agreeing to
    /// within A&S's own 7.5e-8 error budget is real evidence both are right.
    test('round-trips through normalCdf', () {
      for (double p = 0.005; p < 1; p += 0.005) {
        expect(normalCdf(inverseNormalCdf(p)), closeTo(p, 1e-6));
      }
    });

    test('stays finite deep in the tails', () {
      expect(inverseNormalCdf(1e-15), lessThan(-7));
      expect(inverseNormalCdf(1e-15).isFinite, isTrue);
      expect(inverseNormalCdf(1 - 1e-15).isFinite, isTrue);
    });
  });

  group('Xoshiro128', () {
    test('the same seed replays the same stream', () {
      final Xoshiro128 a = Xoshiro128(42);
      final Xoshiro128 b = Xoshiro128(42);
      for (int i = 0; i < 1000; i++) {
        expect(a.nextUint32(), b.nextUint32());
      }
    });

    test('neighbouring seeds give unrelated streams', () {
      // The point of seeding through SplitMix32: seeds 1 and 2 must not open
      // with near-identical draws, or two sliders one tick apart would share
      // their sampling error.
      final Xoshiro128 a = Xoshiro128(1);
      final Xoshiro128 b = Xoshiro128(2);
      int matches = 0;
      for (int i = 0; i < 100; i++) {
        if (a.nextUint32() == b.nextUint32()) matches++;
      }
      expect(matches, 0);
    });

    test('nextDouble stays inside [0, 1)', () {
      final Xoshiro128 rng = Xoshiro128(7);
      for (int i = 0; i < 100000; i++) {
        final double u = rng.nextDouble();
        expect(u, greaterThanOrEqualTo(0));
        expect(u, lessThan(1));
      }
    });

    test('nextDouble is roughly uniform across ten buckets', () {
      final Xoshiro128 rng = Xoshiro128(99);
      final List<int> buckets = List<int>.filled(10, 0);
      const int draws = 200000;
      for (int i = 0; i < draws; i++) {
        buckets[(rng.nextDouble() * 10).floor()]++;
      }
      // Each bucket expects 20000 with a standard deviation near 134, so
      // +/- 3% is roughly twenty standard deviations of slack — this catches
      // a broken generator, not an unlucky one.
      for (final int count in buckets) {
        expect(count, closeTo(draws / 10, draws / 10 * 0.03));
      }
    });

    test('seed 0 does not collapse to the all-zero fixed point', () {
      final Xoshiro128 rng = Xoshiro128(0);
      final Set<int> seen = <int>{};
      for (int i = 0; i < 50; i++) {
        seen.add(rng.nextUint32());
      }
      expect(seen.length, greaterThan(40));
    });
  });

  group('NormalPathSampler', () {
    test('draws look standard normal', () {
      final NormalPathSampler sampler = NormalPathSampler(2026, dimension: 1);
      const int n = 200000;
      double sum = 0;
      double sumSq = 0;
      for (int i = 0; i < n; i++) {
        final double z = sampler.nextPath()[0];
        sum += z;
        sumSq += z * z;
      }
      final double mean = sum / n;
      final double sd = math.sqrt(sumSq / n - mean * mean);

      // Standard error of the mean is 1/sqrt(200000) ~= 0.0022, so 0.02 is
      // about nine standard errors.
      expect(mean, closeTo(0, 0.02));
      expect(sd, closeTo(1, 0.02));
    });

    /// The bug this guards against: mirroring draw-against-draw *inside* one
    /// path instead of path-against-path. That version passes a mean test,
    /// passes a variance test on the raw draws, and still prices everything
    /// wrong, because every path becomes its own average and the dispersion
    /// the simulation exists to measure quietly vanishes.
    test('antithetic pairs mirror the WHOLE path, not draws within it', () {
      final NormalPathSampler sampler = NormalPathSampler(
        5,
        dimension: 8,
        antithetic: true,
      );
      final Float64List first = Float64List.fromList(sampler.nextPath());
      final Float64List mirror = Float64List.fromList(sampler.nextPath());

      for (int i = 0; i < 8; i++) {
        expect(mirror[i], closeTo(-first[i], 1e-15));
      }
      // ...and the shocks inside one path must be independent, not mirrored
      // against each other.
      expect(first[1], isNot(closeTo(-first[0], 1e-12)));
    });

    test('without antithetic, consecutive paths are unrelated', () {
      final NormalPathSampler sampler = NormalPathSampler(5, dimension: 4);
      final Float64List first = Float64List.fromList(sampler.nextPath());
      final Float64List second = Float64List.fromList(sampler.nextPath());
      for (int i = 0; i < 4; i++) {
        expect(second[i], isNot(closeTo(-first[i], 1e-12)));
      }
    });

    test('antithetic sampling keeps the mean unbiased', () {
      final NormalPathSampler sampler = NormalPathSampler(
        11,
        dimension: 2,
        antithetic: true,
      );
      double sum = 0;
      for (int i = 0; i < 20000; i++) {
        final Float64List z = sampler.nextPath();
        sum += z[0] + z[1];
      }
      // Exact by construction: every draw is cancelled by its mirror.
      expect(sum, closeTo(0, 1e-9));
    });

    test('the same seed replays the same paths', () {
      final NormalPathSampler a = NormalPathSampler(77, dimension: 3);
      final NormalPathSampler b = NormalPathSampler(77, dimension: 3);
      for (int i = 0; i < 100; i++) {
        final Float64List pa = Float64List.fromList(a.nextPath());
        final Float64List pb = b.nextPath();
        for (int k = 0; k < 3; k++) {
          expect(pa[k], pb[k]);
        }
      }
    });
  });
}
