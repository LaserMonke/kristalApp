import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:optionsschool/pricing/barrier.dart';
import 'package:optionsschool/pricing/black_scholes.dart';
import 'package:optionsschool/pricing/monte_carlo.dart';

/// HOW A SIMULATION IS TESTED. A Monte Carlo price is random, so "equals the
/// right answer" is not a testable claim. What IS testable is that it lands
/// inside its own stated error bars — which tests both the price and the
/// error bar at once, and is the only check that would catch an engine that
/// is accurate but overconfident.
///
/// Every seed here is fixed, so these tests are deterministic: they pass
/// every time or they fail every time. A Monte Carlo test that passes four
/// runs in five is worse than no test at all.
void main() {
  const BsmInputs market = BsmInputs(
    spot: 100,
    strike: 100,
    rate: 0.05,
    volatility: 0.25,
    timeToExpiry: 1,
  );

  group('European by simulation vs the exact formula', () {
    // The calibration test for the whole engine. Black-Scholes-Merton already
    // answers this exactly, so any disagreement beyond sampling error is a
    // bug in the simulation — and everything else in Phase 8 rides on this
    // machinery being sound.
    test('call lands within 3 standard errors of the closed form', () {
      final double exact = bsmQuote(OptionType.call, market).price;
      final McEstimate mc = europeanMonteCarloPrice(
        OptionType.call,
        market,
        settings: const McSettings(paths: 200000, steps: 1, seed: 1),
      );

      expect(mc.standardError, greaterThan(0));
      expect((mc.price - exact).abs(), lessThan(3 * mc.standardError));
    });

    test('put lands within 3 standard errors of the closed form', () {
      final double exact = bsmQuote(OptionType.put, market).price;
      final McEstimate mc = europeanMonteCarloPrice(
        OptionType.put,
        market,
        settings: const McSettings(paths: 200000, steps: 1, seed: 2),
      );

      expect((mc.price - exact).abs(), lessThan(3 * mc.standardError));
    });

    test('the confidence interval brackets the true price', () {
      final double exact = bsmQuote(OptionType.call, market).price;
      final (double low, double high) = europeanMonteCarloPrice(
        OptionType.call,
        market,
        settings: const McSettings(paths: 100000, steps: 1, seed: 3),
      ).confidenceInterval95;

      expect(exact, greaterThan(low));
      expect(exact, lessThan(high));
    });

    test('deep out of the money still prices correctly', () {
      // The hardest case for a simulation: almost every path pays nothing,
      // so the answer comes from a thin slice of the sample. Getting this
      // wrong is how a Monte Carlo engine quietly under-prices tail risk.
      const BsmInputs otm = BsmInputs(
        spot: 100,
        strike: 160,
        rate: 0.05,
        volatility: 0.25,
        timeToExpiry: 1,
      );
      final double exact = bsmQuote(OptionType.call, otm).price;
      final McEstimate mc = europeanMonteCarloPrice(
        OptionType.call,
        otm,
        settings: const McSettings(paths: 400000, steps: 1, seed: 4),
      );

      expect(exact, greaterThan(0.3));
      expect((mc.price - exact).abs(), lessThan(3 * mc.standardError));
    });
  });

  group('error behaves the way the theory says', () {
    test('quadrupling the paths roughly halves the standard error', () {
      double errorFor(int paths) => europeanMonteCarloPrice(
        OptionType.call,
        market,
        settings: McSettings(paths: paths, steps: 1, seed: 11),
      ).standardError;

      final double coarse = errorFor(20000);
      final double fine = errorFor(80000);

      // 1/sqrt(4) = 0.5 exactly in theory; the sample standard deviation
      // itself wobbles, so this allows a generous band around it.
      expect(fine / coarse, closeTo(0.5, 0.08));
    });

    test('antithetic sampling shrinks the error at the same path count', () {
      const McSettings base = McSettings(paths: 100000, steps: 1, seed: 21);
      final McEstimate plain = europeanMonteCarloPrice(
        OptionType.call,
        market,
        settings: base.copyWith(antithetic: false),
      );
      final McEstimate paired = europeanMonteCarloPrice(
        OptionType.call,
        market,
        settings: base.copyWith(antithetic: true),
      );

      expect(paired.standardError, lessThan(plain.standardError));
      // Both must still find the same price — a variance reduction that
      // moved the answer would be a bias, not a reduction.
      final double exact = bsmQuote(OptionType.call, market).price;
      expect((paired.price - exact).abs(), lessThan(3 * paired.standardError));
    });

    test('antithetic pairing halves the independent observation count', () {
      final McEstimate paired = europeanMonteCarloPrice(
        OptionType.call,
        market,
        settings: const McSettings(paths: 10000, steps: 1, seed: 22),
      );
      // 10000 simulated paths, but only 5000 independent observations: the
      // error is computed from the pair averages, not from the paths.
      expect(paired.paths, 5000);
    });

    test('the same seed gives exactly the same price', () {
      const McSettings settings = McSettings(paths: 5000, steps: 1, seed: 99);
      final double a = europeanMonteCarloPrice(
        OptionType.call, market, settings: settings,
      ).price;
      final double b = europeanMonteCarloPrice(
        OptionType.call, market, settings: settings,
      ).price;
      expect(a, b);
    });

    test('a different seed gives a different — but compatible — price', () {
      final McEstimate a = europeanMonteCarloPrice(
        OptionType.call,
        market,
        settings: const McSettings(paths: 20000, steps: 1, seed: 100),
      );
      final McEstimate b = europeanMonteCarloPrice(
        OptionType.call,
        market,
        settings: const McSettings(paths: 20000, steps: 1, seed: 200),
      );

      expect(a.price, isNot(b.price));
      // Two honest estimates of the same quantity should agree within their
      // combined error.
      final double combined = math.sqrt(
        a.standardError * a.standardError + b.standardError * b.standardError,
      );
      expect((a.price - b.price).abs(), lessThan(3 * combined));
    });
  });

  group('barrier by simulation vs the closed form', () {
    const BsmInputs barrierMarket = BsmInputs(
      spot: 100,
      strike: 100,
      rate: 0.05,
      volatility: 0.25,
      timeToExpiry: 1,
    );
    const BarrierSpec downOut = BarrierSpec(
      type: OptionType.call,
      direction: BarrierDirection.down,
      style: BarrierStyle.knockOut,
      barrier: 85,
    );

    test('a discretely watched knock-out is worth MORE than a continuous one', () {
      // The central subtlety of barrier pricing. Watching the barrier only
      // 50 times a year lets the price dip below it and recover unnoticed,
      // so the option survives more often than the continuous formula
      // assumes — and survival is what a knock-out is worth.
      final double continuous = barrierPrice(downOut, barrierMarket);
      final McEstimate discrete = barrierMonteCarloPrice(
        downOut,
        barrierMarket,
        settings: const McSettings(paths: 40000, steps: 50, seed: 31),
      );

      expect(discrete.price, greaterThan(continuous));
      // And meaningfully so — this is a real economic difference, not noise.
      expect(discrete.price - continuous, greaterThan(3 * discrete.standardError));
    });

    test('the continuity correction reconciles the two', () {
      final double continuous = barrierPrice(downOut, barrierMarket);
      final McEstimate corrected = barrierMonteCarloPrice(
        downOut,
        barrierMarket,
        settings: const McSettings(paths: 60000, steps: 200, seed: 32),
        continuityCorrection: true,
      );

      // Broadie-Glasserman-Kou is an approximation, so a small residual bias
      // survives on top of the sampling error. Allowing 1% of the price for
      // it still leaves the check far tighter than the ~7% gap the previous
      // test measured without the correction.
      final double tolerance =
          4 * corrected.standardError + 0.01 * continuous;
      expect((corrected.price - continuous).abs(), lessThan(tolerance));
    });

    test('simulated in + out still adds back up to the vanilla', () {
      // Path by path, exactly one of the pair is alive — so with the same
      // seed the identity holds to floating-point precision, not merely
      // within sampling error.
      const McSettings settings = McSettings(paths: 20000, steps: 40, seed: 33);
      const BarrierSpec inTwin = BarrierSpec(
        type: OptionType.call,
        direction: BarrierDirection.down,
        style: BarrierStyle.knockIn,
        barrier: 85,
      );

      final double out = barrierMonteCarloPrice(
        downOut, barrierMarket, settings: settings,
      ).price;
      final double inside = barrierMonteCarloPrice(
        inTwin, barrierMarket, settings: settings,
      ).price;
      final McEstimate vanilla = europeanMonteCarloPrice(
        OptionType.call,
        barrierMarket,
        settings: const McSettings(paths: 20000, steps: 40, seed: 33),
      );

      expect(out + inside, closeTo(vanilla.price, 1e-9));
    });

    test('an already-breached barrier settles with no sampling error at all', () {
      const BarrierSpec breached = BarrierSpec(
        type: OptionType.call,
        direction: BarrierDirection.down,
        style: BarrierStyle.knockOut,
        barrier: 120,
      );
      final McEstimate mc = barrierMonteCarloPrice(breached, barrierMarket);

      expect(mc.price, 0);
      expect(mc.standardError, 0);
    });
  });

  group('Asian (average price)', () {
    test('averaging makes the option cheaper than its vanilla twin', () {
      // The average of a wandering price is steadier than its endpoint, and
      // an option on something steadier is worth less. This is the entire
      // economics of an Asian option in one inequality.
      final double vanilla = bsmQuote(OptionType.call, market).price;
      final McEstimate asian = asianMonteCarloPrice(
        OptionType.call,
        market,
        settings: const McSettings(paths: 40000, steps: 50, seed: 41),
      );

      expect(asian.price, lessThan(vanilla));
      expect(asian.price, greaterThan(0));
    });

    test('the arithmetic average is never below the geometric one', () {
      // True path by path (AM-GM inequality), so it holds for the prices too
      // when both use the same seed.
      const McSettings settings = McSettings(paths: 20000, steps: 40, seed: 42);
      final double arithmetic = asianMonteCarloPrice(
        OptionType.call, market, settings: settings,
      ).price;
      final double geometric = asianMonteCarloPrice(
        OptionType.call,
        market,
        settings: settings,
        average: AsianAverage.geometric,
      ).price;

      expect(arithmetic, greaterThanOrEqualTo(geometric));
    });
  });

  group('McEstimate', () {
    test('reports a 95% interval of +/- 1.96 standard errors', () {
      const McEstimate e = McEstimate(
        price: 10,
        standardError: 0.5,
        paths: 1000,
      );
      final (double low, double high) = e.confidenceInterval95;
      expect(low, closeTo(10 - 0.98, 1e-12));
      expect(high, closeTo(10 + 0.98, 1e-12));
      expect(e.relativeError, closeTo(0.05, 1e-12));
    });

    test('declines to quote a relative error on a zero price', () {
      // A knock-out that dies on every path is worth nothing, and "the error
      // is 20% of nothing" is not a statement worth showing anyone.
      const McEstimate e = McEstimate(price: 0, standardError: 0, paths: 100);
      expect(e.relativeError, isNull);
    });
  });
}
